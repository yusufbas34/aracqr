# Google Play'e yükleme rehberi

Bu dosyada sırasıyla şunlar var: imza anahtarı, AAB derleme, Play Console adımları, test süreci,
Veri güvenliği formu cevapları ve mağaza metinleri. Görseller `android/store/` klasöründe.

## 0. Uygulamada Play için yapılanlar

- **İki sürüm derlenir.** `github` sürümü bugünkü APK'dır, yeni sürüm olunca GitHub'dan haber verir.
  `play` sürümü (AAB) kendini güncellemez, GitHub'a hiç bağlanmaz. Güncellemeyi Play Store yapar; bu Play'in kuralıdır.
- **Hedef API 36** (Android 16). 31 Ağustos 2026'dan beri yeni uygulama ve güncellemelerde zorunlu.
- **Yeni geri hareketi** (Android 13+ "predictive back") desteklenir.
- **Gizlilik politikası:** https://yusufbas34.github.io/aracqr/gizlilik.html
- **Veri silme:**
  - Uygulama içinde iki yol var: QR sayfasında "QR'ı kalıcı olarak sil", Profilim'de "Tüm verilerimi sil".
  - Web'de: https://yusufbas34.github.io/aracqr/gizlilik.html#silme
- **İzinler:**
  - İnternet ve ağ durumu
  - Bildirim (Android 13+ bir kez sorulur)
  - Açılışta başlama: bildirim kontrolü telefon yeniden başlayınca da sürsün diye
  
  Konum, kamera, rehber ve dosya izni yok. Hiçbiri Play'de ek beyan istemez.

## 1. Yükleme anahtarı oluşturun (bir kez, kendi bilgisayarınızda)

Java yüklü bir bilgisayarda (Android Studio ile gelir):

```
keytool -genkeypair -v -keystore aracqr-play.jks -alias aracqr -keyalg RSA -keysize 4096 -validity 10000
```

