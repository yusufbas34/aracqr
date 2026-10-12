// Instagram görsellerini kit.html'den PNG olarak üretir: node pazarlama/uret.js (Playwright gerekir)
const path = require("path"), fs = require("fs");
const { chromium } = require(process.env.PW || "playwright");
(async () => {
  const out = path.join(__dirname, "instagram"); fs.mkdirSync(out, {recursive: true});
  const b = await chromium.launch(); const p = await b.newPage({viewport: {width: 1200, height: 2000}});
  p.on("pageerror", e => console.log("HATA", e.message));
  await p.goto("file://" + path.join(__dirname, "kit.html")); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300); await p.evaluate(() => fitAll()); await p.waitForTimeout(300);
  for (const el of await p.$$(".ab")) { const n = await el.getAttribute("data-name"); await el.screenshot({path: path.join(out, n + ".png")}); console.log(n); }
  await b.close();
})();
