// İlk açılış tanıtımı: reels gibi dikey kaydırılan 4 tam ekran slayt. İllüstrasyonlar elle çizilmiş SVG.
// Kullanım: showOnboarding(() => { ... bitince ... })

// Kuşbakışı araba: (x, y) sol üst, w×h, renk; dir: "up" (ön yukarıda) ya da "right"
function topCar(x, y, w, h, color, dir = "up") {
  const r = Math.min(w, h) * .26;
  const glass = "#cfe6ff";
  if (dir === "right") {
    return `<g transform="translate(${x} ${y})">
      <rect width="${w}" height="${h}" rx="${r}" fill="${color}"/>
      <rect x="${w * .62}" y="${h * .12}" width="${w * .16}" height="${h * .76}" rx="${h * .12}" fill="${glass}"/>
      <rect x="${w * .14}" y="${h * .16}" width="${w * .12}" height="${h * .68}" rx="${h * .1}" fill="${glass}" opacity=".8"/>
      <rect x="${w * .3}" y="${h * .14}" width="${w * .3}" height="${h * .72}" rx="${h * .1}" fill="#000" opacity=".12"/>
      <rect x="${w * .64}" y="${-h * .08}" width="${w * .08}" height="${h * .12}" rx="2" fill="${color}"/>
      <rect x="${w * .64}" y="${h * .96}" width="${w * .08}" height="${h * .12}" rx="2" fill="${color}"/>
      <rect x="${w * .93}" y="${h * .12}" width="${w * .05}" height="${h * .18}" rx="2" fill="#ffd400"/>
      <rect x="${w * .93}" y="${h * .7}" width="${w * .05}" height="${h * .18}" rx="2" fill="#ffd400"/>
    </g>`;
  }
  return `<g transform="translate(${x} ${y})">
    <rect width="${w}" height="${h}" rx="${r}" fill="${color}"/>
    <rect x="${w * .12}" y="${h * .22}" width="${w * .76}" height="${h * .16}" rx="${w * .12}" fill="${glass}"/>
    <rect x="${w * .16}" y="${h * .74}" width="${w * .68}" height="${h * .12}" rx="${w * .1}" fill="${glass}" opacity=".8"/>
    <rect x="${w * .14}" y="${h * .4}" width="${w * .72}" height="${h * .3}" rx="${w * .1}" fill="#000" opacity=".12"/>
    <rect x="${-w * .08}" y="${h * .28}" width="${w * .12}" height="${h * .08}" rx="2" fill="${color}"/>
    <rect x="${w * .96}" y="${h * .28}" width="${w * .12}" height="${h * .08}" rx="2" fill="${color}"/>
    <rect x="${w * .12}" y="${h * .02}" width="${w * .18}" height="${h * .05}" rx="2" fill="#ffd400"/>
    <rect x="${w * .7}" y="${h * .02}" width="${w * .18}" height="${h * .05}" rx="2" fill="#ffd400"/>
  </g>`;
}

// Küçük QR deseni (dekoratif): (x, y) sol üst, s kenar
function miniQr(x, y, s, fg = "#111418", bg = "#fff") {
  const c = s / 7, f = (fx, fy) => `<rect x="${x + fx * c}" y="${y + fy * c}" width="${c * 3}" height="${c * 3}" fill="${fg}"/>
    <rect x="${x + (fx + .7) * c}" y="${y + (fy + .7) * c}" width="${c * 1.6}" height="${c * 1.6}" fill="${bg}"/>
    <rect x="${x + (fx + 1.1) * c}" y="${y + (fy + 1.1) * c}" width="${c * .8}" height="${c * .8}" fill="${fg}"/>`;
  const dots = [[4, 0], [5, 1], [4, 2], [6, 4], [4, 4], [5, 5], [3, 5], [4, 6], [6, 6], [3, 3]]
    .map(([dx, dy]) => `<rect x="${x + dx * c}" y="${y + dy * c}" width="${c}" height="${c}" fill="${fg}"/>`).join("");
  // zemin + 3 köşe deseni + noktalar
  return `<rect x="${x - c * .5}" y="${y - c * .5}" width="${s + c}" height="${s + c}" rx="${c * .6}" fill="${bg}"/>${f(0, 0)}${f(4, 0)}${f(0, 4)}${dots}`;
}

