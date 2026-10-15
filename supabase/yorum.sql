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
      E'\n\nOnaylamak için: https://yusufbas34.github.io/aracqr/?admin');
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
