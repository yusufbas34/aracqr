// Araç QR mobil uygulaması: tasarım seç, telefonunu gir, kendi QR'ını oluştur, istediğin ölçüde yazdır.
// QR, sitedeki ?s=KOD sayfasını açar; numara sunucuda tutulur ve PIN ile değiştirilebilir (supabase/uygulama.sql).

const SUPABASE_URL = "https://icedhptvywmqsiarxpio.supabase.co";
const SUPABASE_KEY = "sb_publishable_IEPlZ5oNcsrQt7_8DK_QKQ_1s9UMT6z";
const SITE = "https://yusufbas34.github.io/aracqr/";
const bridge = window.AndroidBridge; // Android dışında (tarayıcıda denerken) yok

const app = document.getElementById("app");
const qrLink = code => `${SITE}?s=${encodeURIComponent(code)}`;

// ---------------------------------------------------------------- kayıt (bu cihaz)
const store = {
  get(key, fallback) { try { const v = localStorage.getItem("aracqr-" + key); return v === null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
  set(key, value) { try { localStorage.setItem("aracqr-" + key, JSON.stringify(value)); } catch (e) {} },
};
const tags = () => store.get("tags", []);
const findTag = code => tags().find(t => t.code === code);
function saveTag(tag) {
  const list = tags().filter(t => t.code !== tag.code);
  store.set("tags", [tag, ...list]);
}
function deviceId() {
  let id = store.get("device", null);
  if (!id) { id = crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now(); store.set("device", id); }
  return id;
}

// ---------------------------------------------------------------- yardımcılar
async function rpc(fn, args) {
  const headers = {"Content-Type": "application/json", apikey: SUPABASE_KEY};
  if (SUPABASE_KEY.startsWith("eyJ")) headers.Authorization = "Bearer " + SUPABASE_KEY;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {method: "POST", headers, body: JSON.stringify(args)});
  const data = await r.json().catch(() => null);
  if (!r.ok) { const e = new Error(data?.message || r.statusText); e.status = r.status; throw e; }
  return data;
}

function normalizePhone(raw) {
  let s = String(raw || "").replace(/[^\d+]/g, "");
  if (s.startsWith("00")) s = "+" + s.slice(2);
  if (s.startsWith("+")) return (s.length - 1 >= 10 && s.length - 1 <= 15) ? s : null;
  if (s.startsWith("90") && s.length === 12) return "+" + s;
  if (s.startsWith("0") && s.length === 11) return "+9" + s;
  if (s.startsWith("5") && s.length === 10) return "+90" + s;
  return null;
}

function prettyPhone(p) {
  if (p && p.startsWith("+90") && p.length === 13) {
    const n = p.slice(3);
    return `0${n.slice(0, 3)} ${n.slice(3, 6)} ${n.slice(6, 8)} ${n.slice(8)}`;
  }
  return p || "";
}

function toast(text, ms = 3200) {
  document.querySelector(".toast")?.remove();
  const t = Object.assign(document.createElement("div"), {className: "toast", textContent: text});
  t.setAttribute("role", "status");
  document.body.append(t);
  setTimeout(() => t.remove(), ms);
}

function confetti() {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const colors = ["#0a3a9e", "#ffd400", "#0c7a43", "#d9426b", "#5ef2ff", "#f3a25a"];
  for (let i = 0; i < 60; i++) {
    const c = document.createElement("div");
    c.className = "confetti";
    c.style.cssText = `left:${Math.random() * 100}vw;background:${colors[i % colors.length]};` +
      `animation-duration:${1.6 + Math.random() * 1.6}s;animation-delay:${Math.random() * .4}s;border-radius:${i % 3 ? 2 : 50}px`;
    document.body.append(c);
    setTimeout(() => c.remove(), 3800);
  }
}

const sizeVars = size => { const {w, h, k} = dims(size); return `--w:${w}mm;--h:${h}mm;--k:${k}`; };
const stickerAt = (code, design, link, size) =>
  `<div class="grid${dims(size).k < .75 ? " small-size" : ""}" style="${sizeVars(size)}">${stickerHtml(code, design, link)}</div>`;

// ---------------------------------------------------------------- ekranlar
function show(title, html, canGoBack, cls = "") {
  document.getElementById("apptitle").textContent = title;
  document.getElementById("back").hidden = !canGoBack;
  app.className = cls;
  app.innerHTML = html;
  scrollTo(0, 0);
}

function showHome() {
  const list = tags();
  if (!list.length) {
    return show("Araç QR", `
      <div class="empty">
        ${stickerAt("ÖRNEK", "klasik", SITE, "50x75")}
        <h1>Kendi araç QR'ınızı oluşturun</h1>
        <p>Aracınızın önünü kapatan kişi QR'ı okutup sizi tek dokunuşla arasın. Numaranız camda yazmaz.</p>
      </div>
      <ol class="msg info" style="padding-left:30px;margin:0">
        <li>Bir tasarım seçin</li>
        <li>Telefon numaranızı girin</li>
        <li>İstediğiniz ölçüde yazdırın, camınıza yapıştırın</li>
      </ol>
      <a class="btn" href="#/yeni">Başlayalım</a>
      <button class="btn ghost" type="button" id="howto">Nasıl çalışır?</button>`), bindHowto();
  }
  show("Etiketlerim", `
    <div class="cards">
      ${list.map(t => `
        <a class="card" href="#/etiket/${encodeURIComponent(t.code)}">
          ${stickerAt(t.code, t.design, qrLink(t.code), "40x60")}
          <div><b>${esc(t.code)}</b><span>${esc(prettyPhone(t.phone))}<br>${esc(DESIGNS[t.design]?.name || "")} · ${esc(SIZES[t.size] || "")}</span></div>
        </a>`).join("")}
    </div>
    <a class="btn" href="#/yeni">+ Yeni QR etiket oluştur</a>
    ${orders().length ? `<h2>Siparişlerim</h2><div class="cards">${orders().map(orderCardHtml).join("")}</div>` : ""}
    <button class="btn ghost" type="button" id="howto">Nasıl çalışır?</button>`);
  bindHowto();
  refreshOrders();
}

function bindHowto() {
  const b = document.getElementById("howto");
  if (b) b.onclick = () => showOnboarding();
}

let draft = {design: store.get("lastDesign", "klasik")};

// Tasarımlar reels gibi: tam ekran, yukarı-aşağı kaydırarak gezilir. tagCode verilirse o etiketin tasarımı değişir.
function showDesigns(tagCode) {
  const t = tagCode ? findTag(tagCode) : null;
  if (tagCode && !t) { location.replace("#/"); return; }
  const keys = Object.keys(DESIGNS), current = t ? t.design : draft.design;
  const code = t ? t.code : "ÖRNEK", link = t ? qrLink(t.code) : SITE;
  show(t ? "Tasarımı değiştir" : "1. Tasarım seçin", `
    <div class="reels" id="reels">
      ${keys.map((k, i) => `
        <section class="reel" data-d="${k}" aria-label="${esc(DESIGNS[k].name)}">
          <div class="reel-top">${i + 1} / ${keys.length} · ${DESIGNS[k].group ? "Eğlenceli" : "Klasik"}</div>
          <div class="reel-sticker">${stickerAt(code, k, link, "60x90")}</div>
          <div class="reel-bottom">
            <b>${esc(DESIGNS[k].name)}</b>
            <button class="btn" type="button" data-pick="${k}">${k === current && t ? "Şu anki tasarım" : t ? "Bu tasarımı kullan" : "Bu tasarımı seç"}</button>
            <div class="swipe">${i < keys.length - 1 ? "⌃ Sonraki tasarım için yukarı kaydırın" : "Son tasarım · ⌄ geri kaydırabilirsiniz"}</div>
          </div>
        </section>`).join("")}
    </div>`, true, "full");
  const reels = document.getElementById("reels");
  // Sticker'ı slayta sığacak kadar büyüt
  const fitStickers = () => {
    const slide = reels.clientHeight, room = Math.min((slide - 200) / 340, (reels.clientWidth - 48) / 227, 1.7);
    reels.querySelectorAll(".reel-sticker").forEach(el => el.style.zoom = Math.max(.6, room).toFixed(3));
  };
  fitStickers();
  reels.scrollTop = keys.indexOf(current) * reels.clientHeight;
  reels.onclick = ev => {
    const pick = ev.target.closest("[data-pick]")?.dataset.pick;
    if (!pick) return;
    if (t) { saveTag({...t, design: pick}); toast(`Tasarım: ${DESIGNS[pick].name}`, 1500); history.back(); return; }
    draft.design = pick;
    store.set("lastDesign", pick);
    location.hash = "#/yeni/telefon";
  };
}

function showPhone(error = "", value = "") {
  show("2. Telefon numaranız", `
    <div class="steps"><span class="on"></span><span class="on"></span><span></span></div>
    <div class="preview">${stickerAt("······", draft.design, SITE, "50x75")}</div>
    ${error ? `<div class="msg err" role="alert" style="margin-top:14px">${esc(error)}</div>` : ""}
    <form id="f" novalidate>
      <label for="phone">QR okutulunca aranacak numara</label>
      <input id="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="05xx xxx xx xx" value="${esc(value || store.get("lastPhone", ""))}">
      <div class="hint">Numaranız QR'da ve camda yazmaz. QR'ı okutan kişi sizi arayabilsin diye arama ekranında görür. Numarayı sonradan değiştirebilirsiniz.</div>
      <button class="btn" type="submit">QR'ımı oluştur</button>
    </form>`, true);
  document.getElementById("f").addEventListener("submit", async ev => {
    ev.preventDefault();
    const raw = document.getElementById("phone").value;
    const phone = normalizePhone(raw);
    if (!phone) return showPhone("Numara geçersiz. Örnek: 0532 123 45 67", raw);
    ev.submitter && (ev.submitter.disabled = true, ev.submitter.textContent = "Oluşturuluyor…");
    let res;
    try { res = await rpc("self_tag_create", {p_phone: phone, p_device: deviceId()}); }
    catch (e) { return showPhone(navigator.onLine === false ? "İnternet bağlantısı yok. Bağlanıp tekrar deneyin." : "Sunucuya ulaşılamadı, biraz sonra tekrar deneyin.", raw); }
    if (!res?.ok) {
      return showPhone({bad_phone: "Numara geçersiz. Örnek: 0532 123 45 67",
        too_many: "Bugün çok fazla etiket oluşturdunuz. Yarın tekrar deneyin ya da Etiketlerim'deki etiketi kullanın.",
        busy: "Şu an çok yoğun, birkaç dakika sonra tekrar deneyin."}[res?.error] || "Etiket oluşturulamadı, tekrar deneyin.", raw);
    }
    store.set("lastPhone", raw);
    saveTag({code: res.code, pin: res.pin, phone, design: draft.design, size: "60x90", paper: "a4", copies: 1, created: Date.now()});
    location.replace(`#/etiket/${encodeURIComponent(res.code)}/yeni`);
  });
}

let celebrated = "";

function showTag(code, isNew) {
  const t = findTag(code);
  if (!t) { location.replace("#/"); return; }
  const {w, h} = dims(t.size);
  const maxCopies = t.paper === "a4" ? perA4({w, h}) * 4 : 30;
  // Önizleme ekrana sığsın: geniş stickerlarda küçült
  const fit = Math.min(1, (Math.min(innerWidth, 560) - 64) / (w * 96 / 25.4));
  show(isNew ? "3. Yazdırın" : t.code, `
    ${isNew ? `<div class="steps"><span class="on"></span><span class="on"></span><span class="on"></span></div>
      <div class="msg ok"><b>QR'ınız hazır!</b> Bu etiket ${esc(prettyPhone(t.phone))} numarasını arar.</div>` : ""}
    <div class="preview"><div style="zoom:${fit.toFixed(3)}">${stickerAt(t.code, t.design, qrLink(t.code), t.size)}</div></div>

    <div class="opts">
      <label>Tasarım</label>
      <a class="btn ghost" style="margin-top:0" href="#/etiket/${encodeURIComponent(t.code)}/tasarim">🎨 ${esc(DESIGNS[t.design]?.name || "")} · kaydırarak değiştir</a>
      <label for="size">Baskı ölçüsü</label>
      <select id="size">${Object.entries(SIZES).map(([k, n]) =>
        `<option value="${k}"${k === t.size ? " selected" : ""}>${n}</option>`).join("")}</select>
      <label>Kağıt</label>
      <div class="seg">
        <label><input type="radio" name="paper" value="a4"${t.paper === "a4" ? " checked" : ""}> A4 kağıda diz</label>
        <label><input type="radio" name="paper" value="tek"${t.paper === "tek" ? " checked" : ""}> Sayfa = sticker ölçüsü</label>
      </div>
      <div class="hint">${t.paper === "a4" ? `A4'e ${perA4({w, h})} adet sığar. Kesik çizgilerden kesin.` : "Etiket yazıcısı ya da matbaa için: her sticker kendi ölçüsünde ayrı sayfa."}</div>
      <label for="copies">Adet</label>
      <input id="copies" type="number" inputmode="numeric" min="1" max="${maxCopies}" value="${Math.min(t.copies || 1, maxCopies)}">
      <button class="btn" id="print" type="button">Yazdır / PDF olarak kaydet</button>
      <button class="btn alt" id="share" type="button">PDF paylaş (WhatsApp, matbaa…)</button>
      <div class="hint">Yazdırırken ölçeği <b>%100 / Gerçek boyut</b> seçin; “Sayfaya sığdır” ölçüleri bozar.</div>
    </div>

    <h2>Biz basıp kargolayalım</h2>
    <a class="ordercard" href="#/etiket/${encodeURIComponent(t.code)}/siparis">
      <span class="oc-icon" aria-hidden="true">📦</span>
      <span><b>Su geçirmez vinil sticker seti</b>Aynı QR, 6 farklı ölçüde 9 sticker · kargo ile kapınızda</span>
      <strong id="oc-price">…</strong>
    </a>

    <h2>Etiket bilgileri</h2>
    <div class="opts" style="padding-top:14px">
      <dl class="kv">
        <dt>Etiket kodu</dt><dd>${esc(t.code)}</dd>
        <dt>Aranacak numara</dt><dd>${esc(prettyPhone(t.phone))}</dd>
        <dt>PIN</dt><dd><span class="secret" id="pin">••••••</span> <button type="button" class="btn ghost" id="showpin" style="display:inline;width:auto;margin:0 0 0 6px;padding:4px 12px;font-size:14px">Göster</button></dd>
      </dl>
      <div class="hint">PIN numarayı değiştirmek için gerekir. Bu telefonda saklanır; telefon değiştirecekseniz bir yere not edin.</div>
      <a class="btn ghost" href="#/etiket/${encodeURIComponent(t.code)}/numara">Numarayı değiştir</a>
      <a class="btn ghost" href="${esc(qrLink(t.code))}">QR'ı dene (okutan kişinin göreceği sayfa)</a>
      <button class="btn danger" id="remove" type="button">Bu telefondan kaldır</button>
    </div>`, true);

  const update = patch => { saveTag({...t, ...patch}); showTag(code, isNew); };
  document.getElementById("size").onchange = ev => update({size: ev.target.value});
  app.querySelectorAll('input[name="paper"]').forEach(r => r.onchange = () => update({paper: r.value}));
  const copies = () => Math.max(1, Math.min(maxCopies, parseInt(document.getElementById("copies").value, 10) || 1));
  document.getElementById("copies").onchange = () => saveTag({...findTag(code), copies: copies()});
  document.getElementById("print").onclick = () => printTag(findTag(code), copies());
  document.getElementById("share").onclick = async ev => {
    ev.target.disabled = true; ev.target.textContent = "PDF hazırlanıyor…";
    try { await sharePdf(findTag(code), copies()); }
    catch (e) { toast("PDF oluşturulamadı: " + e.message); }
    ev.target.disabled = false; ev.target.textContent = "PDF paylaş (WhatsApp, matbaa…)";
  };
  document.getElementById("showpin").onclick = ev => {
    const el = document.getElementById("pin"), shown = el.textContent === t.pin;
    el.textContent = shown ? "••••••" : t.pin;
    ev.target.textContent = shown ? "Göster" : "Gizle";
  };
  document.getElementById("remove").onclick = () => {
    if (!confirm(`${t.code} bu telefondaki listeden kaldırılsın mı?\n\nQR çalışmaya devam eder; ama PIN'i not etmediyseniz numarasını bir daha değiştiremezsiniz.`)) return;
    store.set("tags", tags().filter(x => x.code !== t.code));
    location.replace("#/");
  };
  if (isNew && celebrated !== code) { celebrated = code; confetti(); }
  loadShop().then(shop => {
    const el = document.getElementById("oc-price");
    if (el) el.textContent = shop?.active ? `${shop.price} TL` : "Yakında";
  });
}

function showChangeNumber(code, error = "", value = "") {
  const t = findTag(code);
  if (!t) { location.replace("#/"); return; }
  show("Numarayı değiştir", `
    <p>${esc(t.code)} etiketini okutanlar artık bu numarayı arayacak. Sticker'ı yeniden basmanıza gerek yok.</p>
    ${error ? `<div class="msg err" role="alert">${esc(error)}</div>` : ""}
    <form id="f" novalidate>
      <label for="phone">Yeni numara</label>
      <input id="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="05xx xxx xx xx" value="${esc(value)}">
      <button class="btn" type="submit">Kaydet</button>
    </form>`, true);
  document.getElementById("f").addEventListener("submit", async ev => {
    ev.preventDefault();
    const raw = document.getElementById("phone").value, phone = normalizePhone(raw);
    if (!phone) return showChangeNumber(code, "Numara geçersiz. Örnek: 0532 123 45 67", raw);
    ev.submitter && (ev.submitter.disabled = true);
    let res;
    try { res = await rpc("self_tag_save", {p_code: t.code, p_pin: t.pin, p_phone: phone}); }
    catch (e) { return showChangeNumber(code, "Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.", raw); }
    if (!res?.ok) {
      return showChangeNumber(code, {locked: `Çok fazla deneme. ${res?.minutes || 15} dakika sonra tekrar deneyin.`,
        bad_phone: "Numara geçersiz.", bad_pin: "PIN eşleşmedi.", not_found: "Bu etiket sunucuda bulunamadı."}[res?.error] || "Kaydedilemedi.", raw);
    }
    saveTag({...t, phone: res.phone});
    toast(`Kaydedildi. QR artık ${prettyPhone(res.phone)} numarasını arar.`);
    history.back();
  });
}

// ---------------------------------------------------------------- baskı ve PDF
// #print alanını seçilen ölçü, kağıt ve adetle doldurur.
function fillPrint(t, copies) {
  const {w, h} = dims(t.size), box = document.getElementById("printarea");
  box.className = t.paper === "tek" ? "tek" : "a4";
  box.innerHTML = `<div class="grid${dims(t.size).k < .75 ? " small-size" : ""}" style="${sizeVars(t.size)}">${
    Array.from({length: copies}, () => stickerHtml(t.code, t.design, qrLink(t.code))).join("")}</div>`;
  document.getElementById("pagestyle").textContent = t.paper === "tek" ? `@page{size:${w}mm ${h}mm;margin:0}` : "@page{size:A4;margin:10mm}";
  return box;
}

async function printTag(t, copies) {
  fillPrint(t, copies);
  await document.fonts?.ready;
  const {w, h} = dims(t.size);
  const name = `Arac QR ${t.code}`;
  if (bridge) bridge.print(name, t.paper === "tek" ? w : 210, t.paper === "tek" ? h : 297);
  else print();
}

let pdfLibs;
function loadPdfLibs() {
  const load = src => new Promise((ok, fail) => document.head.append(Object.assign(document.createElement("script"),
    {src, onload: ok, onerror: () => fail(new Error("kütüphane yüklenemedi"))})));
  return pdfLibs ||= Promise.all([load("vendor/html2canvas.min.js"), load("vendor/jspdf.umd.min.js")]);
}

async function sharePdf(t, copies) {
  await loadPdfLibs();
  const box = fillPrint(t, copies);
  await document.fonts?.ready;
  const {w, h} = dims(t.size), PX = 25.4 / 96;
  const {jsPDF} = window.jspdf;
  const pdf = t.paper === "tek" ? new jsPDF({unit: "mm", format: [w, h], orientation: "portrait"}) : new jsPDF({unit: "mm", format: "a4"});
  const stickers = [...box.querySelectorAll(".sticker")];
  // aynı sticker'ı bir kez çiz, her kopyada tekrar kullan
  const r = stickers[0].getBoundingClientRect();
  const canvas = await html2canvas(stickers[0], {scale: 5, backgroundColor: "#ffffff", logging: false});
  const img = canvas.toDataURL("image/png"), sw = r.width * PX, sh = r.height * PX;
  if (t.paper === "tek") {
    stickers.forEach((_, i) => { if (i) pdf.addPage([w, h], "portrait"); pdf.addImage(img, "PNG", (w - sw) / 2, (h - sh) / 2, sw, sh, "st", "FAST"); });
  } else {
    const {W, H, M, G} = A4;
    let x = M, y = M;
    stickers.forEach(() => {
      if (x + sw > W - M + .1) { x = M; y += sh + G; }
      if (y + sh > H - M + .1) { pdf.addPage(); x = M; y = M; }
      pdf.addImage(img, "PNG", x, y, sw, sh, "st", "FAST");
      x += sw + G;
    });
  }
  const fileName = `arac-qr-${t.code}-${t.size}mm.pdf`;
  if (bridge) bridge.sharePdf(pdf.output("datauristring").split(",")[1], fileName);
  else pdf.save(fileName);
}

// ---------------------------------------------------------------- basılı sticker siparişi
const STATUS = {
  odeme_bekleniyor: "Ödeme bekleniyor", odeme_bildirildi: "Ödemeniz kontrol ediliyor", onaylandi: "Ödeme onaylandı, baskıya hazırlanıyor",
  baskida: "Baskıda", kargolandi: "Kargoya verildi", iptal: "İptal edildi",
};
const orders = () => store.get("orders", []);
const findOrder = code => orders().find(o => o.code === code);
function saveOrder(o) { store.set("orders", [o, ...orders().filter(x => x.code !== o.code)]); }

let shopCache;
async function loadShop() {
  try { shopCache = await rpc("shop_info", {}); store.set("shop", shopCache); }
  catch (e) { shopCache = shopCache || store.get("shop", null); }
  return shopCache;
}

function orderCardHtml(o) {
  return `<a class="card order st-${esc(o.status)}" href="#/odeme/${encodeURIComponent(o.code)}" data-order="${esc(o.code)}">
    <span class="oc-icon" aria-hidden="true">📦</span>
    <div><b>${esc(o.code)} · ${esc(o.amount)} TL</b><span class="ostatus">${esc(STATUS[o.status] || o.status)}${o.tracking ? ` · Takip no: ${esc(o.tracking)}` : ""}</span></div>
  </a>`;
}

// Sunucudan güncel sipariş durumlarını alır, listeyi yerinde günceller
async function refreshOrders() {
  const list = orders();
  if (!list.length) return;
  let rows;
  try { rows = await rpc("order_status", {p_codes: list.map(o => o.code), p_tokens: list.map(o => o.token)}); } catch (e) { return; }
  for (const r of rows || []) {
    const o = findOrder(r.code);
    if (!o) continue;
    saveOrder({...o, status: r.status, tracking: r.tracking});
    const card = document.querySelector(`[data-order="${CSS.escape(r.code)}"]`);
    if (card) card.outerHTML = orderCardHtml(findOrder(r.code));
  }
}

const PRODUCT_FEATURES = [
  ["💧", "Yağmura dayanıklı", "Su geçirmez vinil; yağmur, araç yıkama ve nemden etkilenmez."],
  ["☀️", "Güneşe dayanıklı", "UV dayanımlı baskı: renkler ve QR kod kolay kolay solmaz."],
  ["📐", "6 farklı ölçü, 9 sticker", "Aynı QR'ınız A4 sayfada: 80×120, 74×105, 60×90, 55×85, 50×75 mm ve 4 adet 40×60 mm. Cam, tampon, kask, bisiklet…"],
  ["✂️", "Kesime hazır", "Her sticker'ın kesim çizgisi var; makasla kolayca ayırırsınız."],
  ["🔒", "Numaranız güvende", "Numaranız sticker'da yazmaz; dilediğiniz zaman uygulamadan değiştirirsiniz, yeniden basmanız gerekmez."],
];

async function showOrder(tagCode, error = "", v = null) {
  const t = findTag(tagCode);
  if (!t) { location.replace("#/"); return; }
  show("Basılı sticker siparişi", "<p>Yükleniyor…</p>", true);
  const shop = await loadShop();
  if (!shop?.active) {
    return show("Basılı sticker siparişi", `
      <div class="msg info"><b>Basılı sipariş şu an kapalı.</b><br>Kısa süre içinde açılacak. Bu sırada etiketinizi kendiniz yazdırabilirsiniz.</div>
      <a class="btn" href="#/etiket/${encodeURIComponent(t.code)}">Etikete dön</a>`, true);
  }
  v = v || store.get("lastAddress", {}) || {};
  const val = k => `value="${esc(v[k] || "")}"`;
  const fit = Math.min(1, (Math.min(innerWidth, 560) - 64) / (190 * 96 / 25.4));
  show("Basılı sticker siparişi", `
    ${error ? `<div class="msg err" role="alert">${esc(error)}</div>` : ""}
    <div class="preview sheetprev"><div style="zoom:${fit.toFixed(3)}">${orderSheetHtml(t.code, t.design, qrLink(t.code))}</div></div>
    <div class="price"><span>A4 vinil sticker seti</span><strong>${esc(shop.price)} TL</strong></div>
    <div class="hint" style="text-align:center">${esc(shop.shipping_text)} Ödeme havale / EFT ile.</div>
    <ul class="features">${PRODUCT_FEATURES.map(([i, h, d]) => `<li><span aria-hidden="true">${i}</span><div><b>${h}</b>${d}</div></li>`).join("")}</ul>
    <a class="btn ghost" href="#/etiket/${encodeURIComponent(t.code)}/tasarim">🎨 Tasarım: ${esc(DESIGNS[t.design]?.name || "")} · değiştir</a>

    <h2>Teslimat adresi</h2>
    <form id="of" class="opts" style="padding-top:2px" novalidate>
      <label for="o-name">Ad soyad</label><input id="o-name" autocomplete="name" ${val("name")}>
      <label for="o-phone">Telefon (kargo için)</label>
      <input id="o-phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="05xx xxx xx xx" value="${esc(v.phone || prettyPhone(t.phone))}">
      <label for="o-email">E-posta <span style="font-weight:400;color:var(--muted)">(isteğe bağlı)</span></label>
      <input id="o-email" type="email" inputmode="email" autocomplete="email" ${val("email")}>
      <div class="row">
        <div><label for="o-city">İl</label><input id="o-city" autocomplete="address-level1" ${val("city")}></div>
        <div><label for="o-district">İlçe</label><input id="o-district" autocomplete="address-level2" ${val("district")}></div>
      </div>
      <label for="o-address">Açık adres</label>
      <textarea id="o-address" rows="3" autocomplete="street-address" placeholder="Mahalle, cadde/sokak, bina no, daire">${esc(v.address || "")}</textarea>
      <label for="o-note">Not <span style="font-weight:400;color:var(--muted)">(isteğe bağlı)</span></label>
      <input id="o-note" ${val("note")}>
      <label class="check"><input type="checkbox" id="o-ok"${v.ok ? " checked" : ""}> Bilgilerimin siparişimin basılıp kargolanması için kullanılmasını kabul ediyorum.</label>
      <button class="btn" type="submit">Ödemeye geç · ${esc(shop.price)} TL</button>
    </form>`, true);
  document.getElementById("of").addEventListener("submit", async ev => {
    ev.preventDefault();
    const g = id => document.getElementById(id).value.trim();
    const v2 = {name: g("o-name"), phone: g("o-phone"), email: g("o-email"), city: g("o-city"), district: g("o-district"),
      address: g("o-address"), note: g("o-note"), ok: document.getElementById("o-ok").checked};
    const phone = normalizePhone(v2.phone);
    const err = v2.name.length < 3 ? "Ad soyad yazın." : !phone ? "Telefon numarası geçersiz. Örnek: 0532 123 45 67"
      : v2.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v2.email) ? "E-posta adresi geçersiz."
      : !v2.city || !v2.district ? "İl ve ilçe yazın." : v2.address.length < 10 ? "Açık adresi eksiksiz yazın."
      : !v2.ok ? "Devam etmek için onay kutusunu işaretleyin." : "";
    if (err) return showOrder(tagCode, err, v2);
    store.set("lastAddress", {...v2, ok: false});
    ev.submitter && (ev.submitter.disabled = true, ev.submitter.textContent = "Sipariş oluşturuluyor…");
    let res;
    try {
      res = await rpc("order_create", {p_tag_code: t.code, p_design: t.design, p_full_name: v2.name, p_phone: phone, p_email: v2.email || null,
        p_city: v2.city, p_district: v2.district, p_address: v2.address, p_note: v2.note || null, p_device: deviceId()});
    } catch (e) { return showOrder(tagCode, "Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.", v2); }
    if (!res?.ok) {
      return showOrder(tagCode, {closed: "Basılı sipariş şu an kapalı.", no_tag: "Bu etiket sunucuda bulunamadı.",
        missing: "Adres bilgileri eksik.", bad_phone: "Telefon numarası geçersiz.", bad_email: "E-posta adresi geçersiz.",
        too_many: "Bugün çok fazla sipariş oluşturdunuz. Siparişlerim'den mevcut siparişinize devam edin.",
        busy: "Şu an çok yoğun, birkaç dakika sonra tekrar deneyin."}[res?.error] || "Sipariş oluşturulamadı.", v2);
    }
    saveOrder({code: res.code, token: res.token, amount: res.amount, status: res.status, tagCode: t.code, design: t.design, created: Date.now()});
    location.replace(`#/odeme/${encodeURIComponent(res.code)}`);
  });
}

