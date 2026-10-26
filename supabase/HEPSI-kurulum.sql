-- Araç QR: TÜM veritabanı kurulumu tek dosyada (uygulama, sipariş, yorum, talep, verildi, PIN kurtarma).
-- Supabase > SQL Editor'a hepsini yapıştırıp Run'a basın. Mevcut verilere dokunmaz; tekrar çalıştırmak güvenlidir.
-- "Potential issue detected / RLS" uyarısı çıkarsa "Run without RLS" seçin (tablolarda RLS zaten açılıyor).
-- Bu dosya supabase/*.sql dosyalarından üretilir; tek tek dosyalar da aynı içeriktir.

-- ================================================================ uygulama.sql
-- Mobil uygulama: kullanıcının kendi oluşturduğu QR etiketleri.
-- Supabase > SQL Editor'da çalıştırın. Mevcut tablolara dokunmaz, yalnızca ekleme yapar; tekrar çalıştırmak güvenlidir.
-- Bu etiketlerin QR'ı sitede ?s=KOD adresini açar (yönetimden üretilen etiketler ?k=KOD kullanır).

create table if not exists public.self_tags (
  code text primary key,
  pin text not null,
  phone text not null,
  device text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  fail_count integer not null default 0,
  locked_until timestamptz
);
create index if not exists self_tags_created_idx on public.self_tags (created_at);
-- sürüm 2: yedek numara ve sessiz saatler (dakika, Türkiye saati; ikisi de boşsa kapalı)
alter table public.self_tags add column if not exists backup_phone text;
alter table public.self_tags add column if not exists backup_name text;
alter table public.self_tags add column if not exists quiet_start smallint;
alter table public.self_tags add column if not exists quiet_end smallint;
-- sürüm 3: sahibi QR'ı geçici olarak kapatabilir (araç satıldı, etiket kayboldu, tatil…)
alter table public.self_tags add column if not exists disabled boolean not null default false;

-- okutma sayacı: yalnızca kod ve zaman tutulur (IP, cihaz vb. tutulmaz)
create table if not exists public.self_tag_scans (
  id bigint generated always as identity primary key,
  code text not null,
  scanned_at timestamptz not null default now()
);
create index if not exists self_tag_scans_code_idx on public.self_tag_scans (code, scanned_at);
alter table public.self_tag_scans enable row level security;
revoke all on public.self_tag_scans from anon, authenticated;
alter table public.self_tags enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.self_tags from anon, authenticated;

create or replace function public.aracqr_app_version() returns integer language sql immutable as 'select 5';

-- Yeni etiket oluşturur: {ok:true, code, pin} ya da {ok:false, error}
create or replace function public.self_tag_create(p_phone text, p_device text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_device text := nullif(left(trim(coalesce(p_device, '')), 64), '');
  v_hex text;
  v_code text;
  v_pin text;
begin
  if v_phone !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  -- kötüye kullanım sınırları: cihaz başına günde 10, numara başına günde 5, genelde dakikada 30
  if v_device is not null and (select count(*) from self_tags where device = v_device and created_at > now() - interval '1 day') >= 10
    then return json_build_object('ok', false, 'error', 'too_many'); end if;
  if (select count(*) from self_tags where phone = v_phone and created_at > now() - interval '1 day') >= 5
    then return json_build_object('ok', false, 'error', 'too_many'); end if;
  if (select count(*) from self_tags where created_at > now() - interval '1 minute') >= 30
    then return json_build_object('ok', false, 'error', 'busy'); end if;
  loop
    v_hex := upper(replace(gen_random_uuid()::text, '-', ''));  -- kriptografik rastgele
    v_code := 'S' || translate(substr(v_hex, 1, 7), '01', 'XY');  -- 0/1, O/I ile karışmasın
    exit when not exists (select 1 from self_tags where code = v_code);
  end loop;
  v_pin := lpad(((('x' || substr(v_hex, 17, 8))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into self_tags(code, pin, phone, device) values (v_code, v_pin, v_phone, v_device);
  return json_build_object('ok', true, 'code', v_code, 'pin', v_pin);
end $$;

-- QR okutulunca: {exists, phone, backup_phone, backup_name, quiet_start, quiet_end}. Okutmayı sayar
-- (aynı koda 30 saniye içindeki tekrarlar, ör. sayfayı yenileme, sayılmaz).
create or replace function public.self_tag_lookup(p_code text)
returns json
language plpgsql volatile security definer set search_path = public
as $$
declare t self_tags;
begin
  select * into t from self_tags where code = upper(trim(coalesce(p_code, '')));
  if not found then return json_build_object('exists', false); end if;
  if t.disabled then return json_build_object('exists', true, 'disabled', true); end if;  -- numara gösterilmez
  if not exists (select 1 from self_tag_scans where code = t.code and scanned_at > now() - interval '30 seconds') then
    insert into self_tag_scans (code) values (t.code);
  end if;
  return json_build_object('exists', true, 'phone', t.phone, 'backup_phone', t.backup_phone, 'backup_name', t.backup_name,
    'quiet_start', t.quiet_start, 'quiet_end', t.quiet_end);
end $$;

-- PIN kontrolü: doğruysa null, değilse hata kodu döner. 5 yanlış denemede 15 dakika kilit.
create or replace function public.self_tag_check_pin(p_code text, p_pin text)
returns text
language plpgsql security definer set search_path = public
as $$
declare t self_tags;
begin
  select * into t from self_tags where code = upper(trim(coalesce(p_code, ''))) for update;
  if not found then return 'not_found'; end if;
  if t.locked_until > now() then return 'locked'; end if;
  if t.pin <> trim(coalesce(p_pin, '')) then
    update self_tags set
      fail_count = case when t.fail_count + 1 >= 5 then 0 else t.fail_count + 1 end,
      locked_until = case when t.fail_count + 1 >= 5 then now() + interval '15 minutes' else null end
      where code = t.code;
    return 'bad_pin';
  end if;
  update self_tags set fail_count = 0, locked_until = null where code = t.code and fail_count <> 0;
  return null;
end $$;

-- Numara değiştirme (PIN ile)
create or replace function public.self_tag_save(p_code text, p_pin text, p_phone text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_err text := public.self_tag_check_pin(v_code, p_pin);
begin
  if v_err = 'locked' then
    return json_build_object('ok', false, 'error', 'locked',
      'minutes', (select ceil(extract(epoch from locked_until - now()) / 60) from self_tags where code = v_code));
  end if;
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  if v_phone !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  update self_tags set phone = v_phone, updated_at = now() where code = v_code;
  return json_build_object('ok', true, 'phone', v_phone);
end $$;

-- Yedek numara ve sessiz saatler (PIN ile). Boş yedek numara = kaldır; sessiz saatlerin ikisi de null = kapalı.
create or replace function public.self_tag_settings(p_code text, p_pin text, p_backup_phone text, p_backup_name text,
  p_quiet_start integer, p_quiet_end integer)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_backup text := nullif(regexp_replace(coalesce(p_backup_phone, ''), '[^0-9+]', '', 'g'), '');
  v_name text := nullif(left(trim(coalesce(p_backup_name, '')), 40), '');
  v_err text := public.self_tag_check_pin(v_code, p_pin);
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  if v_backup is not null and v_backup !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  if (p_quiet_start is null) <> (p_quiet_end is null)
     or p_quiet_start not between 0 and 1439 or p_quiet_end not between 0 and 1439 or p_quiet_start = p_quiet_end then
    return json_build_object('ok', false, 'error', 'bad_hours');
  end if;
  update self_tags set backup_phone = v_backup, backup_name = case when v_backup is null then null else v_name end,
    quiet_start = p_quiet_start, quiet_end = p_quiet_end, updated_at = now()
    where code = v_code;
  return json_build_object('ok', true);
end $$;

-- QR'ı kapat / aç (PIN ile). {ok, disabled}
create or replace function public.self_tag_set_active(p_code text, p_pin text, p_active boolean)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  update self_tags set disabled = not coalesce(p_active, true), updated_at = now() where code = v_code;
  return json_build_object('ok', true, 'disabled', not coalesce(p_active, true));
end $$;

-- Okutma istatistikleri (yalnızca PIN'i bilen sahibine): [{code, total, last30, last}]
create or replace function public.self_tag_stats(p_codes text[], p_pins text[])
returns json
language sql stable security definer set search_path = public
as $$
  select coalesce(json_agg(json_build_object('code', t.code,
      'total', (select count(*) from self_tag_scans s where s.code = t.code),
      'last30', (select count(*) from self_tag_scans s where s.code = t.code and s.scanned_at > now() - interval '30 days'),
      'last', (select max(scanned_at) from self_tag_scans s where s.code = t.code))), '[]'::json)
  from unnest(p_codes, p_pins) as q(code, pin)
  join self_tags t on t.code = upper(trim(q.code)) and t.pin = trim(q.pin);
$$;

-- sürüm 4: QR'ı ve okutma kayıtlarını kalıcı olarak siler (PIN ile). Silinen kod okutulunca "kayıtlı değil" görünür
-- ve bir daha kimseye verilmez (kod rastgele üretilir; aynı kodun yeniden çıkma olasılığı yok denecek kadar azdır).
create or replace function public.self_tag_delete(p_code text, p_pin text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
begin
  if v_err = 'not_found' then return json_build_object('ok', true, 'already', true); end if;  -- zaten silinmiş
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  delete from self_tag_scans where code = v_code;
  delete from self_tags where code = v_code;
  return json_build_object('ok', true);
end $$;

-- Yönetim: uygulamadan oluşturulan etiketler (PIN'ler gösterilmez)
create or replace function public.admin_self_tags(p_key text)
returns table (code text, phone text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select s.code, s.phone, s.created_at, s.updated_at from public.self_tags s order by s.created_at desc;
end $$;

revoke all on function public.self_tag_create(text, text) from public;
revoke all on function public.self_tag_lookup(text) from public;
revoke all on function public.self_tag_save(text, text, text) from public;
revoke all on function public.admin_self_tags(text) from public;
revoke all on function public.self_tag_check_pin(text, text) from public, anon, authenticated;  -- yalnızca içeriden
revoke all on function public.self_tag_settings(text, text, text, text, integer, integer) from public;
revoke all on function public.self_tag_stats(text[], text[]) from public;
revoke all on function public.self_tag_set_active(text, text, boolean) from public;
revoke all on function public.self_tag_delete(text, text) from public;
grant execute on function public.self_tag_delete(text, text) to anon, authenticated;
grant execute on function public.self_tag_set_active(text, text, boolean) to anon, authenticated;
grant execute on function public.self_tag_settings(text, text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.self_tag_stats(text[], text[]) to anon, authenticated;
grant execute on function public.aracqr_app_version() to anon, authenticated;
grant execute on function public.self_tag_create(text, text) to anon, authenticated;
grant execute on function public.self_tag_lookup(text) to anon, authenticated;
grant execute on function public.self_tag_save(text, text, text) to anon, authenticated;
grant execute on function public.admin_self_tags(text) to anon, authenticated;

-- ---------------------------------------------------------------- sürüm 5: otomatik yedek
-- Android uygulaması QR listesini (kod, PIN, tasarım…) ve sipariş numaralarını, telefona ve uygulamaya özel gizli bir
-- anahtarla (Android kimliğinden türetilen SHA-256) burada yedekler. Uygulama silinip aynı telefona yeniden kurulunca
-- anahtar aynı kalır ve QR'lar kendiliğinden geri gelir. Anahtarı yalnızca o telefondaki uygulama bilir.
create table if not exists public.device_backups (
  owner_key text primary key check (owner_key ~ '^[0-9a-f]{64}$'),
  data jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.device_backups enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.device_backups from anon, authenticated;

create or replace function public.backup_save(p_key text, p_data jsonb)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(p_key, '') !~ '^[0-9a-f]{64}$' then return json_build_object('ok', false, 'error', 'key'); end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text) > 200000 then
    return json_build_object('ok', false, 'error', 'data');
  end if;
  insert into device_backups (owner_key, data) values (p_key, p_data)
    on conflict (owner_key) do update set data = excluded.data, updated_at = now();
  return json_build_object('ok', true);
end $$;

create or replace function public.backup_load(p_key text)
returns jsonb
language sql stable security definer set search_path = public
as $$ select data from device_backups where owner_key = p_key $$;

create or replace function public.backup_delete(p_key text)
returns void
language sql security definer set search_path = public
as $$ delete from device_backups where owner_key = p_key $$;

revoke all on function public.backup_save(text, jsonb) from public;
revoke all on function public.backup_load(text) from public;
revoke all on function public.backup_delete(text) from public;
grant execute on function public.backup_save(text, jsonb) to anon, authenticated;
grant execute on function public.backup_load(text) to anon, authenticated;
grant execute on function public.backup_delete(text) to anon, authenticated;

-- ================================================================ siparis.sql
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
  price integer not null default 200,             -- TL
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
-- sürüm 10: e-postaların gönderen adresi (Resend'de doğrulanmış alan adı, ör. Araç QR <pin@bulqr.com.tr>).
-- Boşken onboarding@resend.dev kullanılır; o adres yalnızca Resend hesabının sahibine e-posta gönderebilir.
alter table public.shop_settings add column if not exists mail_from text;
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
-- sürüm 8: sipariş müşterinin seçtiği ölçüde 1 sticker (ör. '40x60' = 4×6 cm). Boşsa eski set (6 ölçü, 9 sticker).
alter table public.orders add column if not exists size text;
-- '40x60' → '4×6 cm', '55x85' → '5,5×8,5 cm'
create or replace function public.aracqr_cm(p_size text) returns text language sql immutable as $q$
  select replace(trim_scale(split_part(p_size, 'x', 1)::numeric / 10)::text, '.', ',') || '×' ||
         replace(trim_scale(split_part(p_size, 'x', 2)::numeric / 10)::text, '.', ',') || ' cm'
$q$;
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

create or replace function public.aracqr_shop_version() returns integer language sql immutable as 'select 10';

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
            jsonb_build_object('from', coalesce(nullif(trim(s.mail_from), ''), 'Araç QR <onboarding@resend.dev>'), 'to', jsonb_build_array(s.notify_email),
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
    'Hesabınızı kontrol edip panelden onaylayın: https://arac.bulqr.com.tr/?admin');
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
    '📐 ' || coalesce('1 adet sticker, ' || public.aracqr_cm(new.size), 'A4 set (6 ölçü, 9 sticker)') || E'\n' ||
    case when new.note is not null then '📝 ' || new.note || E'\n' else '' end ||
    E'\nPanel: https://arac.bulqr.com.tr/?admin');
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
      and o.created_at > now() - interval '30 days' and o.pdf_sent_at is null);  -- sürüm 9: panelden sonradan da gönderilebilsin
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
  v_caption := '🖨 Baskı PDF''i · ' || o.code || ' · ' || o.full_name || E'\nTasarım: ' || o.design || coalesce(' · söz: ' || o.phrase, '') || ' · QR: ' || o.tag_code ||
    E'\nÖlçü: ' || coalesce('1 adet, ' || public.aracqr_cm(o.size), '6 ölçü set');
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
            jsonb_build_object('from', coalesce(nullif(trim(s.mail_from), ''), 'Araç QR <onboarding@resend.dev>'), 'to', jsonb_build_array(s.notify_email),
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

-- ---------------------------------------------------------------- sürüm 7: yönetim istatistikleri
-- QR, okutma ve sipariş sayıları, ciro (onaylanan, baskıdaki ve kargolanan siparişler) ve son 14 günün günlük dökümü
create or replace function public.admin_stats(p_key text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  v_month timestamptz := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  v_paid text[] := array['onaylandi', 'baskida', 'kargolandi'];
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return json_build_object(
    'qr_total', (select count(*) from self_tags),
    'qr_7', (select count(*) from self_tags where created_at > now() - interval '7 days'),
    'qr_off', (select count(*) from self_tags where disabled),
    'scan_total', (select count(*) from self_tag_scans),
    'scan_7', (select count(*) from self_tag_scans where scanned_at > now() - interval '7 days'),
    'scan_30', (select count(*) from self_tag_scans where scanned_at > now() - interval '30 days'),
    'qr_scanned', (select count(distinct code) from self_tag_scans),
    'order_total', (select count(*) from orders),
    'order_7', (select count(*) from orders where created_at > now() - interval '7 days'),
    'order_open', (select count(*) from orders where status in ('yeni', 'odeme_bekleniyor', 'odeme_bildirildi')),
    'order_cancel', (select count(*) from orders where status = 'iptal'),
    'revenue_total', (select coalesce(sum(amount), 0) from orders where status = any(v_paid)),
    'revenue_month', (select coalesce(sum(amount), 0) from orders where status = any(v_paid) and created_at >= v_month),
    'paid_total', (select count(*) from orders where status = any(v_paid)),
    'days', (select json_agg(json_build_object('day', d,
        'qr', (select count(*) from self_tags where (created_at at time zone 'Europe/Istanbul')::date = d),
        'scan', (select count(*) from self_tag_scans where (scanned_at at time zone 'Europe/Istanbul')::date = d),
        'order', (select count(*) from orders where (created_at at time zone 'Europe/Istanbul')::date = d)) order by d)
      from generate_series(v_today - 13, v_today, interval '1 day') g(d0), lateral (select g.d0::date as d) x));
end $$;
revoke all on function public.admin_stats(text) from public;
grant execute on function public.admin_stats(text) to anon, authenticated;

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
drop function if exists public.order_create(text, text, text, text, text, text, text, text, text, text, text);  -- sürüm 7 imzası
create or replace function public.order_create(
  p_tag_code text, p_design text, p_full_name text, p_phone text, p_email text,
  p_city text, p_district text, p_address text, p_note text default null, p_device text default null, p_phrase text default null,
  p_size text default null)
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
  v_size text := case when p_size in ('40x60', '50x75', '55x85', '60x90', '74x105', '80x120') then p_size else '60x90' end;
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
  insert into orders (code, tag_code, design, phrase, size, full_name, phone, email, city, district, address, note, amount, device)
    values (v_code, v_tag, v_design, v_phrase, v_size, v_name, v_phone, v_email, v_city, v_district, v_address, v_note, s.price, v_device)
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
    'Panel: https://arac.bulqr.com.tr/?admin');
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
revoke all on function public.order_create(text, text, text, text, text, text, text, text, text, text, text, text) from public;
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
grant execute on function public.order_create(text, text, text, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.order_paid(text, uuid) to anon, authenticated;
grant execute on function public.order_status(text[], uuid[]) to anon, authenticated;
grant execute on function public.order_cancel(text, uuid) to anon, authenticated;
grant execute on function public.admin_shop_get(text) to anon, authenticated;
grant execute on function public.admin_shop_set(text, boolean, integer, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_notify_test(text) to anon, authenticated;
grant execute on function public.admin_orders(text) to anon, authenticated;
grant execute on function public.admin_order_update(text, bigint, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------- sürüm 9: baskı PDF'ini panelden gönderme ve hata ayıklama
-- Panel, siparişin PDF'ini yeniden hazırlayıp yükler ve order_pdf_ready ile Telegram / e-postaya gönderir.
-- Daha önce gönderildi işaretliyse önce bu işaret kaldırılır.
create or replace function public.admin_order_pdf_reset(p_key text, p_id bigint)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  update orders set pdf_sent_at = null where id = p_id;
end $$;

-- Son dış istek sonuçları (Telegram / Resend): gönderim neden olmadı görmek için. pg_net yoksa boş döner.
create or replace function public.admin_net_log(p_key text)
returns table (id bigint, status_code integer, content text, error_msg text, created timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  if to_regclass('net._http_response') is null then return; end if;
  return query execute 'select r.id, r.status_code, left(r.content::text, 400), r.error_msg, r.created
    from net._http_response r order by r.id desc limit 8';
end $$;

revoke all on function public.admin_order_pdf_reset(text, bigint) from public;
revoke all on function public.admin_net_log(text) from public;
grant execute on function public.admin_order_pdf_reset(text, bigint) to anon, authenticated;
grant execute on function public.admin_net_log(text) to anon, authenticated;

-- ================================================================ yorum.sql
-- Kullanıcı yorumları: uygulamadan puan, yorum ve isteğe bağlı fotoğraf; yönetim panelinden onaylanınca sitede ve uygulamada görünür.
-- Supabase > SQL Editor'da çalıştırın. Önce uygulama.sql kurulu olmalı. Mevcut tablolara dokunmaz; tekrar çalıştırmak güvenlidir.
-- Yalnızca uygulamada QR'ı olan kişi (QR kodu + PIN) yorum yazabilir; her QR için tek yorum (yeniden yazınca güncellenir
-- ve tekrar onaya düşer). Hiçbir yorum onaylanmadan yayınlanmaz.

create table if not exists public.reviews (
  id bigint generated always as identity primary key,
  tag_code text not null unique,                  -- self_tags.code: yorumu yazan kullanıcının QR'ı
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  name text not null,                             -- herkese görünen ad (ör. "Yusuf B.")
  city text,
  rating smallint not null check (rating between 1 and 5),
  comment text not null,
  photo text,                                     -- Storage'daki dosya adı (yorum/<id>-<anahtar>.jpg)
  photo_token uuid,                               -- fotoğraf yüklemesi için tek seferlik gizli anahtar
  status text not null default 'bekliyor' check (status in ('bekliyor', 'yayinda', 'gizli')),
  lang text
);
create index if not exists reviews_status_idx on public.reviews (status, created_at);
alter table public.reviews enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.reviews from anon, authenticated;

-- siparis.sql ile aynı (kurulu değilse de çalışsın)
create or replace function public.aracqr_project_url() returns text language sql immutable
  as $q$ select 'https://icedhptvywmqsiarxpio.supabase.co' $q$;

create or replace function public.aracqr_reviews_version() returns integer language sql immutable as 'select 1';

-- Fotoğraflar herkese açık kovada; adları tahmin edilemez. Yalnızca resim, en fazla 3 MB.
do $$ begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('aracqr-yorum', 'aracqr-yorum', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = true, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
exception when others then raise notice 'Storage kovası oluşturulamadı, yorumlarda fotoğraf olmayacak: %', sqlerrm;
end $$;

-- Yüklemeye yalnızca son 1 saatte yazılmış, fotoğrafı henüz olmayan yorum için, doğru gizli anahtarla izin verilir
create or replace function public.review_photo_ok(p_name text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from reviews r
    where r.photo_token is not null and r.photo is null
      and p_name = 'yorum/' || r.id || '-' || r.photo_token::text || '.jpg'
      and coalesce(r.updated_at, r.created_at) > now() - interval '1 hour');
$$;
revoke all on function public.review_photo_ok(text) from public;
grant execute on function public.review_photo_ok(text) to anon, authenticated;

do $$ begin
  drop policy if exists "aracqr yorum fotograf yukleme" on storage.objects;
  create policy "aracqr yorum fotograf yukleme" on storage.objects for insert to anon, authenticated
    with check (bucket_id = 'aracqr-yorum' and public.review_photo_ok(name));
exception when others then raise notice 'Storage izni eklenemedi, yorumlarda fotoğraf olmayacak: %', sqlerrm;
end $$;

-- Yorum yaz / güncelle: {ok, id, photo_name?} ya da {ok:false, error}
-- p_photo true ise dönen photo_name adıyla fotoğraf yüklenir, sonra review_photo_ready çağrılır.
create or replace function public.review_submit(p_code text, p_pin text, p_name text, p_city text,
  p_rating integer, p_comment text, p_photo boolean default false, p_lang text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
  v_name text := left(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 40);
  v_city text := nullif(left(trim(coalesce(p_city, '')), 30), '');
  v_comment text := left(trim(coalesce(p_comment, '')), 600);
  v_token uuid := case when p_photo then gen_random_uuid() end;
  r reviews;
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  if p_rating is null or p_rating not between 1 and 5 then return json_build_object('ok', false, 'error', 'rating'); end if;
  if length(v_name) < 2 then return json_build_object('ok', false, 'error', 'name'); end if;
  if length(v_comment) < 5 then return json_build_object('ok', false, 'error', 'comment'); end if;
  insert into reviews (tag_code, name, city, rating, comment, photo_token, lang)
    values (v_code, v_name, v_city, p_rating, v_comment, v_token, left(p_lang, 5))
  on conflict (tag_code) do update set name = excluded.name, city = excluded.city, rating = excluded.rating,
    comment = excluded.comment, photo = null, photo_token = excluded.photo_token, lang = excluded.lang,
    status = 'bekliyor', updated_at = now()
  returning * into r;
  begin
    perform public.aracqr_notify('Araç QR: yeni yorum (' || r.rating || '★)',
      r.name || coalesce(' · ' || r.city, '') || ' · ' || repeat('★', r.rating) || E'\n' || r.comment ||
      E'\n\nOnaylamak için: https://arac.bulqr.com.tr/?admin');
  exception when others then null;  -- bildirim kurulu değilse yorum yine kaydedilir
  end;
  return json_build_object('ok', true, 'id', r.id,
    'photo_name', case when v_token is not null then 'yorum/' || r.id || '-' || v_token::text || '.jpg' end);
end $$;

-- Fotoğraf yüklendi: yoruma bağla
create or replace function public.review_photo_ready(p_code text, p_pin text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
  r reviews;
  v_name text;
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  select * into r from reviews where tag_code = v_code for update;
  if not found or r.photo_token is null then return json_build_object('ok', false, 'error', 'not_found'); end if;
  v_name := 'yorum/' || r.id || '-' || r.photo_token::text || '.jpg';
  if not exists (select 1 from storage.objects where bucket_id = 'aracqr-yorum' and name = v_name) then
    return json_build_object('ok', false, 'error', 'no_file');
  end if;
  update reviews set photo = v_name where id = r.id;
  return json_build_object('ok', true);
end $$;

-- Kendi yorumum (formu doldurmak ve onay durumunu göstermek için)
create or replace function public.review_mine(p_code text, p_pin text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
  r reviews;
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  select * into r from reviews where tag_code = v_code;
  if not found then return json_build_object('ok', true, 'review', null); end if;
  return json_build_object('ok', true, 'review', json_build_object('name', r.name, 'city', r.city, 'rating', r.rating,
    'comment', r.comment, 'status', r.status, 'photo', r.photo is not null));
end $$;

-- Herkese açık: onaylı yorumlar ve özet. {count, avg, items:[{name, city, rating, comment, photo_url, at}]}
create or replace function public.reviews_public(p_limit integer default 30)
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object(
    'count', (select count(*) from reviews where status = 'yayinda'),
    'avg', (select round(avg(rating)::numeric, 1) from reviews where status = 'yayinda'),
    'items', coalesce((select json_agg(x) from (
      select name, city, rating, comment, coalesce(updated_at, created_at) as at,
        case when photo is not null then public.aracqr_project_url() || '/storage/v1/object/public/aracqr-yorum/' || photo end as photo_url
      from reviews where status = 'yayinda'
      order by (photo is not null) desc, rating desc, coalesce(updated_at, created_at) desc
      limit least(greatest(coalesce(p_limit, 30), 1), 100)) x), '[]'::json));
$$;

-- Yönetim
create or replace function public.admin_reviews(p_key text)
returns table (id bigint, tag_code text, created_at timestamptz, updated_at timestamptz, name text, city text,
  rating smallint, comment text, photo_url text, status text, lang text)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select r.id, r.tag_code, r.created_at, r.updated_at, r.name, r.city, r.rating, r.comment,
    case when r.photo is not null then public.aracqr_project_url() || '/storage/v1/object/public/aracqr-yorum/' || r.photo end,
    r.status, r.lang
  from reviews r order by (r.status = 'bekliyor') desc, coalesce(r.updated_at, r.created_at) desc;
end $$;

-- p_status: 'yayinda' | 'gizli' | 'bekliyor' | 'sil'. Fotoğraf yorumdan ayrılır (dosyası Storage'da kalır, bağlantısı hiçbir yerde gösterilmez).
create or replace function public.admin_review_set(p_key text, p_id bigint, p_status text, p_remove_photo boolean default false)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  if p_status = 'sil' then delete from reviews where id = p_id; return; end if;
  if p_status not in ('yayinda', 'gizli', 'bekliyor') then raise exception 'geçersiz durum'; end if;
  update reviews set status = p_status, photo = case when p_remove_photo then null else photo end where id = p_id;
end $$;

-- Kullanıcı QR'ını silince yorumu da silinsin
create or replace function public.reviews_tag_deleted()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  delete from reviews where tag_code = old.code;
  return old;
end $$;
drop trigger if exists self_tags_review_cleanup on public.self_tags;
create trigger self_tags_review_cleanup after delete on public.self_tags
  for each row execute function public.reviews_tag_deleted();

revoke all on function public.review_submit(text, text, text, text, integer, text, boolean, text) from public;
revoke all on function public.review_photo_ready(text, text) from public;
revoke all on function public.review_mine(text, text) from public;
revoke all on function public.reviews_public(integer) from public;
revoke all on function public.admin_reviews(text) from public;
revoke all on function public.admin_review_set(text, bigint, text, boolean) from public;
revoke all on function public.reviews_tag_deleted() from public, anon, authenticated;
grant execute on function public.aracqr_reviews_version() to anon, authenticated;
grant execute on function public.review_submit(text, text, text, text, integer, text, boolean, text) to anon, authenticated;
grant execute on function public.review_photo_ready(text, text) to anon, authenticated;
grant execute on function public.review_mine(text, text) to anon, authenticated;
grant execute on function public.reviews_public(integer) to anon, authenticated;
grant execute on function public.admin_reviews(text) to anon, authenticated;
grant execute on function public.admin_review_set(text, bigint, text, boolean) to anon, authenticated;

-- ================================================================ talepler.sql
-- QR talep formu: ana sayfadaki formdan gelen talepler ve yönetim paneli fonksiyonları.
-- Supabase > SQL Editor'da çalıştırın. Mevcut tablolara dokunmaz, yalnızca ekleme yapar.
-- Tekrar çalıştırmak güvenlidir: önceki sürümü kurduysanız bu dosyayı yeniden çalıştırmanız yeterli.
-- Admin şifresi kontrolü için mevcut admin_list(p_key) fonksiyonunu kullanır.

create table if not exists public.qr_requests (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text,           -- isteğe bağlı: sticker WhatsApp'tan istenirse
  plate text,           -- artık formda yok; eski kayıtlar için duruyor
  note text,
  status text not null default 'yeni' check (status in ('yeni', 'verildi', 'iptal')),
  tag_code text,
  updated_at timestamptz
);
alter table public.qr_requests enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.qr_requests from anon, authenticated;
alter table public.qr_requests alter column phone drop not null;  -- önceki sürümde zorunluydu

-- Panelin kurulumun güncel olup olmadığını anlaması için
create or replace function public.aracqr_requests_version() returns integer language sql immutable as 'select 3';
grant execute on function public.aracqr_requests_version() to anon, authenticated;

-- Herkese açık: talep oluşturur. {ok:true} ya da {ok:false, error:'...'} döner. Telefon isteğe bağlı; p_plate yok sayılır.
create or replace function public.request_create(
  p_first_name text, p_last_name text, p_email text, p_phone text default null, p_plate text default null, p_note text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_first text := left(trim(coalesce(p_first_name, '')), 60);
  v_last  text := left(trim(coalesce(p_last_name, '')), 60);
  v_email text := lower(left(trim(coalesce(p_email, '')), 120));
  v_phone text := nullif(left(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), 16), '');
  v_note  text := nullif(left(trim(coalesce(p_note, '')), 500), '');
begin
  if v_first = '' or v_last = '' then return json_build_object('ok', false, 'error', 'missing'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  if v_phone is not null and v_phone !~ '^\+?[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  -- kötüye kullanım sınırları: aynı kişiden günde 3, genelde dakikada 20 talep
  if (select count(*) from qr_requests where (email = v_email or phone = v_phone) and created_at > now() - interval '1 day') >= 3
    then return json_build_object('ok', false, 'error', 'too_many'); end if;
  if (select count(*) from qr_requests where created_at > now() - interval '1 minute') >= 20
    then return json_build_object('ok', false, 'error', 'busy'); end if;
  insert into qr_requests(first_name, last_name, email, phone, note)
    values (v_first, v_last, v_email, v_phone, v_note);
  -- sürüm 3: yeni talep Telegram / e-postayla bildirilir (siparis.sql kuruluysa)
  begin
    perform public.aracqr_notify('Araç QR: yeni hazır QR talebi',
      v_first || ' ' || v_last || coalesce(' · ' || v_phone, '') || ' · ' || v_email || coalesce(E'\n' || v_note, '') ||
      E'\n\nYönetim: https://arac.bulqr.com.tr/?admin');
  exception when others then null;  -- bildirim kurulu değilse talep yine kaydedilir
  end;
  return json_build_object('ok', true);
end $$;

-- Yönetim: tüm talepler, en yenisi önce
create or replace function public.admin_requests(p_key text)
returns setof public.qr_requests
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select * from public.qr_requests order by created_at desc;
end $$;

-- Yönetim: talebin durumunu ve verilen etiket kodunu günceller
create or replace function public.admin_request_update(p_key text, p_id bigint, p_status text, p_tag_code text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  update public.qr_requests
     set status = p_status, tag_code = nullif(upper(trim(coalesce(p_tag_code, ''))), ''), updated_at = now()
   where id = p_id;
end $$;

revoke all on function public.request_create(text, text, text, text, text, text) from public;
revoke all on function public.admin_requests(text) from public;
revoke all on function public.admin_request_update(text, bigint, text, text) from public;
grant execute on function public.request_create(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_requests(text) to anon, authenticated;
grant execute on function public.admin_request_update(text, bigint, text, text) to anon, authenticated;

-- ================================================================ verildi.sql
-- "Verildi" takibi: dağıtılan etiketleri yönetim listesinden gizler.
-- Supabase > SQL Editor'da bir kez çalıştırın. Mevcut tablolara dokunmaz, yalnızca ekleme yapar.
-- Admin şifresi kontrolü için mevcut admin_list(p_key) fonksiyonunu kullanır
-- (şifre hatalıysa o fonksiyon hata verir, bu da işlemi durdurur).

create table if not exists public.tag_given (
  code text primary key,
  given_at timestamptz not null default now()
);
alter table public.tag_given enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.tag_given from anon, authenticated;

-- Verilmiş etiket kodlarını döner
create or replace function public.admin_given_list(p_key text)
returns setof text
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return query select code from public.tag_given;
end $$;

-- Etiketleri verildi / verilmedi olarak işaretler
create or replace function public.admin_set_given(p_key text, p_codes text[], p_given boolean)
returns integer
language plpgsql security definer set search_path = public
as $$
declare n integer;
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  if p_given then
    insert into public.tag_given(code) select distinct upper(trim(c)) from unnest(p_codes) c
      on conflict (code) do nothing;
  else
    delete from public.tag_given where code = any (select upper(trim(c)) from unnest(p_codes) c);
  end if;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.admin_given_list(text) from public;
revoke all on function public.admin_set_given(text, text[], boolean) from public;
grant execute on function public.admin_given_list(text) to anon, authenticated;
grant execute on function public.admin_set_given(text, text[], boolean) to anon, authenticated;

-- ================================================================ pin.sql
-- PIN'imi unuttum: kullanıcı QR'ına bir kurtarma e-postası kaydeder; PIN'i unutunca e-postasını yazar, QR kodu(ları)
-- ve PIN(ler)i o adrese gönderilir. Supabase > SQL Editor'da çalıştırın. Önce uygulama.sql ve siparis.sql kurulu olmalı
-- (e-posta, siparis.sql'deki Resend ayarlarıyla gönderilir). Mevcut verilere dokunmaz; tekrar çalıştırmak güvenlidir.
--
-- E-postanın müşterilere ulaşması için Resend'de bir alan adı doğrulanmalı (Resend > Domains > bulqr.com.tr, verilen
-- DNS kayıtları Cloudflare'e eklenir) ve yönetim panelinde "Gönderen adresi" ör. Araç QR <pin@bulqr.com.tr> yapılmalı.
-- Doğrulanmamış onboarding@resend.dev adresi yalnızca Resend hesabının sahibine e-posta gönderebilir.

alter table public.self_tags add column if not exists email text;
create index if not exists self_tags_email_idx on public.self_tags (lower(email)) where email is not null;
alter table public.shop_settings add column if not exists mail_from text;

-- Her "PIN'imi unuttum" isteği (eşleşsin ya da eşleşmesin) sınır için kaydedilir; 2 gün sonra silinir
create table if not exists public.pin_mail_log (
  id bigint generated always as identity primary key,
  email text not null,
  sent boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists pin_mail_log_idx on public.pin_mail_log (email, created_at);
alter table public.pin_mail_log enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.pin_mail_log from anon, authenticated;

create or replace function public.aracqr_pin_version() returns integer language sql immutable as 'select 2';

create or replace function public.aracqr_email_ok(p_email text) returns boolean language sql immutable
  as $q$ select coalesce(p_email, '') ~ '^[^@\s<>",;]+@[^@\s<>",;]+\.[^@\s<>",;]+$' and length(p_email) <= 254 $q$;

-- Müşteriye e-posta (Resend). Gönderildiyse true.
create or replace function public.aracqr_mail(p_to text, p_subject text, p_text text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare s shop_settings;
begin
  select * into s from shop_settings where id = 1;
  if coalesce(s.resend_api_key, '') = '' or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return false; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using 'https://api.resend.com/emails',
          jsonb_build_object('from', coalesce(nullif(trim(s.mail_from), ''), 'Araç QR <onboarding@resend.dev>'),
            'to', jsonb_build_array(p_to), 'subject', p_subject, 'text', p_text),
          jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || s.resend_api_key);
  return true;
exception when others then
  raise warning 'Araç QR e-postası gönderilemedi: %', sqlerrm;
  return false;
end $$;
revoke all on function public.aracqr_mail(text, text, text) from public, anon, authenticated;  -- yalnızca içeriden

-- Kurtarma e-postasını kaydet / kaldır (PIN ile). Boş e-posta = kaldır. {ok, email}
create or replace function public.self_tag_email_set(p_code text, p_pin text, p_email text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_err text := public.self_tag_check_pin(v_code, p_pin);
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  if v_email is not null and not public.aracqr_email_ok(v_email) then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  update self_tags set email = v_email, updated_at = now() where code = v_code;
  return json_build_object('ok', true, 'email', v_email);
end $$;

-- base64url (uygulamadaki yedek kodu biçimi: ARACQR1.<base64url JSON>)
create or replace function public.aracqr_b64url(p text) returns text language sql immutable
  as $q$ select rtrim(translate(replace(encode(convert_to(p, 'UTF8'), 'base64'), E'\n', ''), '+/', '-_'), '=') $q$;

-- QR bilgileri e-postası: e-postaya kayıtlı QR'ların kodu, PIN'i, numara değiştirme bağlantısı ve uygulamaya geri
-- yükleme kodu. p_code verilirse yalnızca o QR. p_welcome: QR'a e-posta ilk bağlandığında giden "bilgileriniz" e-postası,
-- değilse "PIN'imi unuttum" yanıtı. Sınır: aynı e-postaya saatte 3, toplamda saatte 60. {ok} ya da {ok:false, error}
create or replace function public.aracqr_tags_mail(p_email text, p_code text, p_lang text, p_welcome boolean)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_code text := nullif(upper(trim(coalesce(p_code, ''))), '');
  v_tr boolean := coalesce(p_lang, 'tr') like 'tr%';
  s shop_settings;
  v_list text := '';
  v_tags jsonb := '[]'::jsonb;
  v_n integer := 0;
  v_restore text;
  t record;
begin
  if not public.aracqr_email_ok(v_email) then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  select * into s from shop_settings where id = 1;
  if coalesce(s.resend_api_key, '') = '' or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return json_build_object('ok', false, 'error', 'mail_off');
  end if;
  delete from pin_mail_log where created_at < now() - interval '2 days';
  if (select count(*) from pin_mail_log where email = v_email and created_at > now() - interval '1 hour') >= 3
     or (select count(*) from pin_mail_log where created_at > now() - interval '1 hour') >= 60 then
    return json_build_object('ok', false, 'error', 'busy');
  end if;

  for t in select code, pin, phone from self_tags
           where email = v_email and (v_code is null or code = v_code) order by created_at limit 20 loop
    v_n := v_n + 1;
    v_list := v_list || E'\n' || (case when v_tr then 'QR kodu: ' else 'QR code: ' end) || t.code ||
      E'\nPIN: ' || t.pin ||
      E'\n' || (case when v_tr then 'Numarayı değiştir: ' else 'Change number: ' end) || 'https://arac.bulqr.com.tr/?s=' || t.code || E'&degistir\n';
    v_tags := v_tags || jsonb_build_object('code', t.code, 'pin', t.pin, 'phone', t.phone,
      'design', 'klasik', 'size', '60x90', 'paper', 'a4', 'copies', 1);
  end loop;

  insert into pin_mail_log (email, sent) values (v_email, v_n > 0);
  if v_n = 0 then return json_build_object('ok', true); end if;
  v_restore := 'ARACQR1.' || public.aracqr_b64url(json_build_object('t', v_tags, 'o', '[]'::json)::text);

  perform public.aracqr_mail(v_email,
    case when p_welcome and v_tr then 'Araç QR · QR bilgileriniz'
         when p_welcome then 'Araç QR · your QR details'
         when v_tr then 'Araç QR · PIN''iniz' else 'Araç QR · your PIN' end,
    case when v_tr then
      'Merhaba,' || E'\n\n' ||
      case when p_welcome then 'Araç QR bilgileriniz aşağıda. Bu e-postayı saklayın: PIN''inizi unutursanız ya da telefonunuz değişirse işinize yarar.'
           else 'PIN''imi unuttum isteğiniz üzerine Araç QR bilgileriniz:' end || E'\n' || v_list || E'\n' ||
      'QR''larınızı uygulamaya geri eklemek için aşağıdaki kodu kopyalayın; uygulamada Profilim › Yedekle / taşı › Geri yükle''ye yapıştırın:' ||
      E'\n\n' || v_restore || E'\n\n' ||
      '🔒 Bu e-postayı kimseyle paylaşmayın: PIN''i bilen numaranızı değiştirebilir.' || E'\n' ||
      case when p_welcome then 'Bu e-postayı Araç QR uygulamasında Profilim''e kaydettiğiniz için aldınız.'
           else 'Bu isteği siz yapmadıysanız e-postayı silebilirsiniz; bilgileriniz değişmedi.' end ||
      E'\n\n' || 'Araç QR · https://arac.bulqr.com.tr'
    else
      'Hello,' || E'\n\n' ||
      case when p_welcome then 'Here are your Araç QR details. Keep this email: it helps if you forget your PIN or change phones.'
           else 'You asked for your Araç QR PIN. Here are your details:' end || E'\n' || v_list || E'\n' ||
      'To add your QR codes back to the app, copy the code below and paste it in Profile › Back up / move › Restore:' ||
      E'\n\n' || v_restore || E'\n\n' ||
      '🔒 Do not share this email: anyone with the PIN can change your number.' || E'\n' ||
      case when p_welcome then 'You received this email because you saved it in your Araç QR profile.'
           else 'If you did not request this, you can delete this email; nothing was changed.' end ||
      E'\n\n' || 'Araç QR · https://arac.bulqr.com.tr'
    end);
  return json_build_object('ok', true);
end $$;
revoke all on function public.aracqr_tags_mail(text, text, text, boolean) from public, anon, authenticated;  -- yalnızca içeriden

-- PIN'imi unuttum. p_code verilirse yalnızca o QR, verilmezse bu e-postaya kayıtlı tüm QR'lar gönderilir.
-- Kimin hangi e-postayı kaydettiği anlaşılmasın diye eşleşme olsa da olmasa da aynı yanıt döner: {ok:true}.
-- Hata: bad_email | busy (çok sık istek) | mail_off (e-posta gönderimi kurulu değil)
create or replace function public.pin_forgot(p_email text, p_code text default null, p_lang text default 'tr')
returns json
language sql security definer set search_path = public
as $$ select public.aracqr_tags_mail(p_email, p_code, p_lang, false) $$;

-- QR'a e-posta bağlanınca (uygulama, PIN ile): o e-postaya kayıtlı tüm QR'ların bilgileri tek e-postada gönderilir
create or replace function public.tags_welcome_mail(p_code text, p_pin text, p_lang text default 'tr')
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_err text := public.self_tag_check_pin(v_code, p_pin);
  v_email text;
begin
  if v_err is not null then return json_build_object('ok', false, 'error', v_err); end if;
  select email into v_email from self_tags where code = v_code;
  if v_email is null then return json_build_object('ok', false, 'error', 'no_email'); end if;
  return public.aracqr_tags_mail(v_email, null, p_lang, true);
end $$;

-- Yönetim: PIN e-postalarının gönderen adresi (Resend'de doğrulanmış alan adından olmalı). Boş = onboarding@resend.dev
create or replace function public.admin_mail_from_set(p_key text, p_from text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  update shop_settings set mail_from = nullif(left(trim(coalesce(p_from, '')), 120), ''), updated_at = now() where id = 1;
end $$;

-- Yönetim: kurtarma e-postası kayıtlı QR sayısı ve son 2 günün istekleri
create or replace function public.admin_pin_stats(p_key text)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  perform public.admin_list(p_key);  -- şifre kontrolü
  return json_build_object('with_email', (select count(*) from self_tags where email is not null),
    'requests', (select count(*) from pin_mail_log), 'sent', (select count(*) from pin_mail_log where sent));
end $$;

revoke all on function public.aracqr_b64url(text) from public, anon, authenticated;
revoke all on function public.self_tag_email_set(text, text, text) from public;
revoke all on function public.pin_forgot(text, text, text) from public;
revoke all on function public.tags_welcome_mail(text, text, text) from public;
revoke all on function public.admin_mail_from_set(text, text) from public;
revoke all on function public.admin_pin_stats(text) from public;
grant execute on function public.aracqr_pin_version() to anon, authenticated;
grant execute on function public.aracqr_email_ok(text) to anon, authenticated;
grant execute on function public.self_tag_email_set(text, text, text) to anon, authenticated;
grant execute on function public.pin_forgot(text, text, text) to anon, authenticated;
grant execute on function public.tags_welcome_mail(text, text, text) to anon, authenticated;
grant execute on function public.admin_mail_from_set(text, text) to anon, authenticated;
grant execute on function public.admin_pin_stats(text) to anon, authenticated;
