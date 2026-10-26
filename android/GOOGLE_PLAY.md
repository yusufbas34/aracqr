# Google Play'e yükleme rehberi

Bu dosyada sırasıyla şunlar var: imza anahtarı, AAB derleme, Play Console adımları, test süreci,
Veri güvenliği formu cevapları ve mağaza metinleri. Görseller `android/store/` klasöründe.

## 0. Uygulamada Play için yapılanlar

- **İki sürüm derlenir.** `github` sürümü bugünkü APK'dır, yeni sürüm olunca GitHub'dan haber verir.
  `play` sürümü (AAB) kendini güncellemez, GitHub'a hiç bağlanmaz. Güncellemeyi Play Store yapar; bu Play'in kuralıdır.
- **Hedef API 36** (Android 16). 31 Ağustos 2026'dan beri yeni uygulama ve güncellemelerde zorunlu.
- **Yeni geri hareketi** (Android 13+ "predictive back") desteklenir.
- **Gizlilik politikası:** https://arac.bulqr.com.tr/gizlilik.html
- **Veri silme:**
  - Uygulama içinde iki yol var: QR sayfasında "QR'ı kalıcı olarak sil", Profilim'de "Tüm verilerimi sil".
  - Web'de: https://arac.bulqr.com.tr/gizlilik.html#silme
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

Anahtar GitHub'a eklendikten sonra her derlemede imzalı paket şu sabit bağlantıya konur (telefondan da indirilir):
https://github.com/yusufbas34/aracqr/releases/download/play-son/arac-qr-play.aab


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
   - Gizlilik politikası: `https://arac.bulqr.com.tr/gizlilik.html`
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
   - Rahatsız Etmeyin saatlerini açıp o saatte okutunca yalnızca mesaj seçeneğinin çıkması
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
  - Silme bağlantısı: `https://arac.bulqr.com.tr/gizlilik.html#silme`
  - Uygulama içinde silme de var.
- Hesap oluşturma: **Yok**. Hesap olmadığı için "hesap silme bağlantısı" zorunlu değildir, yine de silme sayfası var.

Toplanan veri türleri:

