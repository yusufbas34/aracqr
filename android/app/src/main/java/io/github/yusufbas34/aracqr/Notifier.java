package io.github.yusufbas34.aracqr;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Arka planda (uygulama kapalıyken de) yaklaşık saatte bir: GitHub'da yeni APK var mı ve siparişlerin durumu
 * değişti mi diye bakar; değişiklik varsa bildirim gösterir. Ek kütüphane ya da Firebase gerektirmez.
 * Siparişleri web arayüzü AndroidBridge.syncOrders ile buraya bildirir.
 */
public class Notifier extends JobService {
    static final String SUPABASE_URL = "https://icedhptvywmqsiarxpio.supabase.co";
    static final String SUPABASE_KEY = "sb_publishable_IEPlZ5oNcsrQt7_8DK_QKQ_1s9UMT6z";
    static final String RELEASE_API = "https://api.github.com/repos/yusufbas34/aracqr/releases/tags/apk-son";
    static final String APK_URL = "https://github.com/yusufbas34/aracqr/releases/download/apk-son/arac-qr.apk";
    static final String EXTRA_ROUTE = "route";
    private static final int JOB_ID = 1;
    private static final long PERIOD = 30 * 60 * 1000L;  // yarım saatte bir
    private static final String PREFS = "aracqr";
    private static final String CH_ORDERS = "siparis", CH_UPDATE = "guncelleme";

