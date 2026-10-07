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
alter table public.self_tags enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.self_tags from anon, authenticated;

create or replace function public.aracqr_app_version() returns integer language sql immutable as 'select 1';

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

-- QR okutulunca: {exists, phone}
create or replace function public.self_tag_lookup(p_code text)
returns json
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select json_build_object('exists', true, 'phone', phone) from self_tags where code = upper(trim(p_code))),
    json_build_object('exists', false));
$$;

-- Numara değiştirme (PIN ile). 5 yanlış denemede 15 dakika kilit.
create or replace function public.self_tag_save(p_code text, p_pin text, p_phone text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  t self_tags;
begin
  select * into t from self_tags where code = v_code for update;
  if not found then return json_build_object('ok', false, 'error', 'not_found'); end if;
  if t.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked', 'minutes', ceil(extract(epoch from t.locked_until - now()) / 60));
  end if;
  if t.pin <> trim(coalesce(p_pin, '')) then
    update self_tags set
      fail_count = case when t.fail_count + 1 >= 5 then 0 else t.fail_count + 1 end,
      locked_until = case when t.fail_count + 1 >= 5 then now() + interval '15 minutes' else null end
      where code = v_code;
    return json_build_object('ok', false, 'error', 'bad_pin');
  end if;
  if v_phone !~ '^\+[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  update self_tags set phone = v_phone, updated_at = now(), fail_count = 0, locked_until = null where code = v_code;
  return json_build_object('ok', true, 'phone', v_phone);
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
grant execute on function public.aracqr_app_version() to anon, authenticated;
grant execute on function public.self_tag_create(text, text) to anon, authenticated;
grant execute on function public.self_tag_lookup(text) to anon, authenticated;
grant execute on function public.self_tag_save(text, text, text) to anon, authenticated;
grant execute on function public.admin_self_tags(text) to anon, authenticated;