function copyText(text) {
  const done = () => toast("Kopyalandı", 1500);
  if (navigator.clipboard && isSecureContext) return navigator.clipboard.writeText(text).then(done, () => fallback());
  fallback();
  function fallback() {
    const ta = Object.assign(document.createElement("textarea"), {value: text});
    ta.style.cssText = "position:fixed;opacity:0";
    document.body.append(ta); ta.select();
    try { document.execCommand("copy"); done(); } catch (e) { toast("Kopyalanamadı; uzun basıp kopyalayın"); }
    ta.remove();
  }
}

async function showPayment(orderCode) {
  const o = findOrder(orderCode);
  if (!o) { location.replace("#/"); return; }
  show(`Sipariş ${o.code}`, "<p>Yükleniyor…</p>", true);
  const [shop] = await Promise.all([loadShop(), refreshOrders()]);
  const cur = findOrder(orderCode);
  if (cur.status !== "odeme_bekleniyor") {
    return show(`Sipariş ${cur.code}`, `
      <div class="msg ${cur.status === "iptal" ? "err" : "ok"}"><b>${esc(STATUS[cur.status] || cur.status)}</b>${cur.tracking ? `<br>Kargo takip no: <b>${esc(cur.tracking)}</b>` : ""}</div>
      <ol class="timeline">${["odeme_bildirildi", "onaylandi", "baskida", "kargolandi"].map(st => {
        const order = ["odeme_bekleniyor", "odeme_bildirildi", "onaylandi", "baskida", "kargolandi"];
        return `<li class="${order.indexOf(cur.status) >= order.indexOf(st) ? "on" : ""}">${esc(STATUS[st])}</li>`;
      }).join("")}</ol>
      <p>Tutar: <b>${esc(cur.amount)} TL</b>. Sorunuz olursa sipariş numaranızla bize ulaşın.</p>
      <a class="btn ghost" href="#/">Ana sayfa</a>`, true);
  }
  const iban = (shop?.iban || "").replace(/(.{4})/g, "$1 ").trim();
  show("Ödeme", `
    <div class="price"><span>Ödenecek tutar</span><strong>${esc(cur.amount)} TL</strong></div>
    <ol class="paysteps">
      <li>Aşağıdaki IBAN'a <b>${esc(cur.amount)} TL</b> havale / EFT yapın.</li>
      <li>Açıklamaya sipariş numaranızı yazın: <b>${esc(cur.code)}</b></li>
      <li>Ödemeyi yaptıktan sonra aşağıdaki butona basın.</li>
    </ol>
    <div class="opts paybox">
      <dl class="kv">
        <dt>Alıcı</dt><dd>${esc(shop?.account_name || "")}</dd>
        ${shop?.bank_name ? `<dt>Banka</dt><dd>${esc(shop.bank_name)}</dd>` : ""}
        <dt>IBAN</dt><dd class="iban">${esc(iban)}</dd>
        <dt>Açıklama</dt><dd>${esc(cur.code)}</dd>
      </dl>
      <div class="row">
        <button class="btn ghost" type="button" id="cp-iban">IBAN'ı kopyala</button>
        <button class="btn ghost" type="button" id="cp-code">Sipariş no kopyala</button>
      </div>
    </div>
    <button class="btn" type="button" id="paid" style="background:var(--ok)">✅ Ödemeyi yaptım</button>
    <a class="btn ghost" href="#/">Daha sonra öderim</a>
    <div class="hint">Ödemeniz kontrol edildikten sonra stickerlarınız basılıp kargoya verilir. Durumu ana sayfadaki Siparişlerim bölümünden takip edebilirsiniz.</div>`, true);
  document.getElementById("cp-iban").onclick = () => copyText(shop?.iban || "");
  document.getElementById("cp-code").onclick = () => copyText(cur.code);
  document.getElementById("paid").onclick = async ev => {
    if (!confirm(`${cur.amount} TL ödemeyi ${cur.code} açıklamasıyla yaptığınızı onaylıyor musunuz?`)) return;
    ev.target.disabled = true;
    let res;
    try { res = await rpc("order_paid", {p_code: cur.code, p_token: cur.token}); }
    catch (e) { ev.target.disabled = false; return toast("Sunucuya ulaşılamadı, tekrar deneyin."); }
    if (!res?.ok) { ev.target.disabled = false; return toast("Sipariş bulunamadı."); }
    saveOrder({...cur, status: res.status});
    show("Sipariş iletildi", `
      <div class="empty" style="padding-top:10px">
        <div style="font-size:64px" aria-hidden="true">🎉</div>
        <h1>Siparişiniz iletildi!</h1>
        <p>Ödemeniz kontrol edildikten sonra stickerlarınız basılıp kargoya verilir. Sipariş no: <b>${esc(cur.code)}</b></p>
      </div>
      <a class="btn" href="#/">Siparişlerim</a>`, false);
    confetti();
  };
}

// ---------------------------------------------------------------- yönlendirme
function route() {
  const parts = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  if (parts[0] === "yeni" && parts[1] === "telefon") return showPhone();
  if (parts[0] === "yeni") return showDesigns();
  if (parts[0] === "etiket" && parts[2] === "numara") return showChangeNumber(parts[1]);
  if (parts[0] === "etiket" && parts[2] === "tasarim") return showDesigns(parts[1]);
  if (parts[0] === "etiket" && parts[2] === "siparis") return showOrder(parts[1]);
  if (parts[0] === "odeme") return showPayment(parts[1]);
  if (parts[0] === "etiket") return showTag(parts[1], parts[2] === "yeni");
  showHome();
}

document.getElementById("back").onclick = () => history.length > 1 ? history.back() : (location.hash = "#/");
addEventListener("hashchange", route);
route();
if (!store.get("onboarded", false)) showOnboarding();
