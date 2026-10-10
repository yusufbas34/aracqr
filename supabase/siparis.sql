-- Basılı etiket siparişi: uygulamadan sipariş, size anında Telegram / e-posta bildirimi, yönetim panelinden takip.
-- Sürüm 3: uygulamada ödeme adımı yok; sipariş kaydedilir, siz müşteriyle iletişime geçersiniz.
-- Supabase > SQL Editor'da çalıştırın. Önce uygulama.sql kurulu olmalı. Mevcut tablolara dokunmaz; tekrar çalıştırmak güvenlidir.
-- Admin şifresi kontrolü için mevcut admin_list(p_key) fonksiyonunu kullanır.

-- Bildirimler (Telegram / e-posta) Supabase'in pg_net eklentisiyle gönderilir. Eklenti açılamazsa sipariş sistemi
-- yine çalışır, yalnızca bildirim gitmez.
do $$ begin
  create extension if not exists pg_net;
exception when others then raise notice 'pg_net açılamadı, bildirimler kapalı: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------- ayarlar (tek satır, panelden düzenlenir)
create table if not exists public.shop_settings (
  id integer primary key default 1 check (id = 1),
  active boolean not null default false,          -- IBAN girilip açılana kadar sipariş alınmaz
  price integer not null default 150,             -- TL
  iban text,
  account_name text,
  bank_name text,
  printer_email text,                             -- baskıcı: yalnızca panelde görünür
  shipping_text text not null default 'Kargo ücreti fiyata dahildir.',
  updated_at timestamptz
);
insert into public.shop_settings (id) values (1) on conflict (id) do nothing;
-- sürüm 2: bildirim ayarları (yalnızca panelde görünür)
alter table public.shop_settings add column if not exists telegram_bot_token text;
alter table public.shop_settings add column if not exists telegram_chat_id text;
alter table public.shop_settings add column if not exists resend_api_key text;
alter table public.shop_settings add column if not exists notify_email text;
alter table public.shop_settings enable row level security;
revoke all on public.shop_settings from anon, authenticated;

-- ---------------------------------------------------------------- siparişler
create table if not exists public.orders (
  id bigint generated always as identity primary key,
  code text not null unique,                      -- müşterinin gördüğü sipariş no, havale açıklaması (AQ-XXXXXX)
  token uuid not null default gen_random_uuid(),  -- müşterinin kendi siparişini sorgulaması için gizli anahtar
  created_at timestamptz not null default now(),
  tag_code text not null,                         -- self_tags.code: basılacak QR
  design text not null,
  full_name text not null,
  phone text not null,
  email text,
  city text not null,
  district text not null,
  address text not null,
  note text,
  amount integer not null,
  status text not null default 'yeni',
  paid_at timestamptz,                            -- müşterinin "ödemeyi yaptım" dediği an
  tracking text,
  admin_note text,
  device text,
  updated_at timestamptz
);
create index if not exists orders_created_idx on public.orders (created_at);
alter table public.orders enable row level security;
revoke all on public.orders from anon, authenticated;
-- sürüm 3: adres isteğe bağlı, yeni durum 'yeni' (iletişime geçilecek). Eski durumlar eski siparişler için geçerli kalır.
alter table public.orders alter column city drop not null;
alter table public.orders alter column district drop not null;
alter table public.orders alter column address drop not null;
alter table public.orders alter column status set default 'yeni';
alter table public.orders drop constraint if exists orders_status_check;
-- sürüm 4: iptal bilgisi (müşteri uygulamadan ya da yönetici panelden)
alter table public.orders add column if not exists phrase text;          -- sürüm 5: sticker sözü (shared/sticker.js PHRASES anahtarı)
alter table public.orders add column if not exists cancelled_by text;   -- 'musteri' | 'yonetici'
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists pdf_sent_at timestamptz;  -- sürüm 6: baskı PDF'i bildirimle gönderildi
alter table public.orders add constraint orders_status_check
  check (status in ('yeni', 'odeme_bekleniyor', 'odeme_bildirildi', 'onaylandi', 'baskida', 'kargolandi', 'iptal'));

create or replace function public.aracqr_shop_version() returns integer language sql immutable as 'select 6';