const ONB_SLIDES = [
  {
    bg: "linear-gradient(160deg,#1b2a52,#0f1115)",
    title: "Önünüz mü kapandı?",
    text: "Aracınızın önü kapanınca kimi arayacağınızı bilemezsiniz. Ya da birinin önünü kapattığınızda size ulaşamazlar.",
    art: () => `<svg viewBox="0 0 360 300" class="onb-art" role="img" aria-label="Park etmiş bir aracın arkasını başka bir araba kapatmış">
      <rect width="360" height="300" rx="22" fill="#3a3f4b"/>
      <g stroke="#ffffff" stroke-opacity=".55" stroke-width="3">
        <path d="M60 20v130M140 20v130M220 20v130M300 20v130"/>
      </g>
      <path d="M0 190h360" stroke="#ffd400" stroke-width="3" stroke-dasharray="18 14" opacity=".6"/>
      ${topCar(74, 34, 52, 100, "#8a93a6")}
      ${topCar(154, 34, 52, 100, "#2f6fb5")}
      ${topCar(234, 34, 52, 100, "#6c7487")}
      <g class="onb-slide-in">${topCar(118, 160, 128, 62, "#e4572e", "right")}</g>
      <g class="onb-pop">
        <path d="M206 88h120a14 14 0 0 1 14 14v34a14 14 0 0 1-14 14h-74l-20 18 4-18h-30a14 14 0 0 1-14-14v-34a14 14 0 0 1 14-14z" fill="#fff"/>
        <text x="266" y="126" text-anchor="middle" font-family="Barlow,sans-serif" font-weight="700" font-size="19" fill="#111418">Kimin bu araba?!</text>
      </g>
      <g class="onb-blink"><circle cx="180" cy="84" r="16" fill="#e4002b"/><path d="M180 74v12M180 91v2" stroke="#fff" stroke-width="4" stroke-linecap="round"/></g>
    </svg>`,
  },
  {
    bg: "linear-gradient(160deg,#0a3a9e,#071d4f)",
    title: "Camınıza QR'ınızı yapıştırın",
    text: "Size özel QR'ı tasarımını seçerek oluşturun ve aracınızın camına yapıştırın. Numaranız camda yazmaz.",
    art: () => `<svg viewBox="0 0 360 300" class="onb-art" role="img" aria-label="Önden görünen bir arabanın ön camına QR sticker yapışıyor">
      <rect width="360" height="300" rx="22" fill="#dfe9ff"/>
      <circle cx="300" cy="56" r="28" fill="#ffd400" opacity=".8"/>
      <path d="M0 236h360v64H0z" fill="#9fb3d9"/>
      <path d="M40 262h280" stroke="#fff" stroke-width="4" stroke-dasharray="26 18"/>
      <g transform="translate(66 52)">
        <rect x="18" y="186" width="34" height="34" rx="6" fill="#0b1530"/>
        <rect x="176" y="186" width="34" height="34" rx="6" fill="#0b1530"/>
        <path d="M54 30q6-16 24-16h72q18 0 24 16l22 64h14q16 0 16 16v64q0 16-16 16H18q-16 0-16-16v-64q0-16 16-16h14z" fill="#ffffff"/>
        <path d="M66 38q4-10 16-10h64q12 0 16 10l18 56H48z" fill="#cfe0ff"/>
        <rect x="14" y="118" width="40" height="16" rx="8" fill="#ffd400"/>
        <rect x="174" y="118" width="40" height="16" rx="8" fill="#ffd400"/>
        <rect x="84" y="142" width="60" height="12" rx="6" fill="#c9d3e8"/>
        <g class="onb-stick">
          <rect x="94" y="34" width="44" height="54" rx="5" fill="#0a3a9e"/>
          <rect x="98" y="38" width="36" height="7" rx="2" fill="#fff" opacity=".9"/>
          ${miniQr(101, 50, 30)}
        </g>
      </g>
      <g class="onb-sparkle" fill="#fff"><path d="M236 70l4 10 10 4-10 4-4 10-4-10-10-4 10-4z"/><path d="M116 64l3 7 7 3-7 3-3 7-3-7-7-3 7-3z"/></g>
    </svg>`,
  },
  {
    bg: "linear-gradient(160deg,#0c5e37,#06291a)",
    title: "Okutan sizi tek dokunuşla arar",
    text: "QR'ı telefon kamerasıyla okutan kişi uygulama indirmeden sizi arar. Numaranızı istediğiniz zaman değiştirirsiniz.",
    art: () => `<svg viewBox="0 0 360 300" class="onb-art" role="img" aria-label="Telefon kamerası QR'ı tarıyor, ardından arama ekranı açılıyor">
      <rect width="360" height="300" rx="22" fill="#e6f4ec"/>
      <g transform="translate(46 26)">
        <rect width="128" height="248" rx="22" fill="#111418"/>
        <rect x="8" y="10" width="112" height="228" rx="16" fill="#2b3240"/>
        <g stroke="#5ef2a0" stroke-width="4" fill="none" stroke-linecap="round">
          <path d="M24 70v-16h16M88 54h16v16M104 154v16H88M40 170H24v-16"/>
        </g>
        ${miniQr(38, 76, 52)}
        <rect class="onb-scan" x="22" y="110" width="84" height="3" rx="1.5" fill="#5ef2a0"/>
        <rect x="34" y="196" width="60" height="10" rx="5" fill="#ffffff" opacity=".25"/>
      </g>
      <path class="onb-arrow" d="M186 150h26m-10-10 10 10-10 10" stroke="#0c7a43" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      <g transform="translate(222 26)">
        <rect width="104" height="248" rx="22" fill="#111418"/>
        <rect x="8" y="10" width="88" height="228" rx="16" fill="#0c7a43"/>
        <circle cx="52" cy="70" r="24" fill="#ffffff" opacity=".9"/>
        <path d="M52 58a8 8 0 1 1 0 16 8 8 0 0 1 0-16zm-16 30q4-10 16-10t16 10" fill="#0c7a43"/>
        <rect x="22" y="110" width="60" height="9" rx="4.5" fill="#fff" opacity=".9"/>
        <rect x="30" y="126" width="44" height="7" rx="3.5" fill="#fff" opacity=".55"/>
        <g class="onb-ring">
          <circle cx="52" cy="196" r="20" fill="#2ecc71"/>
          <g transform="translate(40 184)"><path d="M6.62,10.79c1.44,2.83 3.76,5.14 6.59,6.59l2.2,-2.2c0.27,-0.27 0.67,-0.36 1.02,-0.24 1.12,0.37 2.33,0.57 3.57,0.57 0.55,0 1,0.45 1,1V20c0,0.55 -0.45,1 -1,1 -9.39,0 -17,-7.61 -17,-17 0,-0.55 0.45,-1 1,-1h3.5c0.55,0 1,0.45 1,1 0,1.25 0.2,2.45 0.57,3.57 0.11,0.35 0.03,0.74 -0.25,1.02l-2.2,2.2z" fill="#fff"/></g>
        </g>
        <circle class="onb-wave" cx="52" cy="196" r="20" fill="none" stroke="#2ecc71" stroke-width="3"/>
      </g>
    </svg>`,
  },
  {
    bg: "linear-gradient(160deg,#5b2a86,#1a0f2b)",
    title: "Tasarımını seç, yazdır ya da biz gönderelim",
    text: "17 tasarım, 8 baskı ölçüsü. Evde yazdırın ya da su geçirmez vinil sticker setinizi biz basıp kargolayalım.",
    art: () => `<div class="onb-fan" role="img" aria-label="Üç farklı sticker tasarımı ve kargo kutusu">
      ${["kedi", "klasik", "nazar"].map((d, i) => `<div class="onb-card c${i}">${stickerAt("ÖRNEK", d, SITE, "40x60")}</div>`).join("")}
      <div class="onb-box" aria-hidden="true">📦</div>
    </div>`,
  },
];

