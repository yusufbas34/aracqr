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

create or replace function public.aracqr_app_version() returns integer language sql immutable as 'select 3';

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
grant execute on function public.self_tag_set_active(text, text, boolean) to anon, authenticated;
grant execute on function public.self_tag_settings(text, text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.self_tag_stats(text[], text[]) to anon, authenticated;
grant execute on function public.aracqr_app_version() to anon, authenticated;
grant execute on function public.self_tag_create(text, text) to anon, authenticated;
grant execute on function public.self_tag_lookup(text) to anon, authenticated;
grant execute on function public.self_tag_save(text, text, text) to anon, authenticated;
grant execute on function public.admin_self_tags(text) to anon, authenticated;
