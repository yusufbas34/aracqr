// Kullanıcı yorumlarını ekranın altında tek tek konuşma balonu olarak gösterir: balon süzülerek gelir, okunacak kadar
// bekler (ya da dokununca) patlayarak kaybolur, ardından sıradaki gelir. Site (index.html) ve uygulama birlikte kullanır.
// items: reviews_public kayıtları. opt: {bottom: px, max: en fazla kaç balon, delay: ms, label: {close}}. Durdurma fonksiyonu döner.
(function () {
  const CSS = `
.rvb{position:fixed;left:12px;right:12px;z-index:40;max-width:360px;margin:0 auto;pointer-events:none}
.rvb-b{position:relative;pointer-events:auto;background:#fff;color:#111418;border-radius:20px;padding:12px 40px 12px 14px;
  box-shadow:0 10px 30px rgba(10,30,80,.28),0 0 0 2px #f5a400;font:15px/1.4 "Barlow",system-ui,sans-serif;cursor:pointer;
  animation:rvb-in .5s cubic-bezier(.2,1.4,.4,1) both,rvb-bob 2.6s ease-in-out .5s infinite}
.rvb-b::after{content:"";position:absolute;left:28px;bottom:-11px;border:12px solid transparent;border-top-color:#fff;border-bottom:0;
  filter:drop-shadow(0 2px 0 #f5a400)}
.rvb-b .st{color:#f5a400;letter-spacing:1px}.rvb-b .st i{color:#d3d7de;font-style:normal}
.rvb-b p{margin:3px 0 4px;overflow-wrap:anywhere;display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
.rvb-b small{color:#5b6370;font-size:13px}
.rvb-x{position:absolute;top:6px;right:6px;width:30px;height:30px;border:0;border-radius:50%;background:#eef0f3;color:#5b6370;font-size:16px;cursor:pointer}
.rvb-b.pop{animation:rvb-pop .38s ease-in forwards}
.rvb-dot{position:absolute;left:50%;top:50%;width:10px;height:10px;border-radius:50%;background:var(--c);pointer-events:none;
  animation:rvb-burst .55s ease-out forwards}
@keyframes rvb-in{from{opacity:0;transform:translateY(30px) scale(.6)}to{opacity:1;transform:none}}
@keyframes rvb-bob{50%{transform:translateY(-5px)}}
@keyframes rvb-pop{40%{transform:scale(1.12);opacity:1}100%{transform:scale(.2);opacity:0}}
@keyframes rvb-burst{from{transform:translate(-50%,-50%) scale(1);opacity:1}to{transform:translate(calc(-50% + var(--x)),calc(-50% + var(--y))) scale(.3);opacity:0}}
@media (prefers-reduced-motion:reduce){.rvb-b,.rvb-b.pop{animation:none}.rvb-b.pop{opacity:0;transition:opacity .2s}.rvb-dot{display:none}}`;
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
  const COLORS = ["#f5a400", "#0a3a9e", "#e8453c", "#0c7a43", "#7b4dff"];

  window.reviewBubbles = function (items, opt = {}) {
    if (!items?.length) return;
    try { if (sessionStorage.getItem("aracqr-rvb-off")) return; } catch (e) {}
    if (!document.getElementById("rvb-css")) document.head.insertAdjacentHTML("beforeend", `<style id="rvb-css">${CSS}</style>`);
    document.querySelector(".rvb")?.remove();
    const box = document.createElement("div");
    box.className = "rvb";
    box.style.bottom = (opt.bottom || 16) + "px";
    box.setAttribute("aria-live", "polite");
    document.body.append(box);
    const list = items.filter(r => r.comment).sort(() => Math.random() - .5).slice(0, opt.max || 4);
    let i = 0, timer;
    const stop = () => { clearTimeout(timer); box.remove(); };
    function next() {
      if (!box.isConnected) return;
      if (i >= list.length) return stop();
      const r = list[i++];
      const b = document.createElement("div");
      b.className = "rvb-b";
      b.innerHTML = `<span class="st">${"★".repeat(r.rating)}<i>${"★".repeat(5 - r.rating)}</i></span>
        <p>“${esc(r.comment)}”</p><small><b>${esc(r.name)}</b>${r.city ? ` · ${esc(r.city)}` : ""}</small>
        <button class="rvb-x" type="button" aria-label="${esc(opt.label?.close || "Kapat")}">✕</button>`;
      box.replaceChildren(b);
      let popped = false;
      const pop = () => {
        if (popped) return;
        popped = true; clearTimeout(timer);
        for (let k = 0; k < 10; k++) {
          const d = document.createElement("span"), a = k / 10 * Math.PI * 2, dist = 70 + Math.random() * 50;
          d.className = "rvb-dot";
          d.style.cssText = `--x:${Math.cos(a) * dist}px;--y:${Math.sin(a) * dist * .6}px;--c:${COLORS[k % COLORS.length]}`;
          box.append(d);
        }
        b.classList.add("pop");
        setTimeout(() => { box.replaceChildren(); timer = setTimeout(next, 3500); }, 550);
      };
      b.onclick = ev => {
        if (ev.target.closest(".rvb-x")) { try { sessionStorage.setItem("aracqr-rvb-off", "1"); } catch (e) {} return stop(); }
        pop();
      };
      // Okuma süresi: metin uzunluğuna göre 5–10 sn
      timer = setTimeout(pop, Math.min(10000, 5000 + r.comment.length * 40));
    }
    timer = setTimeout(next, opt.delay ?? 2500);
    return stop;
  };
})();
