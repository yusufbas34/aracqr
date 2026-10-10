# Araç QR Android uygulaması

Kullanıcı bir tasarım seçer, telefon numarasını girer, uygulama ona özel bir QR etiketi ve PIN oluşturur.
Etiket istenen ölçüde yazdırılır ya da PDF olarak paylaşılır.

QR, `https://yusufbas34.github.io/aracqr/?s=KOD` adresini açar. Numara QR'ın içinde değil sunucuda
tutulur, bu yüzden PIN ile sonradan değiştirilebilir ve sticker'ı yeniden basmak gerekmez.

## İlk kurulum (bir kez)

Supabase > SQL Editor'da `supabase/uygulama.sql` dosyasını çalıştırın. Bu dosya mevcut tablolara
dokunmaz; uygulamadan oluşturulan etiketler ayrı bir tabloda (`self_tags`) tutulur.

## APK'yı indirme

`main` dalına her gönderimde GitHub Actions APK'yı derler ve şu sabit bağlantıya koyar:

https://github.com/yusufbas34/aracqr/releases/download/apk-son/arac-qr.apk

Telefonda bağlantıyı açıp dosyayı indirin ve açın. İlk kurulumda Android "bilinmeyen kaynaklardan
yüklemeye izin ver" diye sorar. Yeni sürümler eskisinin üstüne kurulur, kayıtlı etiketler silinmez.

## Kendiniz derlemek isterseniz

Android Studio ile `android` klasörünü açın ya da komut satırında:

```
cd android
./gradlew assembleRelease
```

APK: `android/app/build/outputs/apk/release/app-release.apk`

## Yapı

- `../app/`: uygulamanın arayüzü (index.html, app.js, app.css, onboarding.js, sticker tasarımları). Aynı klasör web'de /aracqr/app/ adresinde de yayınlanır; derlemede uygulamanın içine eklenir.
- `MainActivity.java`: arayüzü gösterir; Android yazdırma ekranını açar, PDF'i İndirilenler/AracQR
  klasörüne kaydedip paylaşma ekranını açar.
- `../app/vendor`, `../app/fonts`: çevrimdışı çalışmak için gömülü kütüphaneler ve fontlar
  (lisanslar `vendor/LICENSES.txt` ve `fonts/OFL.txt`).

## İmza anahtarı hakkında

`app/aracqr-sideload.keystore` APK'yı elden dağıtmak (indirme bağlantısı) için konmuş, şifresi
`app/build.gradle` içinde açık duran bir anahtardır. Her sürüm aynı anahtarla imzalandığı için
güncellemeler eskisinin üstüne kurulur.

Uygulamayı Google Play'e yükleyecekseniz bu anahtarı kullanmayın: kendi gizli anahtarınızı oluşturun
ve şifresini depoya değil GitHub Secrets'a koyun.