-- ---------------------------------------------------------------- bildirim
-- Telegram ve/veya e-posta (Resend) gönderir. Hata olursa siparişi bozmaz, yalnızca uyarı yazar.
create or replace function public.aracqr_notify(p_subject text, p_text text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  s shop_settings;
  sent boolean := false;
begin
  select * into s from shop_settings where id = 1;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return false; end if;
  if coalesce(s.telegram_bot_token, '') <> '' and coalesce(s.telegram_chat_id, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.telegram.org/bot' || s.telegram_bot_token || '/sendMessage',
            jsonb_build_object('chat_id', s.telegram_chat_id, 'text', p_subject || E'\n\n' || p_text),
            '{"Content-Type": "application/json"}'::jsonb;
    sent := true;
  end if;
  if coalesce(s.resend_api_key, '') <> '' and coalesce(s.notify_email, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.resend.com/emails',
            jsonb_build_object('from', 'Araç QR <onboarding@resend.dev>', 'to', jsonb_build_array(s.notify_email),
              'subject', p_subject, 'text', p_text),
            jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || s.resend_api_key);
    sent := true;
  end if;
  return sent;
exception when others then
  raise warning 'Araç QR bildirimi gönderilemedi: %', sqlerrm;
  return false;
end $$;
revoke all on function public.aracqr_notify(text, text) from public, anon, authenticated;  -- yalnızca içeriden

-- Müşteri "ödemeyi yaptım" deyince size haber verir
create or replace function public.orders_notify_paid()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.aracqr_notify('Araç QR: ödeme bildirimi ' || new.code,
    new.code || ' · ' || new.amount || ' TL' || E'\n' ||
    new.full_name || ' · ' || new.phone || E'\n' ||
    new.district || ' / ' || new.city || E'\n\n' ||
    'Hesabınızı kontrol edip panelden onaylayın: https://yusufbas34.github.io/aracqr/?admin');
  return new;
end $$;

-- Yeni sipariş gelince size haber verir: müşteriyle iletişime geçmeniz için tüm bilgiler
create or replace function public.orders_notify_new()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_wa text := 'https://wa.me/' || regexp_replace(new.phone, '[^0-9]', '', 'g');
begin
  perform public.aracqr_notify('Araç QR: yeni sipariş ' || new.code || ' · ' || new.amount || ' TL',
    '👤 ' || new.full_name || E'\n' ||
    '📞 ' || new.phone || '  (WhatsApp: ' || v_wa || ')' || E'\n' ||
    '✉️ ' || coalesce(new.email, '-') || E'\n' ||
    case when coalesce(new.address, '') <> '' or coalesce(new.city, '') <> '' then
      '📍 ' || concat_ws(', ', nullif(new.address, ''), nullif(concat_ws(' / ', nullif(new.district, ''), nullif(new.city, '')), '')) || E'\n'
    else '' end ||
    '🎨 Tasarım: ' || new.design || coalesce(' · söz: ' || new.phrase, '') || ' · QR: ' || new.tag_code || E'\n' ||
    case when new.note is not null then '📝 ' || new.note || E'\n' else '' end ||
    E'\nPanel: https://yusufbas34.github.io/aracqr/?admin');
  return new;
end $$;

drop trigger if exists orders_new_notify on public.orders;
create trigger orders_new_notify after insert on public.orders
  for each row execute function public.orders_notify_new();

drop trigger if exists orders_paid_notify on public.orders;
create trigger orders_paid_notify after update of status on public.orders
  for each row when (new.status = 'odeme_bildirildi' and old.status is distinct from new.status)
  execute function public.orders_notify_paid();

-- ---------------------------------------------------------------- sürüm 6: bildirimde baskı PDF'i
-- Veritabanı Telegram'a dosya yükleyemez (pg_net yalnızca JSON gönderir). Bu yüzden siparişi veren uygulama baskı PDF'ini
-- hazırlayıp Supabase Storage'a "siparis/AQ-XXXXXX-<gizli anahtar>.pdf" adıyla yükler; ardından order_pdf_ready çağrılır ve
-- PDF'in bağlantısı Telegram'a belge olarak (sendDocument), e-postaya ek olarak gönderilir. Adı yalnızca siparişi veren
-- telefonun bildiği gizli anahtarı içerdiği için tahmin edilemez. PDF'te yalnızca sticker'lar var, kişisel bilgi yok.
do $$ begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('aracqr-pdf', 'aracqr-pdf', true, 5242880, array['application/pdf'])
    on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['application/pdf'];
exception when others then raise notice 'Storage kovası oluşturulamadı, bildirimde PDF olmayacak: %', sqlerrm;
end $$;

create or replace function public.aracqr_project_url() returns text language sql immutable
  as $q$ select 'https://icedhptvywmqsiarxpio.supabase.co' $q$;

-- Yüklemeye yalnızca son 1 günün siparişi için, doğru gizli anahtarla izin verilir
create or replace function public.order_pdf_ok(p_name text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from orders o
    where p_name = 'siparis/' || o.code || '-' || o.token::text || '.pdf'
      and o.created_at > now() - interval '1 day' and o.pdf_sent_at is null);
$$;
revoke all on function public.order_pdf_ok(text) from public;
grant execute on function public.order_pdf_ok(text) to anon, authenticated;

do $$ begin
  drop policy if exists "aracqr siparis pdf yukleme" on storage.objects;
  create policy "aracqr siparis pdf yukleme" on storage.objects for insert to anon, authenticated
    with check (bucket_id = 'aracqr-pdf' and public.order_pdf_ok(name));
exception when others then raise notice 'Storage izni eklenemedi, bildirimde PDF olmayacak: %', sqlerrm;
end $$;

-- PDF yüklendi: Telegram'a belge, e-postaya ek olarak gönder (her sipariş için bir kez)
create or replace function public.order_pdf_ready(p_code text, p_token uuid)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  o orders;
  s shop_settings;
  v_name text;
  v_url text;
  v_caption text;
begin
  select * into o from orders where code = upper(trim(coalesce(p_code, ''))) and token = p_token for update;
  if not found then return json_build_object('ok', false, 'error', 'not_found'); end if;
  if o.pdf_sent_at is not null then return json_build_object('ok', true, 'already', true); end if;
  v_name := 'siparis/' || o.code || '-' || o.token::text || '.pdf';
  if not exists (select 1 from storage.objects where bucket_id = 'aracqr-pdf' and name = v_name) then
    return json_build_object('ok', false, 'error', 'no_file');
  end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return json_build_object('ok', false, 'error', 'no_pg_net'); end if;
  v_url := public.aracqr_project_url() || '/storage/v1/object/public/aracqr-pdf/' || v_name;
  v_caption := '🖨 Baskı PDF''i · ' || o.code || ' · ' || o.full_name || E'\nTasarım: ' || o.design || coalesce(' · söz: ' || o.phrase, '') || ' · QR: ' || o.tag_code;
  select * into s from shop_settings where id = 1;
  if coalesce(s.telegram_bot_token, '') <> '' and coalesce(s.telegram_chat_id, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.telegram.org/bot' || s.telegram_bot_token || '/sendDocument',
            jsonb_build_object('chat_id', s.telegram_chat_id, 'document', v_url, 'caption', v_caption),
            '{"Content-Type": "application/json"}'::jsonb;
  end if;
  if coalesce(s.resend_api_key, '') <> '' and coalesce(s.notify_email, '') <> '' then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.resend.com/emails',
            jsonb_build_object('from', 'Araç QR <onboarding@resend.dev>', 'to', jsonb_build_array(s.notify_email),
              'subject', 'Araç QR: baskı PDF''i ' || o.code, 'text', v_caption || E'\n\nPDF ektedir: ' || v_url,
              'attachments', jsonb_build_array(jsonb_build_object('filename', 'baski-' || o.code || '.pdf', 'path', v_url))),
            jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || s.resend_api_key);
  end if;
  update orders set pdf_sent_at = now() where id = o.id;
  return json_build_object('ok', true);
exception when others then
  raise warning 'Baskı PDF bildirimi gönderilemedi: %', sqlerrm;
  return json_build_object('ok', false, 'error', 'failed');
end $$;
revoke all on function public.order_pdf_ready(text, uuid) from public;
grant execute on function public.order_pdf_ready(text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------- herkese açık
-- Uygulamanın göstereceği satış bilgileri (baskıcı e-postası hariç)
create or replace function public.shop_info()
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object('active', active,
    'price', price, 'iban', iban, 'account_name', account_name, 'bank_name', bank_name, 'shipping_text', shipping_text)
  from shop_settings where id = 1;
$$;

drop function if exists public.order_create(text, text, text, text, text, text, text, text, text, text);  -- sürüm 4 imzası
create or replace function public.order_create(
  p_tag_code text, p_design text, p_full_name text, p_phone text, p_email text,
  p_city text, p_district text, p_address text, p_note text default null, p_device text default null, p_phrase text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  s shop_settings;
  v_tag text := upper(trim(coalesce(p_tag_code, '')));
  v_design text := left(lower(trim(coalesce(p_design, ''))), 20);
  v_name text := left(trim(coalesce(p_full_name, '')), 80);
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_email text := lower(left(trim(coalesce(p_email, '')), 120));
  v_city text := nullif(left(trim(coalesce(p_city, '')), 40), '');
  v_district text := nullif(left(trim(coalesce(p_district, '')), 60), '');
  v_address text := nullif(left(trim(coalesce(p_address, '')), 400), '');
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_device text := nullif(left(trim(coalesce(p_device, '')), 64), '');
  v_phrase text := nullif(lower(trim(coalesce(p_phrase, ''))), '');
  v_code text;
  o orders;
begin
  select * into s from shop_settings where id = 1;
  if not s.active then return json_build_object('ok', false, 'error', 'closed'); end if;
  if not exists (select 1 from self_tags where code = v_tag) then return json_build_object('ok', false, 'error', 'no_tag'); end if;
  if v_design !~ '^[a-z]{2,20}$' then v_design := 'klasik'; end if;
  if v_phrase !~ '^[a-z0-9_]{1,20}$' then v_phrase := null; end if;  -- yalnızca anahtar; metin uygulamada
  if length(v_name) < 3 then return json_build_object('ok', false, 'error', 'missing'); end if;
  if v_phone !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  -- kötüye kullanım sınırları: cihaz / telefon başına günde 5, genelde dakikada 20 sipariş
  if (select count(*) from orders where (phone = v_phone or (v_device is not null and device = v_device))
        and created_at > now() - interval '1 day') >= 5
    then return json_build_object('ok', false, 'error', 'too_many'); end if;
  if (select count(*) from orders where created_at > now() - interval '1 minute') >= 20
    then return json_build_object('ok', false, 'error', 'busy'); end if;
  loop
    v_code := 'AQ-' || translate(upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)), '01', 'XY');
    exit when not exists (select 1 from orders where code = v_code);
  end loop;
  insert into orders (code, tag_code, design, phrase, full_name, phone, email, city, district, address, note, amount, device)
    values (v_code, v_tag, v_design, v_phrase, v_name, v_phone, v_email, v_city, v_district, v_address, v_note, s.price, v_device)
    returning * into o;
  return json_build_object('ok', true, 'code', o.code, 'token', o.token, 'amount', o.amount, 'status', o.status);
end $$;

-- Müşteri "ödemeyi yaptım" der
create or replace function public.order_paid(p_code text, p_token uuid)
returns json
language plpgsql security definer set search_path = public
as $$
declare o orders;
begin
  update orders set status = 'odeme_bildirildi', paid_at = now(), updated_at = now()
    where code = upper(trim(p_code)) and token = p_token and status = 'odeme_bekleniyor'
    returning * into o;
  if not found then
    select * into o from orders where code = upper(trim(p_code)) and token = p_token;
    if not found then return json_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  return json_build_object('ok', true, 'status', o.status);
end $$;

-- Müşteri kendi siparişlerinin durumunu sorgular: [{code, status, tracking}]
-- Müşteri kendi siparişini iptal eder: yalnızca henüz onaylanmamışsa. {ok, status} ya da {ok:false, error:'too_late'|'not_found'}
create or replace function public.order_cancel(p_code text, p_token uuid)
returns json
language plpgsql security definer set search_path = public
as $$
declare o orders;
begin
  select * into o from orders where code = upper(trim(coalesce(p_code, ''))) and token = p_token for update;
  if not found then return json_build_object('ok', false, 'error', 'not_found'); end if;
  if o.status = 'iptal' then return json_build_object('ok', true, 'status', 'iptal'); end if;
  if o.status not in ('yeni', 'odeme_bekleniyor', 'odeme_bildirildi') then
    return json_build_object('ok', false, 'error', 'too_late', 'status', o.status);
  end if;
  update orders set status = 'iptal', cancelled_by = 'musteri', cancelled_at = now(), updated_at = now() where id = o.id;
  perform public.aracqr_notify('Araç QR: sipariş iptal edildi ' || o.code,
    o.full_name || ' (' || o.phone || ') ' || o.code || ' numaralı siparişini uygulamadan iptal etti.' || E'\n\n' ||
    'Panel: https://yusufbas34.github.io/aracqr/?admin');
  return json_build_object('ok', true, 'status', 'iptal');
end $$;

create or replace function public.order_status(p_codes text[], p_tokens uuid[])
returns json
language sql stable security definer set search_path = public
as $$
  select coalesce(json_agg(json_build_object('code', o.code, 'status', o.status, 'tracking', o.tracking, 'cancelled_by', o.cancelled_by)), '[]'::json)
  from unnest(p_codes, p_tokens) as q(code, token)
  join orders o on o.code = upper(trim(q.code)) and o.token = q.token;
$$;

-- ---------------------------------------------------------------- yönetim
create or replace function public.admin_shop_get(p_key text)
returns setof public.shop_settings
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select * from shop_settings where id = 1;
end $$;

drop function if exists public.admin_shop_set(text, boolean, integer, text, text, text, text, text);  -- sürüm 1 imzası
create or replace function public.admin_shop_set(p_key text, p_active boolean, p_price integer, p_iban text,
  p_account_name text, p_bank_name text, p_printer_email text, p_shipping_text text,
  p_telegram_bot_token text default null, p_telegram_chat_id text default null,
  p_resend_api_key text default null, p_notify_email text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  update shop_settings set
    active = coalesce(p_active, false),
    price = greatest(coalesce(p_price, 150), 0),
    iban = nullif(upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g')), ''),
    account_name = nullif(trim(coalesce(p_account_name, '')), ''),
    bank_name = nullif(trim(coalesce(p_bank_name, '')), ''),
    printer_email = nullif(trim(coalesce(p_printer_email, '')), ''),
    shipping_text = coalesce(nullif(trim(coalesce(p_shipping_text, '')), ''), 'Kargo ücreti fiyata dahildir.'),
    telegram_bot_token = nullif(trim(coalesce(p_telegram_bot_token, '')), ''),
    telegram_chat_id = nullif(trim(coalesce(p_telegram_chat_id, '')), ''),
    resend_api_key = nullif(trim(coalesce(p_resend_api_key, '')), ''),
    notify_email = nullif(trim(coalesce(p_notify_email, '')), ''),
    updated_at = now()
  where id = 1;
end $$;

-- Yönetim: deneme bildirimi. {sent: gönderildi mi, pg_net: eklenti var mı}
create or replace function public.admin_notify_test(p_key text)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return json_build_object('pg_net', to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null,
    'sent', public.aracqr_notify('Araç QR: deneme bildirimi', 'Bildirimler çalışıyor. Yeni ödeme bildirimleri buraya gelecek.'));
end $$;

create or replace function public.admin_orders(p_key text)
returns setof public.orders
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select * from orders order by created_at desc;
end $$;

create or replace function public.admin_order_update(p_key text, p_id bigint, p_status text, p_tracking text, p_admin_note text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  update orders set status = p_status, tracking = nullif(trim(coalesce(p_tracking, '')), ''),
    admin_note = nullif(trim(coalesce(p_admin_note, '')), ''), updated_at = now(),
    cancelled_by = case when p_status = 'iptal' then coalesce(cancelled_by, 'yonetici') else null end,
    cancelled_at = case when p_status = 'iptal' then coalesce(cancelled_at, now()) else null end
  where id = p_id;
end $$;

revoke all on function public.shop_info() from public;
revoke all on function public.order_create(text, text, text, text, text, text, text, text, text, text, text) from public;
revoke all on function public.order_paid(text, uuid) from public;
revoke all on function public.order_status(text[], uuid[]) from public;
revoke all on function public.order_cancel(text, uuid) from public;
revoke all on function public.admin_shop_get(text) from public;
revoke all on function public.admin_shop_set(text, boolean, integer, text, text, text, text, text, text, text, text, text) from public;
revoke all on function public.admin_notify_test(text) from public;
revoke all on function public.admin_orders(text) from public;
revoke all on function public.admin_order_update(text, bigint, text, text, text) from public;
grant execute on function public.aracqr_shop_version() to anon, authenticated;
grant execute on function public.shop_info() to anon, authenticated;
grant execute on function public.order_create(text, text, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.order_paid(text, uuid) to anon, authenticated;
grant execute on function public.order_status(text[], uuid[]) to anon, authenticated;
grant execute on function public.order_cancel(text, uuid) to anon, authenticated;
grant execute on function public.admin_shop_get(text) to anon, authenticated;
grant execute on function public.admin_shop_set(text, boolean, integer, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_notify_test(text) to anon, authenticated;
grant execute on function public.admin_orders(text) to anon, authenticated;
grant execute on function public.admin_order_update(text, bigint, text, text, text) to anon, authenticated;
