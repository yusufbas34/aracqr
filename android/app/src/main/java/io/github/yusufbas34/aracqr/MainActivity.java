package io.github.yusufbas34.aracqr;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
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
        setContentView(web);

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

        if (state != null) web.restoreState(state);
        else web.loadUrl(START_URL);
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
