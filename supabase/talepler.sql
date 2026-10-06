-- QR talep formu: ana sayfadaki formdan gelen talepler ve yönetim paneli fonksiyonları.
-- Supabase > SQL Editor'da bir kez çalıştırın. Mevcut tablolara dokunmaz, yalnızca ekleme yapar.
-- Admin şifresi kontrolü için mevcut admin_list(p_key) fonksiyonunu kullanır.

create table if not exists public.qr_requests (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text not null,
  plate text,
  note text,
  status text not null default 'yeni' check (status in ('yeni', 'verildi', 'iptal')),
  tag_code text,
  updated_at timestamptz
);
alter table public.qr_requests enable row level security;  -- politika yok: doğrudan erişim kapalı
revoke all on public.qr_requests from anon, authenticated;

-- Herkese açık: talep oluşturur. {ok:true} ya da {ok:false, error:'...'} döner.
create or replace function public.request_create(
  p_first_name text, p_last_name text, p_email text, p_phone text, p_plate text default null, p_note text default null)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_first text := left(trim(coalesce(p_first_name, '')), 60);
  v_last  text := left(trim(coalesce(p_last_name, '')), 60);
  v_email text := lower(left(trim(coalesce(p_email, '')), 120));
  v_phone text := left(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), 16);
  v_plate text := nullif(upper(left(trim(coalesce(p_plate, '')), 12)), '');
  v_note  text := nullif(left(trim(coalesce(p_note, '')), 500), '');
begin
  if v_first = '' or v_last = '' then return json_build_object('ok', false, 'error', 'missing'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  if v_phone !~ '^\+?[0-9]{10,15}$' then return json_build_object('ok', false, 'error', 'bad_phone'); end if;
  -- kötüye kullanım sınırları: aynı kişiden günde 3, genelde dakikada 20 talep
  if (select count(*) from qr_requests where (email = v_email or phone = v_phone) and created_at > now() - interval '1 day') >= 3
    then return json_build_object('ok', false, 'error', 'too_many'); end if;
  if (select count(*) from qr_requests where created_at > now() - interval '1 minute') >= 20
    then return json_build_object('ok', false, 'error', 'busy'); end if;
  insert into qr_requests(first_name, last_name, email, phone, plate, note)
    values (v_first, v_last, v_email, v_phone, v_plate, v_note);
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
