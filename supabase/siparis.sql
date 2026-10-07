-- Basılı etiket siparişi: uygulamadan sipariş, IBAN ile ödeme bildirimi, yönetim panelinden takip.
-- Supabase > SQL Editor'da çalıştırın. Önce uygulama.sql kurulu olmalı. Mevcut tablolara dokunmaz; tekrar çalıştırmak güvenlidir.
-- Admin şifresi kontrolü için mevcut admin_list(p_key) fonksiyonunu kullanır.

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
  status text not null default 'odeme_bekleniyor'
    check (status in ('odeme_bekleniyor', 'odeme_bildirildi', 'onaylandi', 'baskida', 'kargolandi', 'iptal')),
  paid_at timestamptz,                            -- müşterinin "ödemeyi yaptım" dediği an
  tracking text,
  admin_note text,
  device text,
  updated_at timestamptz
);
create index if not exists orders_created_idx on public.orders (created_at);
alter table public.orders enable row level security;
revoke all on public.orders from anon, authenticated;

create or replace function public.aracqr_shop_version() returns integer language sql immutable as 'select 1';

-- ---------------------------------------------------------------- herkese açık
-- Uygulamanın göstereceği satış bilgileri (baskıcı e-postası hariç)
create or replace function public.shop_info()
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object('active', active and coalesce(iban, '') <> '' and coalesce(account_name, '') <> '',
    'price', price, 'iban', iban, 'account_name', account_name, 'bank_name', bank_name, 'shipping_text', shipping_text)
  from shop_settings where id = 1;
$$;

create or replace function public.order_create(
  p_tag_code text, p_design text, p_full_name text, p_phone text, p_email text,
  p_city text, p_district text, p_address text, p_note text default null, p_device text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  s shop_settings;
  v_tag text := upper(trim(coalesce(p_tag_code, '')));
  v_design text := left(lower(trim(coalesce(p_design, ''))), 20);
  v_name text := left(trim(coalesce(p_full_name, '')), 80);
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_email text := nullif(lower(left(trim(coalesce(p_email, '')), 120)), '');
  v_city text := left(trim(coalesce(p_city, '')), 40);
  v_district text := left(trim(coalesce(p_district, '')), 60);
  v_address text := left(trim(coalesce(p_address, '')), 400);
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
  v_device text := nullif(left(trim(coalesce(p_device, '')), 64), '');
  v_code text;
  o orders;
begin
  select * into s from shop_settings where id = 1;
  if not (s.active and coalesce(s.iban, '') <> '' and coalesce(s.account_name, '') <> '') then
    return json_build_object('ok', false, 'error', 'closed');
  end if;
  if not exists (select 1 from self_tags where code = v_tag) then return json_build_object('ok', false, 'error', 'no_tag'); end if;
  if v_design !~ '^[a-z]{2,20}$' then v_design := 'klasik'; end if;
  if length(v_name) < 3 or v_city = '' or v_district = '' or length(v_address) < 10 then
    return json_build_object('ok', false, 'error', 'missing');
  end if;
  if v_phone !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return json_build_object('ok', false, 'error', 'bad_email'); end if;
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
  insert into orders (code, tag_code, design, full_name, phone, email, city, district, address, note, amount, device)
    values (v_code, v_tag, v_design, v_name, v_phone, v_email, v_city, v_district, v_address, v_note, s.price, v_device)
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
create or replace function public.order_status(p_codes text[], p_tokens uuid[])
returns json
language sql stable security definer set search_path = public
as $$
  select coalesce(json_agg(json_build_object('code', o.code, 'status', o.status, 'tracking', o.tracking)), '[]'::json)
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

create or replace function public.admin_shop_set(p_key text, p_active boolean, p_price integer, p_iban text,
  p_account_name text, p_bank_name text, p_printer_email text, p_shipping_text text)
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
    updated_at = now()
  where id = 1;
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
    admin_note = nullif(trim(coalesce(p_admin_note, '')), ''), updated_at = now()
  where id = p_id;
end $$;

revoke all on function public.shop_info() from public;
revoke all on function public.order_create(text, text, text, text, text, text, text, text, text, text) from public;
revoke all on function public.order_paid(text, uuid) from public;
revoke all on function public.order_status(text[], uuid[]) from public;
revoke all on function public.admin_shop_get(text) from public;
revoke all on function public.admin_shop_set(text, boolean, integer, text, text, text, text, text) from public;
revoke all on function public.admin_orders(text) from public;
revoke all on function public.admin_order_update(text, bigint, text, text, text) from public;
grant execute on function public.aracqr_shop_version() to anon, authenticated;
grant execute on function public.shop_info() to anon, authenticated;
grant execute on function public.order_create(text, text, text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.order_paid(text, uuid) to anon, authenticated;
grant execute on function public.order_status(text[], uuid[]) to anon, authenticated;
grant execute on function public.admin_shop_get(text) to anon, authenticated;
grant execute on function public.admin_shop_set(text, boolean, integer, text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_orders(text) to anon, authenticated;
grant execute on function public.admin_order_update(text, bigint, text, text, text) to anon, authenticated;