| Tür | Toplanıyor | Paylaşılıyor* | İsteğe bağlı mı | Amaç |
|---|---|---|---|---|
| Kişisel bilgi › Ad | Evet (yalnızca siparişte) | Hayır | İsteğe bağlı | Uygulama işlevi |
| Kişisel bilgi › E-posta adresi | Evet (siparişte ya da Profilim'e yazılırsa) | Hayır | İsteğe bağlı | Uygulama işlevi, Hesap yönetimi (PIN kurtarma), iletişim |
| Kişisel bilgi › Telefon numarası | Evet | Hayır | Zorunlu (uygulamanın amacı) | Uygulama işlevi |
| Kişisel bilgi › Adres | Evet (yalnızca siparişte) | Hayır | İsteğe bağlı | Uygulama işlevi (kargo) |
| Uygulama etkinliği › Diğer işlemler (okutma zamanı) | Evet | Hayır | Zorunlu | Uygulama işlevi (okutma sayacı) |
| Cihaz veya diğer kimlikler | Evet (uygulamanın ürettiği rastgele kimlik) | Hayır | Zorunlu | Dolandırıcılığı önleme, güvenlik |

\* Play'in tanımında hizmet sağlayıcıya (Supabase, Telegram, e-posta servisi, baskı ve kargo firması) sizin adınıza
veri vermek "paylaşma" sayılmaz. Bu yüzden "Paylaşılıyor" sütunu Hayır.

Konum, kişiler, fotoğraf, finans, sağlık, mesaj, dosya, takvim, web geçmişi, reklam kimliği ve çökme kaydı: **toplanmıyor**.

## 7. Mağaza metinleri

**Uygulama adı** (en fazla 30): `Araç QR: Hatalı Park, Beni Ara`

**Kısa açıklama** (en fazla 80): `Hatalı park ettiğinde seni arasınlar. Numaran camda yazmaz. Ücretsiz QR sticker.`

**Tam açıklama:**

```
Acele edip hatalı mı park ettiniz? Birinin yolunu kapattıysanız size ulaşamazlarsa ceza, çekici ya da kızgın bir not gelir. Camınıza numaranızı yazmak da istemiyorsunuz.

Araç QR ile aracınıza size özel bir QR sticker yapıştırırsınız. Yolunu kapattığınız kişi QR'ı telefon kamerasıyla okutur ve tek dokunuşla sizi arar ya da hazır bir mesaj gönderir ("Önümü kapattınız", "Farlarınız açık kaldı" gibi). Numaranız camda ya da QR'ın üstünde yazmaz.

★ Kendi tasarımınızı yapın
29 hazır tasarım (komik, klasik, takım renkleri) ve esprili sözler arasından seçin. Tasarımları yana kaydırarak gezin, sözünüzü değiştirin.

★ Ücretsiz yazdırın ya da biz basalım
Evdeki yazıcıdan istediğiniz ölçüde yazdırın, PDF olarak matbaaya gönderin. İsterseniz yağmura ve güneşe dayanıklı vinil sticker'ınızı istediğiniz ölçüde biz basıp kargolayalım.

★ Gece rahat uyuyun: Rahatsız Etmeyin modu
Belirlediğiniz saatlerde arama butonu gösterilmez. QR'ı okutan kişi size yalnızca SMS ya da WhatsApp mesajı gönderebilir.

★ Numara değişti mi? Sticker'ı yeniden basmayın
Numaranız QR'ın içinde değil, güvenli sunucuda durur. Uygulamadan PIN'inizle değiştirin; aynı sticker çalışmaya devam eder.

★ QR'ı kapatın / açın
Araç satıldı, sticker kayboldu ya da tatildesiniz: QR'ı tek dokunuşla kapatın, kimse numaranıza ulaşamaz.

★ Yabancı da okutabilir
QR'ı okutan kişinin sayfası telefonunun diline göre Türkçe, İngilizce, Arapça ya da Rusça açılır; mesaj size Türkçe gelir. Uygulama da bu 4 dilde kullanılabilir.

★ Silseniz de kaybolmaz
Uygulamayı silip yeniden kursanız da QR'larınız otomatik geri gelir. Yeni telefona yedek koduyla tek seferde taşıyın.

★ PIN'inizi unutsanız da sorun yok
E-postanızı ekleyin: QR kodlarınız ve PIN'leriniz e-postanıza gelsin. PIN'i unutursanız "PIN'imi unuttum" ile tekrar gönderelim.

★ Okutma sayacı ve bildirimler
QR'ınız ilk kez okutulunca haber verelim, kaç kez okutulduğunu görün. Siparişinizin durumu değişince bildirim alın.

Araç QR kod sticker, otopark ve site park sorunları, cama numara yazmadan ulaşılmak, çekici ve park cezasından kurtulmak için.

Hesap açmanız gerekmez. Reklam yok. Verilerinizi istediğiniz an uygulamadan silebilirsiniz.
```

**Kategori:** Araçlar ve Taşıtlar (Auto & Vehicles) ya da Araçlar (Tools)
**Etiketler:** araç, otopark, QR kod, sticker
**İletişim e-postası:** Play bu adresi mağazada herkese gösterir. Gizlilik sayfası iletişim için bu adresi gösteriyor; geliştirici hesabındaki e-posta da olur, ayrı bir adres açabilirsiniz de.
**Web sitesi:** `https://arac.bulqr.com.tr/`

**İlk sürüm notu:** `İlk sürüm: QR oluşturma, 20+ tasarım, Rahatsız Etmeyin modu, hazır mesajlar, baskılı sticker siparişi.`

**Diğer diller** (Play Console › Mağaza girişi › Çeviri ekle; uygulama bu dilleri destekliyor):

| Dil | Uygulama adı (≤30) | Kısa açıklama (≤80) |
|---|---|---|
| English (en-US) | `Araç QR: Parked Badly? Call Me` | `Parked badly? Let them call you. No number on the glass. Free QR sticker.` |
| العربية (ar) | `Araç QR: ركنت خطأ؟ اتصل بي` | `ركنت بشكل خاطئ؟ دعهم يتصلون بك دون أن يظهر رقمك على الزجاج. ملصق QR مجاني.` |
| Русский (ru-RU) | `Araç QR: Мешаю? Позвоните` | `Неудачно припарковались? Вам позвонят, а номер не виден на стекле. QR бесплатно.` |

**Görseller** (`android/store/`):

- `icon-512.png`: uygulama simgesi
- `feature-1024x500.png`: öne çıkan görsel
- `screen-*.png`: telefon ekran görüntüleri (en az 2, en fazla 8)

### Play'de aranmak (ASO) için notlar

- Play, **uygulama adı**, **kısa açıklama** ve **tam açıklama**daki kelimelere bakar. İnsanların arayacağı kelimeler: *araç QR, araç QR kod, park, hatalı park, otopark, cama numara, park numarası, araç sticker, çekici, beni ara*. Bunlar yukarıdaki metinlerde geçiyor; aynı kelimeyi 4-5 kereden fazla tekrarlamayın (Play bunu cezalandırır).
- **Puan ve yorum** sıralamayı en çok etkileyen şey. İlk 20 yorumu test eden arkadaşlarınızdan isteyin; uygulama ilk okutmada zaten "işe yaradı" anını yakalıyor.
- **Diğer diller:** Aşağıdaki İngilizce tam açıklamayı ekleyin. Arapça ve Rusça için ad ve kısa açıklama tabloda; tam açıklamayı Play Console'daki "çeviri" düğmesiyle İngilizceden alabilirsiniz.
- Ekran görüntülerinin ilk 2'si en önemlisi (aramada görünen bunlar): `screen-1` (Hatalı mı park ettiniz?) ve `screen-5` (okutan kişinin ekranı) önde olsun.

**English full description (en-US):**

```
Parked badly in a hurry? If the person you blocked can't reach you, you get a fine, a tow truck or an angry note. And you don't want your phone number written on the windshield.

With Araç QR you stick your own QR sticker on your car. The person you blocked scans it with the phone camera and calls you with one tap or sends a ready message ("You're blocking me", "Your lights are on"). Your number is never shown on the glass or on the QR.

★ Make it yours: 29 designs (classic, funny, team colors) and witty phrases.
★ Print for free at home in the size you want, or order a waterproof vinyl sticker (Turkey).
★ Do Not Disturb: if you don't want calls at certain hours, people can only message you.
★ Number changed? Change it in the app with your PIN; the same sticker keeps working.
★ Turn your QR off and on: car sold, sticker lost, on holiday.
★ Anyone can scan: the scan page opens in Turkish, English, Arabic or Russian.
★ Never lost: reinstall the app and your QRs come back automatically.
★ Forgot your PIN? Add your email and we'll send your QR codes and PINs to your inbox.
★ Scan counter and a notification when your QR is scanned for the first time.

No account needed. No ads. Delete your data any time in the app.
```

## 8. Hazır metinler (kopyala-yapıştır)

### Google Grubu
groups.google.com › **Grup oluştur**:

| Alan | Değer |
|---|---|
| Grup adı | `Araç QR Test` |
| Grup e-postası | `aracqr-test` (sonuna @googlegroups.com eklenir) |
| Kimler arayabilir | Grup üyeleri |
| Kimler katılabilir | **Herkes katılabilir** (testçiler bağlantıyla kendileri katılsın) |

Grubun adresini (`https://groups.google.com/g/aracqr-test`) ve Play'in verdiği katılım bağlantısını bana gönderin;
testçi sayfasına (`https://arac.bulqr.com.tr/test.html`) eklerim. Testçilere yalnızca bu sayfayı göndermeniz yeterli olur.

### WhatsApp davet mesajı

```
Selam! 🙌 Araç QR diye bir uygulama yaptım: arabanın camına QR sticker yapıştırıyorsun, hatalı park ettiğinde yolunu kapattığın kişi seni tek dokunuşla arıyor, numaran camda yazmıyor.

Google Play'e çıkması için 14 gün test eden 12 kişi lazım. 5 dakikanı alır, sonra telefonda dursun yeter:
👉 https://arac.bulqr.com.tr/test.html

Çok teşekkürler! 💙
```

### Sürüm notu: 1.0.49 (Play'e yapıştırılacak, dil etiketli)

```
<tr-TR>
Yeni: PIN'imi unuttum, QR bilgileriniz e-postanızda. Tasma QR tanıtımı, yenilenen arama ekranı ve 200 TL basılı sticker.
</tr-TR>
<en-US>
New: Forgot PIN with email recovery, refreshed call screen, Tasma QR showcase and printed stickers for 200 TL.
</en-US>
```

### Sürüm notu: PIN kurtarma güncellemesi (derleme 46 ve sonrası)

- **Türkçe:** `Yeni: PIN'imi unuttum. E-postanızı ekleyin, QR kodlarınız ve PIN'leriniz e-postanıza gelsin. Yeni adres: arac.bulqr.com.tr`
- **English:** `New: Forgot PIN. Add your email and get your QR codes and PINs in your inbox. New address: arac.bulqr.com.tr`

### Sürüm notu (kapalı test ve ilk yayın)

- **Türkçe:** `İlk sürüm: QR sticker oluşturma, 29 tasarım, Rahatsız Etmeyin modu, hazır mesajlar, yedekleme, basılı sticker siparişi. 4 dil.`
- **English:** `First release: create QR stickers, 29 designs, quiet hours, ready messages, backup, printed sticker orders. 4 languages.`

### Üretim erişimi başvurusu (14 gün sonra) cevap taslakları
Play Console sorularına kendi deneyiminizle tamamlayın; testte gerçekten olanları yazın.

1. **Testçileri nasıl buldunuz?** `Aile, arkadaşlar ve çevremdeki araç sahipleri; WhatsApp üzerinden Google Grubu ile davet ettim.`
2. **Testçi bulmak ne kadar kolaydı?** `Kolaydı; uygulama araç sahiplerine yönelik ve herkesin günlük karşılaştığı bir sorunu çözüyor.`
3. **Testçiler uygulamayı nasıl kullandı?** `QR oluşturdular, başka telefonla okutup aramayı ve hazır mesajları denediler, Rahatsız Etmeyin saatlerini, tasarım/söz değiştirmeyi, PDF paylaşmayı, yedeklemeyi ve bildirimleri test ettiler.`
4. **Hangi geri bildirimleri aldınız, nasıl topladınız?** `WhatsApp üzerinden topladım. (Buraya gerçek örnekler: ör. "şu metin anlaşılmıyordu", "şu ölçü eklensin".)`
5. **Geri bildirime göre ne değiştirdiniz?** `(Buraya yapılan düzeltmeler; test sırasında yayınlanan güncellemeleri yazın.)`
6. **Uygulama kime yönelik, ne değer sağlıyor?** `Türkiye'deki araç sahipleri. Hatalı park edildiğinde araç sahibine numarası görünmeden ulaşılmasını sağlar; ceza, çekici ve tartışmanın önüne geçer.`
7. **İlk yıl beklenen indirme:** `1.000 – 10.000`
8. **Yayına hazır olduğuna nasıl karar verdiniz?** `14 günlük testte çökme ya da kritik hata kalmadı, testçilerin bildirdiği sorunlar düzeltildi.`

Çökme olup olmadığını Play Console › **Android vitals** bölümünden kontrol edin.

### İmzasız AAB'yi imzalama (GitHub'a anahtar eklemediyseniz)
GitHub Actions anahtar yoksa `arac-qr-play-imzasiz.aab` üretir. Java yüklü bir bilgisayarda:

```
jarsigner -keystore aracqr-play.jks -sigalg SHA256withRSA -digestalg SHA-256 -signedjar arac-qr-play.aab arac-qr-play-imzasiz.aab aracqr
```

Kolay yol: 2. bölümdeki 4 gizli değeri GitHub'a bir kez ekleyin; sonra her derleme imzalı `arac-qr-play.aab` verir.