function showOnboarding(onDone) {
  const wrap = document.createElement("div");
  wrap.className = "onb";
  wrap.setAttribute("role", "dialog");
  wrap.setAttribute("aria-label", "Araç QR tanıtımı");
  const last = ONB_SLIDES.length - 1;
  wrap.innerHTML = `
    <button class="onb-skip" type="button">Geç</button>
    <div class="onb-dots" aria-hidden="true">${ONB_SLIDES.map((_, i) => `<span class="${i ? "" : "on"}"></span>`).join("")}</div>
    <div class="onb-reels">
      ${ONB_SLIDES.map((sl, i) => `
        <section class="onb-slide" style="background:${sl.bg}" data-i="${i}">
          <div class="onb-artbox">${sl.art()}</div>
          <div class="onb-copy">
            <h1>${esc(sl.title)}</h1>
            <p>${esc(sl.text)}</p>
            ${i === last ? `<button class="btn onb-go" type="button">Başlayalım</button>` : `<div class="swipe">⌃ Devam etmek için yukarı kaydırın</div>`}
          </div>
        </section>`).join("")}
    </div>`;
  document.body.append(wrap);
  document.body.classList.add("onb-open");
  const reels = wrap.querySelector(".onb-reels"), dots = wrap.querySelectorAll(".onb-dots span");
  const slides = wrap.querySelectorAll(".onb-slide");
  // Görünür slaytın animasyonlarını yeniden başlat
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (!e.isIntersecting) { e.target.classList.remove("play"); return; }
    e.target.classList.add("play");
    dots.forEach((d, i) => d.classList.toggle("on", i === Number(e.target.dataset.i)));
  }), {root: reels, threshold: .6});
  slides.forEach(s => io.observe(s));
  const close = () => {
    io.disconnect();
    store.set("onboarded", true);
    document.body.classList.remove("onb-open");
    wrap.remove();
    onDone && onDone();
  };
  wrap.querySelector(".onb-skip").onclick = close;
  wrap.querySelector(".onb-go").onclick = close;
}
