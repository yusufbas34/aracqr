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
    private static final String PREFS = "aracqr";
    private static final String CH_ORDERS = "siparis", CH_UPDATE = "guncelleme";

    /** Uygulama her açıldığında çağrılır; görev zaten kuruluysa dokunmaz. */
    static void schedule(Context ctx) {
        JobScheduler js = ctx.getSystemService(JobScheduler.class);
        if (js == null || js.getPendingJob(JOB_ID) != null) return;
        js.schedule(new JobInfo.Builder(JOB_ID, new ComponentName(ctx, Notifier.class))
                .setPeriodic(60 * 60 * 1000L)                         // saatte bir (Android pil durumuna göre kaydırabilir)
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

    @Override
    public boolean onStartJob(JobParameters params) {
        new Thread(() -> {
            // Play sürümü kendini güncellemez; güncelleme duyurusunu Play Store yapar
            if (!"play".equals(BuildConfig.FLAVOR)) try { checkUpdate(); } catch (Exception ignored) { }
            try { checkOrders(); } catch (Exception ignored) { }
            jobFinished(params, false);
        }).start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true;  // yarıda kalırsa sonra yeniden dene
    }

    // ---------------------------------------------------------------- yeni sürüm
    private void checkUpdate() throws Exception {
        long installed = getPackageManager().getPackageInfo(getPackageName(), 0).getLongVersionCode();
        long latest = latestBuild(new JSONObject(http("GET", RELEASE_API, null, false)).optString("body"));
        SharedPreferences p = prefs(this);
        if (latest > installed && latest > p.getLong("notifiedVersion", 0)) {
            Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse(APK_URL + "?v=" + latest));
            notify(CH_UPDATE, 1000, "Araç QR'ın yeni sürümü hazır",
                    "Sürüm 1.0." + latest + " · Güncellemek için dokunun, inen dosyayı açın.", open);
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
            String text = statusChange(o.optString("status"), status, tracking);
            if (text != null) {
                Intent open = new Intent(this, MainActivity.class)
                        .putExtra(EXTRA_ROUTE, "#/siparis/" + o.optString("code"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                notify(CH_ORDERS, 2000 + Math.abs(o.optString("code").hashCode() % 1000), "Sipariş " + o.optString("code"), text, open);
            }
            if (!status.equals(o.optString("status"))) { o.put("status", status); changed = true; }
        }
        if (changed) p.edit().putString("orders", known.toString()).apply();
    }

    /** Durum ilerlediyse müşteriye gösterilecek metin; değişmediyse null. */
    static String statusChange(String before, String after, String tracking) {
        if (after == null || after.isEmpty() || after.equals(before)) return null;
        switch (after) {
            case "onaylandi": return "Siparişiniz onaylandı, stickerlarınız baskıya hazırlanıyor.";
            case "baskida": return "Stickerlarınız baskıda.";
            case "kargolandi": return "Siparişiniz kargoya verildi." + (tracking.isEmpty() ? "" : " Takip no: " + tracking);
            case "iptal": return "Siparişiniz iptal edildi.";
            default: return null;  // ilk durumlar ("yeni" vb.) için bildirim yok
        }
    }

    private static JSONObject find(JSONArray list, String code) throws Exception {
        for (int i = 0; i < list.length(); i++) if (list.getJSONObject(i).optString("code").equals(code)) return list.getJSONObject(i);
        return null;
    }

    // ---------------------------------------------------------------- yardımcılar
    private void notify(String channel, int id, String title, String text, Intent tap) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) return;
        nm.createNotificationChannel(new NotificationChannel(CH_ORDERS, "Sipariş durumu", NotificationManager.IMPORTANCE_DEFAULT));
        nm.createNotificationChannel(new NotificationChannel(CH_UPDATE, "Uygulama güncellemeleri", NotificationManager.IMPORTANCE_DEFAULT));
        PendingIntent pi = PendingIntent.getActivity(this, id, tap, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFF0A3A9E)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        nm.notify(id, n);
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
