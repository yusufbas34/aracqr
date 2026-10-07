package io.github.yusufbas34.aracqr;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import java.io.OutputStream;
import java.util.Locale;

/**
 * Uygulamanın tamamı assets/app.html içindeki web arayüzüdür. Bu sınıf onu gösterir ve
 * web tarafının yapamadığı üç işi sağlar: Android yazdırma ekranı, PDF'i İndirilenler'e kaydetme ve paylaşma.
 */
public class MainActivity extends Activity {
    private static final String START_URL = "file:///android_asset/app.html";
    private WebView web;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        setContentView(edgeToEdgeSafe(web));

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);           // Etiketlerim listesi localStorage'da tutulur
        s.setAllowFileAccess(false);             // yalnızca file:///android_asset okunur
        s.setAllowContentAccess(false);
        s.setTextZoom(100);                      // sistem yazı boyutu sticker ölçülerini bozmasın

        web.addJavascriptInterface(new Bridge(), "AndroidBridge");
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if ("file".equals(uri.getScheme())) return false;
                // Site, WhatsApp, telefon vb. bağlantılar uygulama dışında açılır
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri));
                } catch (Exception e) {
                    toast("Bağlantı açılamadı");
                }
                return true;
            }
        });

        String route = getIntent().getStringExtra(Notifier.EXTRA_ROUTE);
        if (state != null) web.restoreState(state);
        else web.loadUrl(START_URL + (route != null && route.startsWith("#/") ? route : ""));

        Notifier.schedule(this);
        askNotificationPermission();
    }

    /** Bildirime dokunulunca uygulama açıksa ilgili sayfaya geç (ör. #/siparis/AQ-…). */
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String route = intent.getStringExtra(Notifier.EXTRA_ROUTE);
        if (route != null && route.matches("#/[A-Za-z0-9/_-]+")) web.evaluateJavascript("location.hash='" + route + "'", null);
    }

    /** Android 13+: sipariş ve güncelleme bildirimleri için izin (bir kez sorulur). */
    private void askNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33) return;
        if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED) return;
        android.content.SharedPreferences p = getSharedPreferences("aracqr", MODE_PRIVATE);
        if (p.getBoolean("askedNotif", false)) return;
        p.edit().putBoolean("askedNotif", true).apply();
        requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
    }

    /**
     * Uygulama her Android sürümünde ekranın tamamına çizilir ve sistem çubukları (saat/bildirim, gezinme) ile
     * klavye kadar boşluğu kendisi bırakır. Böylece üst çubuk bildirim perdesinin altına girmez; Android 15'in
     * zorunlu tam ekran davranışıyla da eski sürümlerle de aynı görünür. Üstteki şerit marka rengine boyanır.
     */
    @SuppressWarnings("deprecation")
    private View edgeToEdgeSafe(WebView content) {
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        }
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xFFEEF0F3);
        View statusBar = new View(this);
        statusBar.setBackgroundColor(0xFF0A3A9E);
        root.addView(content, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(statusBar, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0));
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            int left, top, right, bottom;
            if (Build.VERSION.SDK_INT >= 30) {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                Insets ime = insets.getInsets(WindowInsets.Type.ime());
                left = bars.left; top = bars.top; right = bars.right; bottom = Math.max(bars.bottom, ime.bottom);
            } else {
                // Android 10: klavye yüksekliği de sistem pencere boşluğunun içindedir
                left = insets.getSystemWindowInsetLeft(); top = insets.getSystemWindowInsetTop();
                right = insets.getSystemWindowInsetRight(); bottom = insets.getSystemWindowInsetBottom();
            }
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) content.getLayoutParams();
            lp.setMargins(left, top, right, bottom);
            content.setLayoutParams(lp);
            statusBar.getLayoutParams().height = top;
            statusBar.requestLayout();
            return WindowInsets.CONSUMED;
        });
        return root;
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    private void toast(String text) {
        runOnUiThread(() -> Toast.makeText(this, text, Toast.LENGTH_LONG).show());
    }

    private static int mils(double mm) {
        return (int) Math.round(mm / 25.4 * 1000);
    }

    /** JavaScript'ten window.AndroidBridge olarak çağrılır. */
    private class Bridge {
        /** Kurulu sürüm (GitHub derleme numarası): güncelleme kontrolü ve Profilim ekranı için. */
        @JavascriptInterface
        public long versionCode() {
            try { return getPackageManager().getPackageInfo(getPackageName(), 0).getLongVersionCode(); }
            catch (Exception e) { return 0; }
        }

        /** Siparişler değişince web arayüzü bildirir: arka plan kontrolü bunlara bakar. */
        @JavascriptInterface
        public void syncOrders(String json) {
            Notifier.syncOrders(MainActivity.this, json);
        }

        @JavascriptInterface
        public String versionName() {
            try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; }
            catch (Exception e) { return ""; }
        }

        /** Sayfanın baskı görünümünü Android yazdırma ekranına gönderir (oradan "PDF olarak kaydet" de seçilebilir). */
        @JavascriptInterface
        public void print(String jobName, double widthMm, double heightMm) {
            runOnUiThread(() -> {
                PrintManager pm = (PrintManager) getSystemService(PRINT_SERVICE);
                PrintDocumentAdapter adapter = web.createPrintDocumentAdapter(jobName);
                PrintAttributes.MediaSize size = Math.round(widthMm) == 210 && Math.round(heightMm) == 297
                        ? PrintAttributes.MediaSize.ISO_A4
                        : new PrintAttributes.MediaSize(
                                String.format(Locale.ROOT, "aracqr_%.0fx%.0f", widthMm, heightMm),
                                String.format(Locale.ROOT, "%.0f × %.0f mm", widthMm, heightMm),
                                mils(widthMm), mils(heightMm));
                PrintAttributes attrs = new PrintAttributes.Builder()
                        .setMediaSize(size)
                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                        .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                        .build();
                pm.print(jobName, adapter, attrs);
            });
        }

        /** PDF'i İndirilenler/AracQR klasörüne kaydeder ve paylaşma ekranını açar. */
        @JavascriptInterface
        public boolean sharePdf(String base64, String fileName) {
            try {
                byte[] data = Base64.decode(base64, Base64.DEFAULT);
                ContentValues cv = new ContentValues();
                cv.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
                cv.put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf");
                cv.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/AracQR");
                Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                if (uri == null) throw new IllegalStateException("MediaStore");
                try (OutputStream out = getContentResolver().openOutputStream(uri)) {
                    if (out == null) throw new IllegalStateException("stream");
                    out.write(data);
                }
                Intent send = new Intent(Intent.ACTION_SEND)
                        .setType("application/pdf")
                        .putExtra(Intent.EXTRA_STREAM, uri)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                runOnUiThread(() -> startActivity(Intent.createChooser(send, "PDF'i paylaş")));
                toast("PDF İndirilenler/AracQR klasörüne kaydedildi");
                return true;
            } catch (Exception e) {
                toast("PDF kaydedilemedi");
                return false;
            }
        }
    }
}
