// Araç QR: uygulama dili. Türkçe metinler kaynaktır; L("Türkçe metin", {değişken}) seçili dildeki karşılığını döner,
// karşılığı yoksa Türkçesini. Sözlükler app/i18n/en.js, ar.js, ru.js. Basılan sticker'ların yazısı Türkçe kalır.
const LANGS = {tr: "Türkçe", en: "English", ar: "العربية", ru: "Русский"};
const I18N = {};
const LANG = (() => {
  try { const v = localStorage.getItem("aracqr-lang"); if (v && LANGS[v]) return v; } catch (e) {}
  const dev = (navigator.languages || [navigator.language]).map(l => String(l || "").slice(0, 2).toLowerCase()).find(l => LANGS[l]);
  return dev || "tr";
})();
const LOCALE = {tr: "tr-TR", en: "en-GB", ar: "ar", ru: "ru-RU"}[LANG];
document.documentElement.lang = LANG;
document.documentElement.dir = LANG === "ar" ? "rtl" : "ltr";

function L(text, vars) {
  const out = LANG === "tr" ? text : (I18N[LANG] && I18N[LANG][text]) || text;
  return vars ? out.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m)) : out;
}
// Tasarım adları sticker.js'te Türkçe tanımlı
const dName = k => L((typeof DESIGNS !== "undefined" && DESIGNS[k] && DESIGNS[k].name) || "");

function setLang(code) {
  if (!LANGS[code] || code === LANG) return;
  try { localStorage.setItem("aracqr-lang", code); } catch (e) {}
  location.reload();
}
const langSelectHtml = id => `<select id="${id}" class="lang-select" aria-label="${L("Uygulamanın dili")}">${Object.entries(LANGS).map(([k, n]) =>
  `<option value="${k}"${k === LANG ? " selected" : ""} lang="${k}">${n}</option>`).join("")}</select>`;

// index.html'deki sabit metinler: data-i18n (metin) ve data-i18n-label (aria-label)
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-i18n]").forEach(el => { el.textContent = L(el.textContent.trim()); });
  document.querySelectorAll("[data-i18n-label]").forEach(el => { el.setAttribute("aria-label", L(el.getAttribute("aria-label"))); });
});
