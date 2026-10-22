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

create or replace function public.aracqr_pin_version() returns integer language sql immutable as 'select 1';

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

-- PIN'imi unuttum. p_code verilirse yalnızca o QR, verilmezse bu e-postaya kayıtlı tüm QR'lar gönderilir.
-- Kimin hangi e-postayı kaydettiği anlaşılmasın diye eşleşme olsa da olmasa da aynı yanıt döner: {ok:true}.
-- Hata: bad_email | busy (çok sık istek) | mail_off (e-posta gönderimi kurulu değil)
create or replace function public.pin_forgot(p_email text, p_code text default null, p_lang text default 'tr')
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
  t record;
begin
  if not public.aracqr_email_ok(v_email) then return json_build_object('ok', false, 'error', 'bad_email'); end if;
  select * into s from shop_settings where id = 1;
  if coalesce(s.resend_api_key, '') = '' or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return json_build_object('ok', false, 'error', 'mail_off');
  end if;
  delete from pin_mail_log where created_at < now() - interval '2 days';
  -- sınır: aynı e-postaya saatte 3, toplamda saatte 60 istek
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

  perform public.aracqr_mail(v_email,
    case when v_tr then 'Araç QR · PIN''iniz' else 'Araç QR · your PIN' end,
    case when v_tr then
      'Merhaba,' || E'\n\n' || 'PIN''imi unuttum isteğiniz üzerine Araç QR bilgileriniz:' || E'\n' || v_list || E'\n' ||
      'QR''larınızı uygulamaya geri eklemek için aşağıdaki kodu kopyalayın; uygulamada Profilim › Yedekle / taşı › Geri yükle''ye yapıştırın:' ||
      E'\n\n' || 'ARACQR1.' || public.aracqr_b64url(json_build_object('t', v_tags, 'o', '[]'::json)::text) || E'\n\n' ||
      '🔒 Bu e-postayı kimseyle paylaşmayın: PIN''i bilen numaranızı değiştirebilir.' || E'\n' ||
      'Bu isteği siz yapmadıysanız e-postayı silebilirsiniz; bilgileriniz değişmedi.' || E'\n\n' || 'Araç QR · https://arac.bulqr.com.tr'
    else
      'Hello,' || E'\n\n' || 'You asked for your Araç QR PIN. Here are your details:' || E'\n' || v_list || E'\n' ||
      'To add your QR codes back to the app, copy the code below and paste it in Profile › Back up / move › Restore:' ||
      E'\n\n' || 'ARACQR1.' || public.aracqr_b64url(json_build_object('t', v_tags, 'o', '[]'::json)::text) || E'\n\n' ||
      '🔒 Do not share this email: anyone with the PIN can change your number.' || E'\n' ||
      'If you did not request this, you can delete this email; nothing was changed.' || E'\n\n' || 'Araç QR · https://arac.bulqr.com.tr'
    end);
  return json_build_object('ok', true);
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
revoke all on function public.admin_mail_from_set(text, text) from public;
revoke all on function public.admin_pin_stats(text) from public;
grant execute on function public.aracqr_pin_version() to anon, authenticated;
grant execute on function public.aracqr_email_ok(text) to anon, authenticated;
grant execute on function public.self_tag_email_set(text, text, text) to anon, authenticated;
grant execute on function public.pin_forgot(text, text, text) to anon, authenticated;
grant execute on function public.admin_mail_from_set(text, text) to anon, authenticated;
grant execute on function public.admin_pin_stats(text) to anon, authenticated;
