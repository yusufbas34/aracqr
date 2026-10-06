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
