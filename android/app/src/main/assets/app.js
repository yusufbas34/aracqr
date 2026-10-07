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
function show(title, html, canGoBack) {
  document.getElementById("apptitle").textContent = title;
  document.getElementById("back").hidden = !canGoBack;
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
      <a class="btn" href="#/yeni">Başlayalım</a>`);
  }
  show("Etiketlerim", `
    <div class="cards">
      ${list.map(t => `
        <a class="card" href="#/etiket/${encodeURIComponent(t.code)}">
          ${stickerAt(t.code, t.design, qrLink(t.code), "40x60")}
          <div><b>${esc(t.code)}</b><span>${esc(prettyPhone(t.phone))}<br>${esc(DESIGNS[t.design]?.name || "")} · ${esc(SIZES[t.size] || "")}</span></div>
        </a>`).join("")}
    </div>
    <a class="btn" href="#/yeni">+ Yeni QR etiket oluştur</a>`);
}

let draft = {design: store.get("lastDesign", "klasik")};

function showDesigns() {
  const groups = [["Klasik", ([, d]) => !d.group], ["Eğlenceli", ([, d]) => d.group]];
  show("1. Tasarım seçin", `
    <div class="steps"><span class="on"></span><span></span><span></span></div>
    <p>Beğendiğiniz tasarıma dokunun. Daha sonra istediğiniz zaman değiştirebilirsiniz.</p>
    ${groups.map(([name, filter]) => `
      <div class="group">${name}</div>
      <div class="designs">
        ${Object.entries(DESIGNS).filter(filter).map(([k, d]) => `
          <button type="button" data-d="${k}" class="${k === draft.design ? "on" : ""}">
            ${stickerAt("ÖRNEK", k, SITE, "40x60")}${esc(d.name)}
          </button>`).join("")}
      </div>`).join("")}`, true);
  app.querySelectorAll(".designs button").forEach(b => b.onclick = () => {
    draft.design = b.dataset.d;
    store.set("lastDesign", draft.design);
    location.hash = "#/yeni/telefon";
  });
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
      <label for="design">Tasarım</label>
      <select id="design">${[["Klasik", d => !d.group], ["Eğlenceli", d => d.group]].map(([g, f]) =>
        `<optgroup label="${g}">${Object.entries(DESIGNS).filter(([, d]) => f(d)).map(([k, d]) =>
          `<option value="${k}"${k === t.design ? " selected" : ""}>${esc(d.name)}</option>`).join("")}</optgroup>`).join("")}</select>
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
  document.getElementById("design").onchange = ev => update({design: ev.target.value});
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

// ---------------------------------------------------------------- yönlendirme
function route() {
  const parts = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  if (parts[0] === "yeni" && parts[1] === "telefon") return showPhone();
  if (parts[0] === "yeni") return showDesigns();
  if (parts[0] === "etiket" && parts[2] === "numara") return showChangeNumber(parts[1]);
  if (parts[0] === "etiket") return showTag(parts[1], parts[2] === "yeni");
  showHome();
}

document.getElementById("back").onclick = () => history.length > 1 ? history.back() : (location.hash = "#/");
addEventListener("hashchange", route);
route();