    /** Uygulama her açıldığında çağrılır; görev zaten kuruluysa dokunmaz. */
    static void schedule(Context ctx) {
        JobScheduler js = ctx.getSystemService(JobScheduler.class);
        JobInfo old = js == null ? null : js.getPendingJob(JOB_ID);
        if (js == null || (old != null && old.getIntervalMillis() == PERIOD)) return;  // aralık değiştiyse yeniden kur
        js.schedule(new JobInfo.Builder(JOB_ID, new ComponentName(ctx, Notifier.class))
                .setPeriodic(PERIOD)                                  // Android pil durumuna göre kaydırabilir
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)                                   // telefon yeniden başlasa da sürer
                .build());
    }

    /** Web arayüzünden gelen sipariş listesi: [{code, token, status}]. Bilinen durumlar için bildirim gösterilmez. */
    static void syncOrders(Context ctx, String json) {
        try {
            new JSONArray(json);  // geçerli mi
            prefs(ctx).edit().putString("orders", json).apply();
        } catch (Exception ignored) {
        }
    }

    /** Web arayüzünden gelen QR listesi: [{code, pin, name}]. İlk okutma bildirimi için. */
    static void syncTags(Context ctx, String json) {
        try {
            new JSONArray(json);  // geçerli mi
            prefs(ctx).edit().putString("tags", json).apply();
        } catch (Exception ignored) {
        }
    }

    @Override
    public boolean onStartJob(JobParameters params) {
        new Thread(() -> {
            // Play sürümü kendini güncellemez; güncelleme duyurusunu Play Store yapar
            if (!"play".equals(BuildConfig.FLAVOR)) try { checkUpdate(); } catch (Exception ignored) { }
            try { checkOrders(); } catch (Exception ignored) { }
            try { checkScans(); } catch (Exception ignored) { }
            jobFinished(params, false);
        }).start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true;  // yarıda kalırsa sonra yeniden dene
    }

    // ---------------------------------------------------------------- dil (web arayüzü AndroidBridge.setLanguage ile bildirir)
    static void setLanguage(Context ctx, String lang) {
        if (lang != null && lang.matches("tr|en|ar|ru")) prefs(ctx).edit().putString("lang", lang).apply();
    }

    /** Bildirim metinleri: [tr, en, ar, ru] */
    private static final java.util.Map<String, String[]> TEXT = new java.util.HashMap<>();
    static {
        TEXT.put("updTitle", new String[]{"Araç QR'ın yeni sürümü hazır", "A new version of Araç QR is ready", "إصدار جديد من Araç QR جاهز", "Доступна новая версия Araç QR"});
        TEXT.put("updText", new String[]{"Sürüm %s · Güncellemek için dokunun, inen dosyayı açın.", "Version %s · Tap to update, then open the downloaded file.", "الإصدار %s · اضغط للتحديث ثم افتح الملف الذي تم تنزيله.", "Версия %s · Нажмите, чтобы обновить, затем откройте загруженный файл."});
        TEXT.put("order", new String[]{"Sipariş %s", "Order %s", "الطلب %s", "Заказ %s"});
        TEXT.put("onaylandi", new String[]{"Siparişiniz onaylandı, stickerlarınız baskıya hazırlanıyor.", "Your order is confirmed; your stickers are being prepared for printing.", "تم تأكيد طلبك، ويتم تجهيز ملصقاتك للطباعة.", "Ваш заказ подтверждён, наклейки готовятся к печати."});
        TEXT.put("baskida", new String[]{"Stickerlarınız baskıda.", "Your stickers are being printed.", "ملصقاتك قيد الطباعة.", "Ваши наклейки печатаются."});
        TEXT.put("kargolandi", new String[]{"Siparişiniz kargoya verildi.", "Your order has been shipped.", "تم شحن طلبك.", "Ваш заказ отправлен."});
        TEXT.put("tracking", new String[]{" Takip no: ", " Tracking no: ", " رقم التتبع: ", " Трек-номер: "});
        TEXT.put("iptal", new String[]{"Siparişiniz iptal edildi.", "Your order has been canceled.", "تم إلغاء طلبك.", "Ваш заказ отменён."});
        TEXT.put("testTitle", new String[]{"Bildirimler çalışıyor ✓", "Notifications are working ✓", "الإشعارات تعمل ✓", "Уведомления работают ✓"});
        TEXT.put("testText", new String[]{"Yeni sürüm çıktığında ve siparişiniz ilerlediğinde böyle haber vereceğiz.", "We'll let you know like this when a new version is out and when your order moves forward.", "سنخبرك هكذا عند صدور إصدار جديد وعند تقدّم طلبك.", "Так мы сообщим о новой версии и о ходе вашего заказа."});
        TEXT.put("scanTitle", new String[]{"🎉 QR'ınız ilk kez okutuldu!", "🎉 Your QR was scanned for the first time!", "🎉 تم مسح رمز QR الخاص بك لأول مرة!", "🎉 Ваш QR впервые отсканировали!"});
        TEXT.put("scanText", new String[]{"%s: Biri QR'ınızı okuttu, sistem çalışıyor. Okutma sayısını uygulamada görebilirsiniz.", "%s: Someone scanned your QR — it works. You can see the scan count in the app.", "%s: قام شخص بمسح رمزك، النظام يعمل. يمكنك رؤية عدد مرات المسح في التطبيق.", "%s: Кто-то отсканировал ваш QR — всё работает. Число сканирований видно в приложении."});
        TEXT.put("chOrders", new String[]{"Sipariş durumu", "Order status", "حالة الطلب", "Статус заказа"});
        TEXT.put("chUpdate", new String[]{"Uygulama güncellemeleri", "App updates", "تحديثات التطبيق", "Обновления приложения"});
    }
    static String tx(Context ctx, String key) {
        String l = prefs(ctx).getString("lang", "tr");
        int i = "en".equals(l) ? 1 : "ar".equals(l) ? 2 : "ru".equals(l) ? 3 : 0;
        return TEXT.get(key)[i];
    }

    /** Profilim'deki "Deneme bildirimi gönder" butonu */
    static boolean showTest(Context ctx) {
        Intent open = new Intent(ctx, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return post(ctx, CH_UPDATE, 999, tx(ctx, "testTitle"), tx(ctx, "testText"), open);
    }

    // ---------------------------------------------------------------- yeni sürüm
    private void checkUpdate() throws Exception {
        long installed = getPackageManager().getPackageInfo(getPackageName(), 0).getLongVersionCode();
        long latest = latestBuild(new JSONObject(http("GET", RELEASE_API, null, false)).optString("body"));
        SharedPreferences p = prefs(this);
        if (latest > installed && latest > p.getLong("notifiedVersion", 0)) {
            Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse(APK_URL + "?v=" + latest));
            post(this, CH_UPDATE, 1000, tx(this, "updTitle"), String.format(tx(this, "updText"), "1.0." + latest), open);
            p.edit().putLong("notifiedVersion", latest).apply();
        }
    }

    /** GitHub sürüm notundaki "Derleme N" sayısı; yoksa 0. */
    static long latestBuild(String releaseBody) {
        Matcher m = Pattern.compile("Derleme (\\d+)").matcher(releaseBody == null ? "" : releaseBody);
        return m.find() ? Long.parseLong(m.group(1)) : 0;
    }

    // ---------------------------------------------------------------- sipariş durumu
    private void checkOrders() throws Exception {
        SharedPreferences p = prefs(this);
        JSONArray known = new JSONArray(p.getString("orders", "[]"));
        if (known.length() == 0) return;
        JSONArray codes = new JSONArray(), tokens = new JSONArray();
        for (int i = 0; i < known.length(); i++) {
            JSONObject o = known.getJSONObject(i);
            codes.put(o.optString("code"));
            tokens.put(o.optString("token"));
        }
        JSONObject args = new JSONObject().put("p_codes", codes).put("p_tokens", tokens);
        JSONArray rows = new JSONArray(http("POST", SUPABASE_URL + "/rest/v1/rpc/order_status", args.toString(), true));
        boolean changed = false;
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            JSONObject o = find(known, r.optString("code"));
            if (o == null) continue;
            String status = r.optString("status"), tracking = r.isNull("tracking") ? "" : r.optString("tracking");
            String text = statusChange(this, o.optString("status"), status, tracking);
            if (text != null) {
                Intent open = new Intent(this, MainActivity.class)
                        .putExtra(EXTRA_ROUTE, "#/siparis/" + o.optString("code"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                post(this, CH_ORDERS, 2000 + Math.abs(o.optString("code").hashCode() % 1000), String.format(tx(this, "order"), o.optString("code")), text, open);
            }
            if (!status.equals(o.optString("status"))) { o.put("status", status); changed = true; }
        }
        if (changed) p.edit().putString("orders", known.toString()).apply();
    }

    /**
     * QR ilk kez okutulunca bildirim. Her QR'ın son bilinen okutma sayısı saklanır; 0'dan yukarı çıkınca bir kez haber verilir.
     * Bu özellik gelmeden önce okutulmuş QR'lar için (ilk kontrolde sayı zaten > 0) bildirim gösterilmez.
     */
    private void checkScans() throws Exception {
        SharedPreferences p = prefs(this);
        JSONArray tags = new JSONArray(p.getString("tags", "[]"));
        if (tags.length() == 0) return;
        JSONArray codes = new JSONArray(), pins = new JSONArray();
        for (int i = 0; i < tags.length(); i++) {
            JSONObject t = tags.getJSONObject(i);
            codes.put(t.optString("code"));
            pins.put(t.optString("pin"));
        }
        JSONObject args = new JSONObject().put("p_codes", codes).put("p_pins", pins);
        JSONArray rows = new JSONArray(http("POST", SUPABASE_URL + "/rest/v1/rpc/self_tag_stats", args.toString(), true));
        JSONObject seen = new JSONObject(p.getString("scanSeen", "{}"));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            String code = r.optString("code");
            long total = r.optLong("total", 0);
            JSONObject t = find(tags, code);
            // Yeni oluşturulmuş QR (son 1 gün) ilk kontrolden önce okutulduysa da haber ver
            boolean fresh = t != null && System.currentTimeMillis() - t.optLong("created", 0) < 24 * 3600 * 1000L;
            boolean known = seen.has(code) || fresh;
            if (known && seen.optLong(code, 0) == 0 && total > 0) {
                String name = t != null && !t.optString("name").isEmpty() ? t.optString("name") : code;
                Intent open = new Intent(this, MainActivity.class)
                        .putExtra(EXTRA_ROUTE, "#/etiket/" + code)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                post(this, CH_ORDERS, 3000 + Math.abs(code.hashCode() % 1000), tx(this, "scanTitle"), String.format(tx(this, "scanText"), name), open);
            }
            seen.put(code, total);
        }
        p.edit().putString("scanSeen", seen.toString()).apply();
    }

    /** Durum ilerlediyse müşteriye gösterilecek metin; değişmediyse null. */
    static String statusChange(Context ctx, String before, String after, String tracking) {
        if (after == null || after.isEmpty() || after.equals(before)) return null;
        switch (after) {
            case "onaylandi": case "baskida": case "iptal": return tx(ctx, after);
            case "kargolandi": return tx(ctx, "kargolandi") + (tracking.isEmpty() ? "" : tx(ctx, "tracking") + tracking);
            default: return null;  // ilk durumlar ("yeni" vb.) için bildirim yok
        }
    }

    private static JSONObject find(JSONArray list, String code) throws Exception {
        for (int i = 0; i < list.length(); i++) if (list.getJSONObject(i).optString("code").equals(code)) return list.getJSONObject(i);
        return null;
    }

    // ---------------------------------------------------------------- yardımcılar
    /** Bildirim izni verilmiş ve kanallar kapatılmamış mı */
    static boolean enabled(Context ctx) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        if (nm == null || !nm.areNotificationsEnabled()) return false;
        return Build.VERSION.SDK_INT < 33 || ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED;
    }

    private static boolean post(Context ctx, String channel, int id, String title, String text, Intent tap) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        if (nm == null || !enabled(ctx)) return false;
        nm.createNotificationChannel(new NotificationChannel(CH_ORDERS, tx(ctx, "chOrders"), NotificationManager.IMPORTANCE_DEFAULT));
        nm.createNotificationChannel(new NotificationChannel(CH_UPDATE, tx(ctx, "chUpdate"), NotificationManager.IMPORTANCE_DEFAULT));
        PendingIntent pi = PendingIntent.getActivity(ctx, id, tap, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(ctx, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFF0A3A9E)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        nm.notify(id, n);
        return true;
    }

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, MODE_PRIVATE);
    }

    private static String http(String method, String url, String body, boolean supabase) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setRequestMethod(method);
        c.setConnectTimeout(15000);
        c.setReadTimeout(15000);
        c.setRequestProperty("Accept", "application/json");
        if (supabase) {
            c.setRequestProperty("apikey", SUPABASE_KEY);
            if (SUPABASE_KEY.startsWith("eyJ")) c.setRequestProperty("Authorization", "Bearer " + SUPABASE_KEY);
        }
        if (body != null) {
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            try (OutputStream out = c.getOutputStream()) { out.write(body.getBytes(StandardCharsets.UTF_8)); }
        }
        if (c.getResponseCode() >= 400) throw new IllegalStateException("HTTP " + c.getResponseCode());
        try (InputStream in = c.getInputStream(); ByteArrayOutputStream buf = new ByteArrayOutputStream()) {
            byte[] b = new byte[8192];
            for (int n; (n = in.read(b)) > 0; ) buf.write(b, 0, n);
            return buf.toString(StandardCharsets.UTF_8.name());
        } finally {
            c.disconnect();
        }
    }
}