Bir şifre sorar; ad-soyad vb. soruları doldurun. Çıkan `aracqr-play.jks` dosyasını ve şifreyi
**kaybetmeyin ve kimseyle paylaşmayın**. Depoya (GitHub'a) KOYMAYIN. Bir yere yedekleyin.

Play App Signing kullanıldığı için bu dosya yalnızca "yükleme anahtarı"dır. Kaybederseniz Play Console'dan
sıfırlatabilirsiniz, uygulama kaybolmaz.

Dosyayı metne çevirin:

- Mac / Linux: `base64 -i aracqr-play.jks | tr -d '\n' > anahtar.txt`
- Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("aracqr-play.jks")) > anahtar.txt`

## 2. Anahtarı GitHub'a gizli olarak ekleyin

GitHub › aracqr deposu › Settings › Secrets and variables › Actions › **New repository secret**.
Dört tane ekleyin:

| Ad | Değer |
|---|---|
| `PLAY_KEYSTORE_BASE64` | `anahtar.txt` dosyasının tamamı |
| `PLAY_KEYSTORE_PASSWORD` | keytool'da verdiğiniz şifre |
| `PLAY_KEY_ALIAS` | `aracqr` |
| `PLAY_KEY_PASSWORD` | aynı şifre (keytool ayrı sormadıysa) |

Sonra `anahtar.txt` dosyasını silin.

## 3. AAB dosyasını alın

GitHub › Actions › **Android APK** › Run workflow ile çalıştırın (ya da main'e bir gönderim yapın).
Bitince çalışmanın sayfasının altında, Artifacts bölümünde **arac-qr-play-aab** belirir. İndirin; içinden
`arac-qr-play.aab` çıkar. Play Console'a bu dosya yüklenir.

Sürüm numarası her derlemede otomatik artar, bu yüzden her güncellemede yeni AAB'yi yüklemeniz yeterli.

## 4. Play Console adımları

1. https://play.google.com/console adresinden geliştirici hesabı açın. Tek seferlik 25 $ ödenir ve kimlik doğrulaması yapılır.
2. **Uygulama oluştur:**
   - Ad: Araç QR
   - Dil: Türkçe
   - Uygulama, Ücretsiz
3. **Uygulama içeriği** bölümündeki formlar (cevaplar aşağıda, 6. bölümde):
   - Gizlilik politikası: `https://yusufbas34.github.io/aracqr/gizlilik.html`
   - Uygulama erişimi: "Tüm işlevler özel erişim olmadan kullanılabilir"
   - Reklamlar: Hayır
   - İçerik derecelendirmesi anketi: Kategori "Yardımcı program / üretkenlik". Şiddet, cinsellik, kumar vb. sorulara hep Hayır. Kullanıcılar birbiriyle iletişim kurabilir mi sorusuna: Hayır (QR'ı okutan, telefonun kendi arama/SMS uygulamasıyla arar; uygulamada sohbet yok).
   - Hedef kitle: 18 yaş ve üzeri (araç sahipleri)
   - Haber uygulaması: Hayır
   - Veri güvenliği: 6. bölüm
   - Devlet uygulaması: Hayır
   - Finansal özellikler: Yok
   - Sağlık: Yok
4. **Mağaza girişi:** metinler 7. bölümde, görseller `android/store/` klasöründe.
5. **Test › Kapalı test:**
   - Kanal oluşturun ve testçileri ekleyin (5. bölüm).
   - AAB'yi yükleyin. Sürüm notunu yazıp yayınlayın.
6. Şartlar dolunca **Üretim** için erişim başvurusu yapın ve yayınlayın.

> **Önemli: telefonunuzdaki eski APK.**
> Play sürümü farklı bir anahtarla imzalıdır. GitHub APK'sı kurulu bir telefona Play'den kurmak için önce APK'yı kaldırmak gerekir.
> Kaldırınca telefondaki QR listesi ve PIN'ler silinir; QR'lar çalışmaya devam eder.
> Kaldırmadan önce her QR'ın kodunu ve PIN'ini not edin.

## 5. Test: "basit bir uygulama, nasıl test edeceğiz?"

Google, **2023'ten sonra açılan kişisel hesaplarda** üretime çıkmadan önce şunu şart koşar:

- **Kapalı testte en az 12 kişi**
- **14 gün boyunca kesintisiz** uygulamaya katılmış olmalı

Uygulamanın basit olması bu şartı değiştirmez. Şirket (kuruluş) hesabıysa bu şart yoktur; D-U-N-S numarası gerekir.

Pratik yol:

1. **Google Grubu açın** (groups.google.com), ör. `aracqr-test@googlegroups.com`. Testçileri e-posta listesi yerine bu gruba ekleyin. Arkadaş, aile ve tanıdık esnaf olabilir; Gmail hesabı yeterli. 12'nin üstünde, ör. 15-20 kişi ekleyin; düşen olursa sayı 12'nin altına inmesin.
2. Kapalı test kanalında "Testçiler" sekmesine bu grubu yazın.
3. Console'un verdiği **katılım bağlantısını** (opt-in link) WhatsApp'tan paylaşın. Her kişi şunları yapar:
   - Bağlantıyı Android telefonunda, gruba eklenen Gmail hesabıyla açar ve "Test kullanıcısı ol"a basar.
   - Aynı sayfadaki Play Store bağlantısından uygulamayı kurar.
   - 14 gün boyunca **kaldırmaz**, ara sıra açar.
4. Testçilerden 14 gün içinde şunları denemelerini isteyin; bunlar sizin de test listenizdir:
   - İlk açılış tanıtımı ve "Başlayalım" ile tasarım seçme (yana kaydırma)
   - QR oluşturma, yazdırma ya da PDF paylaşma
   - Başka bir telefonla QR'ı okutup aramanın gelmesi
   - Sessiz saatleri açıp o saatte okutunca yalnızca mesaj seçeneğinin çıkması
   - Söz ve tasarım değiştirme, QR'ı kapatıp açma
   - Sipariş verme: Telegram/e-postaya düşüyor mu, iptal ediliyor mu, durum değişince bildirim geliyor mu
   - QR'ı kalıcı silme ve Tüm verilerimi sil
5. Bu sürede en az bir güncelleme yayınlamanız iyi olur. Google "aktif geliştirme" görmek ister; gelen geri bildirimlere göre küçük bir düzeltme yeterli.
6. 14 gün dolunca Console › Panel'de "Üretim erişimi başvurusu" açılır. Sorulara açık cevap verin:
   - Testi nasıl yaptınız: arkadaş grubu, WhatsApp
   - Ne geri bildirim aldınız
   - Ne değiştirdiniz
   
   Onay genelde birkaç gün sürer.

Kendi testiniz için: kapalı test yerine **Dahili test** kanalına da yükleyebilirsiniz. 100 kişiye kadar, inceleme
beklemeden dakikalar içinde kurulur, ama 14 gün şartına sayılmaz.

## 6. Veri güvenliği formu cevapları

Gizlilik politikasıyla birebir aynı olmalı. Biri değişirse diğerini de güncelleyin.

- Uygulama kullanıcı verisi topluyor ya da paylaşıyor mu: **Evet**
- Veriler aktarım sırasında şifreleniyor mu: **Evet** (HTTPS)
- Kullanıcılar verilerinin silinmesini isteyebilir mi: **Evet**
  - Silme bağlantısı: `https://yusufbas34.github.io/aracqr/gizlilik.html#silme`
  - Uygulama içinde silme de var.
- Hesap oluşturma: **Yok**. Hesap olmadığı için "hesap silme bağlantısı" zorunlu değildir, yine de silme sayfası var.

Toplanan veri türleri:

| Tür | Toplanıyor | Paylaşılıyor* | İsteğe bağlı mı | Amaç |
|---|---|---|---|---|
| Kişisel bilgi › Ad | Evet (yalnızca siparişte) | Hayır | İsteğe bağlı | Uygulama işlevi |
| Kişisel bilgi › E-posta | Evet (yalnızca siparişte) | Hayır | İsteğe bağlı | Uygulama işlevi, iletişim |
| Kişisel bilgi › Telefon numarası | Evet | Hayır | Zorunlu (uygulamanın amacı) | Uygulama işlevi |
| Kişisel bilgi › Adres | Evet (yalnızca siparişte) | Hayır | İsteğe bağlı | Uygulama işlevi (kargo) |
| Uygulama etkinliği › Diğer işlemler (okutma zamanı) | Evet | Hayır | Zorunlu | Uygulama işlevi (okutma sayacı) |
| Cihaz veya diğer kimlikler | Evet (uygulamanın ürettiği rastgele kimlik) | Hayır | Zorunlu | Dolandırıcılığı önleme, güvenlik |

\* Play'in tanımında hizmet sağlayıcıya (Supabase, Telegram, e-posta servisi, baskı ve kargo firması) sizin adınıza
veri vermek "paylaşma" sayılmaz. Bu yüzden "Paylaşılıyor" sütunu Hayır.

Konum, kişiler, fotoğraf, finans, sağlık, mesaj, dosya, takvim, web geçmişi, reklam kimliği ve çökme kaydı: **toplanmıyor**.

## 7. Mağaza metinleri

**Uygulama adı** (en fazla 30): `Araç QR: Önünü Kapatan Arasın`

**Kısa açıklama** (en fazla 80): `Camınıza QR sticker. Okutan sizi arar; numaranız camda yazmaz. Ücretsiz.`

**Tam açıklama:**

```
Arabanız birinin önünü mü kapattı? Camdaki numaranızı herkes görsün istemiyor musunuz?

Araç QR ile aracınıza size özel bir QR sticker yapıştırırsınız. Önü kapanan kişi QR'ı telefon kamerasıyla okutur ve tek dokunuşla sizi arar ya da hazır bir mesaj gönderir ("Önümü kapattınız", "Farlarınız açık kaldı" gibi). Numaranız camda ya da QR'ın üstünde yazmaz.

★ Kendi tasarımınızı yapın
20'den fazla hazır tasarım ve komik sözler arasından seçin. Tasarımları yana kaydırarak gezin, sözünüzü değiştirin.

★ Ücretsiz yazdırın ya da biz basalım
Evdeki yazıcıdan istediğiniz ölçüde yazdırın, PDF olarak matbaaya gönderin. İsterseniz yağmura ve güneşe dayanıklı vinil sticker setini biz basıp kargolayalım.

★ Gece rahat uyuyun: sessiz saatler
Belirlediğiniz saatlerde arama butonu gösterilmez. QR'ı okutan kişi size yalnızca SMS ya da WhatsApp mesajı gönderebilir.

★ Numara değişti mi? Sticker'ı yeniden basmayın
Numaranız QR'ın içinde değil, güvenli sunucuda durur. Uygulamadan PIN'inizle değiştirin; aynı sticker çalışmaya devam eder.

★ QR'ı kapatın / açın
Araç satıldı, sticker kayboldu ya da tatildesiniz: QR'ı tek dokunuşla kapatın, kimse numaranıza ulaşamaz.

★ Okutma sayacı ve sipariş bildirimleri
QR'ınızın kaç kez okutulduğunu görün. Siparişinizin durumu değişince bildirim alın.

Hesap açmanız gerekmez. Reklam yok. Verilerinizi istediğiniz an uygulamadan silebilirsiniz.
```

**Kategori:** Araçlar ve Taşıtlar (Auto & Vehicles) ya da Araçlar (Tools)
**Etiketler:** araç, otopark, QR kod, sticker
**İletişim e-postası:** Play bu adresi mağazada herkese gösterir. Gizlilik sayfası iletişim için bu adresi gösteriyor; geliştirici hesabındaki e-posta da olur, ayrı bir adres açabilirsiniz de.
**Web sitesi:** `https://yusufbas34.github.io/aracqr/`

**İlk sürüm notu:** `İlk sürüm: QR oluşturma, 20+ tasarım, sessiz saatler, hazır mesajlar, baskılı sticker siparişi.`

**Görseller** (`android/store/`):

- `icon-512.png`: uygulama simgesi
- `feature-1024x500.png`: öne çıkan görsel
- `screen-*.png`: telefon ekran görüntüleri (en az 2, en fazla 8)
