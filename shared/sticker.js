// Araç QR: sticker tasarımları ve baskı ölçüleri. Web sitesi (index.html) ve Android uygulaması ortak kullanır.
// Gerekenler: qrcode-generator (global `qrcode`) ve shared/sticker.css.

const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

function qrSvg(text) {
  const q = qrcode(0, "H"); // yüksek hata düzeltme: çizik/solmaya dayanıklı
  q.addData(text); q.make();
  return q.createSvgTag({cellSize: 4, margin: 2, scalable: true});
}

// ---------------------------------------------------------------- tasarımlar
const svgCat = `<svg class="ic-cat" viewBox="0 0 40 34" aria-hidden="true"><path d="M5 30V6l9 7h12l9-7v24c0 2-2 3-4 3H9c-2 0-4-1-4-3z" fill="#f3a25a" stroke="#d9682b" stroke-width="2" stroke-linejoin="round"/><circle cx="14" cy="20" r="2.4" fill="#2a1a10"/><circle cx="26" cy="20" r="2.4" fill="#2a1a10"/><path d="M18 24h4l-2 2.2z" fill="#d9426b"/><path d="M20 26.2q-2 2.5-4 1M20 26.2q2 2.5 4 1" stroke="#2a1a10" stroke-width="1" fill="none" stroke-linecap="round"/><path d="M1 22l9 1M1 26l9-1M39 22l-9 1M39 26l-9-1" stroke="#2a1a10" stroke-width=".8"/></svg>`;
const svgSmile = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="#ffd400" stroke="#fff" stroke-width="1.5"/><circle cx="8.5" cy="10" r="1.4" fill="#222"/><circle cx="15.5" cy="10" r="1.4" fill="#222"/><path d="M7 14.5q5 5 10 0" stroke="#222" stroke-width="1.6" fill="none" stroke-linecap="round"/><ellipse cx="6" cy="14" rx="1.6" ry="1" fill="#ff8aa0"/><ellipse cx="18" cy="14" rx="1.6" ry="1" fill="#ff8aa0"/></svg>`;
const svgStripe = `<div class="stripe"><svg viewBox="0 0 120 7" preserveAspectRatio="none" aria-hidden="true"><rect width="120" height="7" fill="#ffd400"/>${Array.from({length: 13}, (_, i) => `<path d="M${i * 10 - 4} 7l7-7h5l-7 7z" fill="#111"/>`).join("")}</svg></div>`;
const svgStars = `<svg class="deco" viewBox="0 0 100 150" preserveAspectRatio="none" aria-hidden="true">${[[5,30],[95,34],[4,60],[96,66],[5,95],[95,100],[4,122],[96,120],[8,8],[22,4]].map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${i % 3 ? .7 : 1.1}" fill="#fff" opacity=".8"/>`).join("")}</svg>`;
const svgMoon = `<svg class="ic-moon" viewBox="0 0 20 20" aria-hidden="true"><path d="M15 15A8 8 0 1 1 9 2a6.2 6.2 0 0 0 6 13z" fill="#ffe28a"/></svg>`;
const svgSun = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="#ffd166"/><path d="M0 13.5h24M0 16.5h24M0 19.5h24" stroke="#7a2a8c" stroke-width="1.5"/></svg>`;
const svgRocket = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1c4 3 5 7.5 4 13H8C7 8.5 8 4 12 1z" fill="#e8ecf5"/><circle cx="12" cy="8.5" r="2.2" fill="#5ec8ff" stroke="#101a3d" stroke-width=".6"/><path d="M8 13l-3.5 4.5L8.5 17zM16 13l3.5 4.5-4-.5z" fill="#ff7849"/><path d="M10 15h4l-2 7z" fill="#ffd166"/></svg>`;
const svgCup = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 1.5q-1.2 2 0 3.2t0 3.3M12 1.5q-1.2 2 0 3.2t0 3.3" stroke="#fff" stroke-width="1.3" fill="none" stroke-linecap="round"/><path d="M3 10h14v4.5a6.5 6.5 0 0 1-6.5 6.5h-1A6.5 6.5 0 0 1 3 14.5z" fill="#fff"/><path d="M17 12h1.6a2.6 2.6 0 0 1 0 5.2H16.4" stroke="#fff" stroke-width="1.7" fill="none"/></svg>`;
const svgDog = `<svg class="ic-cat" viewBox="0 0 40 34" aria-hidden="true"><ellipse cx="20" cy="18" rx="12" ry="12.5" fill="#c98b4f"/><path d="M9 7Q2 8 3 21q4.5 1.5 7.5-6zM31 7q7 1 6 14-4.5 1.5-7.5-6z" fill="#7a4a24"/><ellipse cx="20" cy="24.5" rx="7" ry="5.5" fill="#f1d3b0"/><circle cx="15" cy="16.5" r="2.1" fill="#222"/><circle cx="25" cy="16.5" r="2.1" fill="#222"/><ellipse cx="20" cy="21.5" rx="2.8" ry="1.9" fill="#222"/><path d="M20 23.4v2.2M17 26.4q3 2.2 6 0" stroke="#222" stroke-width="1" fill="none" stroke-linecap="round"/><path d="M18.8 27.4q1.2 4.2 2.4 0z" fill="#e8607a"/></svg>`;
const svgBurst = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 0l2.5 6 6-3-2 6.5 5.5 2.5-5.5 2.5 2 6.5-6-3L12 24l-2.5-6-6 3 2-6.5L0 12l5.5-2.5-2-6.5 6 3z" fill="#ffd400" stroke="#111" stroke-width=".8"/><path d="M11 6.5h2l-.4 7.5h-1.2zM12 15.6a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z" fill="#e4002b"/></svg>`;
const svgDots = `<svg class="deco" aria-hidden="true"><defs><pattern id="aracqr-dots" width="7" height="7" patternUnits="userSpaceOnUse"><circle cx="3.5" cy="3.5" r="1.3" fill="#e4002b" fill-opacity=".28"/></pattern></defs><rect width="100%" height="100%" fill="url(#aracqr-dots)"/></svg>`;
const svgLight = `<svg class="ic-light" viewBox="0 0 36 14" aria-hidden="true"><rect x=".5" y=".5" width="35" height="13" rx="6.5" fill="#111" stroke="#666"/><circle cx="7" cy="7" r="4.2" fill="#ff3b30"/><circle cx="18" cy="7" r="4.2" fill="#ffcc00"/><circle cx="29" cy="7" r="4.2" fill="#2ecc71"/></svg>`;
const svgCard = `<svg class="ic-card" viewBox="0 0 16 22" aria-hidden="true"><rect x="2.5" y="1.5" width="11" height="17" rx="1.5" fill="#ffd400" stroke="#111" stroke-width=".8" transform="rotate(12 8 10)"/></svg>`;
const svgPitch = `<svg class="deco" viewBox="0 0 100 150" preserveAspectRatio="none" aria-hidden="true"><g stroke="#fff" stroke-opacity=".3" stroke-width=".8" fill="none"><rect x="3" y="3" width="94" height="144"/><path d="M3 75h94"/><ellipse cx="50" cy="75" rx="15" ry="10"/><rect x="28" y="3" width="44" height="14"/><rect x="28" y="133" width="44" height="14"/></g></svg>`;
const svgFlower = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><g fill="#ff8fb8">${[0, 72, 144, 216, 288].map(a => `<ellipse cx="12" cy="6" rx="3.6" ry="5.2" transform="rotate(${a} 12 12)"/>`).join("")}</g><circle cx="12" cy="12" r="3.3" fill="#ffd166"/></svg>`;
const svgHeart = `<svg class="ic-smile" viewBox="0 0 7 6" shape-rendering="crispEdges" aria-hidden="true"><path fill="#ff2d55" d="M1 0h2v1H1zM4 0h2v1H4zM0 1h7v2H0zM1 3h5v1H1zM2 4h3v1H2zM3 5h1v1H3z"/></svg>`;
const svgNazar = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11.3" fill="#1565c0" stroke="#fff" stroke-width="1.2"/><circle cx="12" cy="12" r="7.6" fill="#fff"/><circle cx="12" cy="12" r="5" fill="#5ec8ff"/><circle cx="12" cy="12" r="2.6" fill="#111"/></svg>`;
const svgClock = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="13" r="10" fill="#fff" stroke="#111" stroke-width="1.6"/><path d="M12 7v6l4 2.5" stroke="#e4002b" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M5 3.5 2.5 6M19 3.5 21.5 6" stroke="#111" stroke-width="1.8" stroke-linecap="round"/></svg>`;
const svgTea = `<svg class="ic-tea" viewBox="0 0 24 30" aria-hidden="true"><path d="M8 3q-1 2 0 3.5T8 10M12 2q-1 2 0 3.5T12 9M16 3q-1 2 0 3.5T16 10" stroke="#fff" stroke-width="1.2" fill="none" stroke-linecap="round" opacity=".85"/><path d="M5 11h14q0 3-2.2 5.2Q15 18 16.5 21T15 27H9q-3-3-1.5-6T7.2 16.2Q5 14 5 11z" fill="#fff" fill-opacity=".35" stroke="#fff" stroke-width="1"/><path d="M6.2 13h11.6q-.6 2.2-2.6 3.6-1.4 1.4.2 4.2t-.9 5.2H9.5q-2.5-2.6-1.1-5.2t.2-4.2Q6.8 15.2 6.2 13z" fill="#c0392b"/><ellipse cx="12" cy="28" rx="7" ry="1.6" fill="#fff"/></svg>`;
const svgPin = `<svg class="ic-smile" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="9" r="6" fill="#e4002b"/><circle cx="10" cy="7" r="2" fill="#fff" opacity=".5"/><path d="M12 15v8" stroke="#555" stroke-width="2" stroke-linecap="round"/></svg>`;
const svgGrade = `<span class="grade" aria-label="10 üzerinden 2">2<small>/10</small></span>`;
const svgStarRow = `<div class="kamyon-stars" aria-hidden="true">★ ✿ ★ ✿ ★ ✿ ★</div>`;
const MSG = "Bu aracın sahibine ulaşmak için QR kodu okutun";
const HOW = "Telefon kameranızı açın, kodu okutun,<br>tek dokunuşla arayın.";

const FUN = "Eğlenceli";
const DESIGNS = {
  klasik:   {name: "Klasik mavi", top: "ARAÇ SAHİBİNE ULAŞIN", msg: MSG, how: HOW},
  plaka:    {name: "Plaka", top: `<span class="tr">TR</span><span class="t">SAHİBİNE ULAŞ</span>`, msg: MSG, how: HOW},
  dikkat:   {name: "Dikkat şeritli", pre: svgStripe, top: "PARK SORUNU MU?", msg: MSG, how: HOW, post: svgStripe},
  minimal:  {name: "Sade (az mürekkep)", top: "ARAÇ SAHİBİNE ULAŞIN", msg: MSG, how: HOW},
  kamyon:   {name: "Kamyon arkası", group: FUN, isNew: true, pre: svgStarRow, top: "KADER BİZİ BU OTOPARKTA BULUŞTURDU",
             msg: "Şoförsen bas gaza, önün kapandıysa okut bu kodu!", how: "Gazla uçabilirsin ama<br>önce bir okut, sahibi gelsin.", post: svgStarRow},
  karne:    {name: "Park karnesi", group: FUN, isNew: true, top: `PARK KARNESİ${svgGrade}`,
             msg: "Kötü park ettiysem affedin! QR'ı okutun, hemen gelip düzelteyim.", how: "Karneyi silecek altına bırakmayın,<br>okutup arayın yeter."},
  postit:   {name: "Not bırakmayın", group: FUN, isNew: true, top: `${svgPin}NOT BIRAKMAYA GEREK YOK!`,
             msg: "Silecek altına kâğıt sıkıştırmayın; QR'ı okutun, beni arayın.", how: "Yağmurda ıslanan notlar<br>artık tarih oldu."},
  mim:      {name: "Mim (meme)", group: FUN, isNew: true, top: "PARK YERİ YOK MU?",
             msg: "Bu aracın sahibine ulaşmak için QR kodu okutun", how: "", post: `<div class="mim-bottom">QR'I OKUT,<br>SAHİBİ GELSİN</div>`},
  besdk:    {name: "5 dakikaya geliyorum", group: FUN, isNew: true, top: `${svgClock}5 DK'YA GELİYORUM`,
             msg: "Söz, gerçekten 5 dakika! Gecikirsem QR'ı okutup arayın.", how: "Türk usulü 5 dakika değil,<br>gerçek 5 dakika."},
  cay:      {name: "Çay molası", group: FUN, isNew: true, top: `${svgTea}<span>BİR ÇAY İÇİP<br>GELİYORUM</span>`,
             msg: "Çayım soğumadan gelirim! Acilse QR'ı okutun.", how: "Demli mi açık mı?<br>Önce arayın, sonra karar verelim."},
  gece:     {name: "Gece yıldızlı", group: FUN, pre: svgStars, top: `SAHİBİNE ULAŞ${svgMoon}`, msg: MSG, how: "Gece gündüz fark etmez,<br>tek dokunuşla arayın."},
  kedi:     {name: "Miyav kedi", group: FUN, top: `${svgCat}MİYAV!`, msg: "Sahibime ulaşmak için QR kodu okut, hemen gelsin!",
             how: "Kameranı aç, kodu okut, ara.<br>Patiler seni bekliyor."},
  kopek:    {name: "Hav hav köpek", group: FUN, top: `${svgDog}HAV HAV!`, msg: "Sahibimi çağırmak için QR kodu okut, kuyruğumu sallayayım!",
             how: "Kameranı aç, kodu okut, ara.<br>Kemik sözü veremem ama teşekkürler!"},
  ozur:     {name: "Kusura bakmayın", group: FUN, top: `${svgSmile}YOLUNUZU MU KAPATTIM?`,
             msg: "Kusura bakmayın! Bana ulaşmak için QR kodu okutun, hemen geleyim.", how: "Kameranızı açın, kodu okutun,<br>tek dokunuşla arayın."},
  kahve:    {name: "Kahve molası", group: FUN, top: `${svgCup}KAHVE MOLASINDAYIM`, msg: "Hemen dönüyorum! Bana ulaşmak için QR kodu okutun.",
             how: "Kameranızı açın, kodu okutun,<br>köpüğü sönmeden geleyim."},
  retro:    {name: "Retro 80'ler", group: FUN, top: `${svgSun}SAHİBİNE ULAŞ`, msg: MSG, how: "Kaseti geri sar, kodu okut,<br>tek dokunuşla ara."},
  roket:    {name: "Uzay roketi", group: FUN, pre: svgStars, top: `${svgRocket}HOUSTON, PARK SORUNU!`,
             msg: "Sahibini Dünya'ya geri çağırmak için QR kodu okut!", how: "3, 2, 1… kodu okut,<br>tek dokunuşla ara."},
  kahraman: {name: "Süper kahraman", group: FUN, pre: svgDots, top: `${svgBurst}SÜPER SAHİP ÇAĞRISI!`,
             msg: "Bu aracın süper sahibini çağırmak için QR kodu okut!", how: "Pelerin gerekmez,<br>tek dokunuşla ara."},
  lamba:    {name: "Trafik lambası", group: FUN, top: `${svgLight}<span>DUR! ÖNCE OKUT</span>`,
             msg: "Aracın sahibine ulaşmak için QR kodu okutun, yol açılsın.", how: "Kırmızıdan yeşile<br>tek dokunuşla."},
  sarikart: {name: "Sarı kart", group: FUN, pre: svgPitch, top: `${svgCard}HATALI PARK MI?`,
             msg: "Sarı kartı çıkarmadan önce QR kodu okutup sahibine ulaşın!", how: "VAR'a gerek yok,<br>tek dokunuşla arayın."},
  cicek:    {name: "Bahar çiçekleri", group: FUN, top: `${svgFlower}MERHABA KOMŞU!${svgFlower}`, msg: MSG,
             how: "Kameranızı açın, kodu okutun,<br>gülümseyerek arayın."},
  piksel:   {name: "Piksel oyun", group: FUN, top: `${svgHeart}PRESS START${svgHeart}`, msg: "OYUNCU 2: Sahibini çağırmak için QR'ı okut!",
             how: "1 OYUNCU · TEK DOKUNUŞ<br>SINIRSIZ CAN"},
  nazar:    {name: "Nazar boncuğu", group: FUN, top: `${svgNazar}MAŞALLAH!`, msg: MSG, how: "Nazar değmesin,<br>park sorunu da olmasın."},
};
const RANDOM = "rastgele";
const pickRandom = () => { const k = Object.keys(DESIGNS); return k[Math.floor(Math.random() * k.length)]; };

// İnternetten tanıdık kalıplarla hazır sözler: herhangi bir tasarımın mesaj satırının yerine geçer.
// Anahtar kaydedilir (sipariş/baskıda metin değil anahtar taşınır), metin burada tek yerde durur.
const PHRASES = {
  olm:      "Olm bi saniye, geliyorum! QR'ı okut, ara.",
  asiri:    "Aşırı özür dilerim! QR'ı okutun, hemen geleyim.",
  aura:     "Kötü park: -1000 aura. QR'ı okut, aura'mı geri kazanayım.",
  npc:      "NPC gibi bekleme, QR'ı okut, sahibi gelsin!",
  plot:     "Plot twist: QR'ı okutursan sahibi 2 dakikada gelir.",
  spoiler:  "Spoiler: QR'ı okutursan bu hikâye mutlu biter.",
  ana:      "Ana karakter enerjisiyle park ettim, affet. Okut, geleyim.",
  kanka:    "Kanka çıkamıyorsan QR'ı okut, hemen geliyorum.",
  sakin:    "Sakin ol şampiyon! QR'ı okut, 5 dakikaya buradayım.",
  hayirdir: "Hayırdır kardeşim? QR'ı okut, tatlıya bağlayalım.",
  kimbu:    "Kimin bu araba? Benim! QR'ı okut, ara beni.",
  abi:      "Abi bi okut ya, hemen gelip çekiyorum.",
  efsane:   "Bu park efsane değil, biliyorum. Okut, düzelteyim.",
  test:     "Bu bir tatbikat değildir: QR'ı okut, sahibi gelsin!",
  mod:      "Mod: geç kaldım. QR'ı okut, koşarak geleyim.",
  bekleme:  "Bekleme yapma, QR'ı okut! (lütfen)",
};
const pickPhrase = () => { const k = Object.keys(PHRASES); return k[Math.floor(Math.random() * k.length)]; };

// Tasarım metinleri sabit HTML; yalnızca kod kaçışlanır. phrase: PHRASES anahtarı (isteğe bağlı)
function stickerHtml(code, design, link = tagLink(code), phrase) {
  const d = DESIGNS[design] ? design : "klasik", D = DESIGNS[d];
  const msg = PHRASES[phrase] ? esc(PHRASES[phrase]) : D.msg;
  return `<div class="sticker d-${d}"><div class="in">${D.pre || ""}
      <div class="top">${D.top}</div>
      <div class="msgline">${msg}</div>
      <div class="qr"><div class="box">${qrSvg(link)}</div></div>
      <div class="how">${D.how}</div>
      <div class="code">${esc(code)}</div>${D.post || ""}
    </div></div>`;
}

// ---------------------------------------------------------------- baskı ölçüleri
const SIZES = {
  "40x60": "Küçük 40×60 mm",
  "50x75": "Orta 50×75 mm",
  "55x85": "Kartvizit 55×85 mm",
  "60x90": "Standart 60×90 mm",
  "74x105": "A7 74×105 mm",
  "80x120": "Büyük 80×120 mm",
  "100x150": "Etiket yazıcısı 100×150 mm (4×6 inç)",
  "105x148": "A6 105×148 mm",
};
const A4 = {W: 210, H: 297, M: 10, G: 3};
const dims = size => { const [w, h] = size.split("x").map(Number); return {w, h, k: Math.min(w / 60, h / 90)}; };
const perA4 = ({w, h}) => Math.floor((A4.W - 2 * A4.M + A4.G) / (w + A4.G)) * Math.floor((A4.H - 2 * A4.M + A4.G) / (h + A4.G));

// ---------------------------------------------------------------- basılı sipariş sayfası
// A4 vinil sayfa: aynı QR 6 farklı ölçüde, toplam 9 sticker. 190×277 mm baskı alanına sığar (10 mm kenar boşluğu).
const ORDER_SHEET = [["80x120", "74x105"], ["60x90", "55x85", "50x75"], ["40x60", "40x60", "40x60", "40x60"]];
const ORDER_SIZES = [...new Set(ORDER_SHEET.flat())];

function orderSheetHtml(code, design, link, phrase) {
  return `<div class="sheet">${ORDER_SHEET.map(row => `<div class="sheet-row">${row.map(size => {
    const {w, h, k} = dims(size);
    return `<div class="grid${k < .75 ? " small-size" : ""}" style="--w:${w}mm;--h:${h}mm;--k:${k}">${stickerHtml(code, design, link, phrase)}</div>`;
  }).join("")}</div>`).join("")}</div>`;
}
