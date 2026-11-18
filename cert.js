/* Ceramic coating certificate renderer — shared by the website (verify page) and the admin app (designer). */
(function () {
  const DEF = {
    title: 'Certificate of Protection', subtitle: 'Professional Ceramic Coating', theme: 'dark', accent: '#2f8cff', gold: '#d4af37',
    product: 'Ceramic coating', warranty: 2, layers: 1,
    intro: 'This certifies that the vehicle below has been professionally decontaminated, machine polished and protected with',
    aftercare: 'Avoid washing for 7 days after application\nUse a pH-neutral shampoo and the two-bucket method\nNo automatic car washes or harsh brushes\nBook a maintenance valet every 4–8 weeks\nAnnual inspection keeps your warranty valid',
    sign: '', role: 'Authorised applicator', footer: '', qr: true,
  };
  let qrP = null;
  function loadQR() {
    if (window.qrLocal) return Promise.resolve();
    if (!qrP) qrP = new Promise((res) => { const s = document.createElement('script'); s.src = '/qr.js?v=1'; s.onload = res; s.onerror = res; document.head.appendChild(s); });
    return qrP;
  }
  function img(src) { return new Promise((res) => { if (!src) return res(null); const i = new Image(); i.crossOrigin = 'anonymous'; i.onload = () => res(i); i.onerror = () => res(null); i.src = src; }); }
  function wrap(g, text, x, y, maxW, lh, maxLines) {
    const words = String(text || '').split(/\s+/); let line = '', n = 0;
    for (let i = 0; i < words.length; i++) {
      const t = line ? line + ' ' + words[i] : words[i];
      if (g.measureText(t).width > maxW && line) { g.fillText(line, x, y); y += lh; line = words[i]; if (++n >= (maxLines || 99) - 1) { line = words.slice(i).join(' '); while (g.measureText(line + '…').width > maxW && line.length) line = line.slice(0, -1); if (i < words.length - 1) line += '…'; break; } }
      else line = t;
    }
    if (line) g.fillText(line, x, y);
    return y + lh;
  }
  const fmt = (d) => d ? new Date(String(d).slice(0, 10) + 'T12:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '—';
  function addYears(d, y) { const x = new Date(String(d).slice(0, 10) + 'T12:00:00'); x.setMonth(x.getMonth() + Math.round(+y * 12)); return x.toISOString().slice(0, 10); }

  async function certCanvas(c, design, o) {
    o = o || {}; const D = Object.assign({}, DEF, design || {});
    const W = 2000, H = 1414, cv = document.createElement('canvas'); cv.width = W; cv.height = H; const g = cv.getContext('2d');
    const dark = D.theme !== 'light', ink = dark ? '#f4f6fb' : '#101521', mu = dark ? 'rgba(220,228,245,.62)' : 'rgba(16,21,33,.6)', gold = D.gold || '#d4af37', ac = D.accent || '#2f8cff';
    // background
    let bg = g.createRadialGradient(W * .7, H * .25, 50, W * .5, H * .5, W * .85);
    if (dark) { bg.addColorStop(0, '#132037'); bg.addColorStop(.55, '#0a1020'); bg.addColorStop(1, '#04060b'); } else { bg.addColorStop(0, '#ffffff'); bg.addColorStop(1, '#efe9dc'); }
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    // diagonal sheen lines
    g.save(); g.globalAlpha = dark ? .05 : .06; g.strokeStyle = dark ? '#fff' : gold; g.lineWidth = 2;
    for (let i = -H; i < W; i += 46) { g.beginPath(); g.moveTo(i, H); g.lineTo(i + H, 0); g.stroke(); } g.restore();
    // frame
    g.strokeStyle = gold; g.lineWidth = 6; g.strokeRect(46, 46, W - 92, H - 92);
    g.lineWidth = 2; g.globalAlpha = .7; g.strokeRect(70, 70, W - 140, H - 140); g.globalAlpha = 1;
    [[70, 70, 1, 1], [W - 70, 70, -1, 1], [70, H - 70, 1, -1], [W - 70, H - 70, -1, -1]].forEach(([x, y, sx, sy]) => { g.beginPath(); g.moveTo(x, y + sy * 90); g.lineTo(x, y); g.lineTo(x + sx * 90, y); g.lineWidth = 10; g.strokeStyle = gold; g.stroke(); g.beginPath(); g.arc(x + sx * 22, y + sy * 22, 7, 0, 7); g.fillStyle = gold; g.fill(); });
    // header: logo + name
    const logo = await img(o.logo); let hx = 130;
    if (logo) { const h = 120, w = Math.min(320, logo.width * h / logo.height); g.drawImage(logo, 130, 118, w, h); hx = 130 + w + 28; }
    g.fillStyle = ink; g.font = '800 46px Inter, Helvetica, Arial, sans-serif'; g.textBaseline = 'middle'; if (!logo || o.showName !== false) g.fillText(o.business || '', hx, 160);
    g.fillStyle = mu; g.font = '500 26px Inter, Helvetica, Arial, sans-serif'; if (o.website) g.fillText(o.website, hx, 205);
    g.textAlign = 'right'; g.fillStyle = mu; g.font = '600 24px Inter, Helvetica, Arial, sans-serif'; g.fillText('CERTIFICATE No.', W - 130, 150);
    g.fillStyle = ink; g.font = '800 40px "Courier New", monospace'; g.fillText(c.code || 'XX-CERT-000000', W - 130, 195); g.textAlign = 'left';
    // title
    g.textAlign = 'center'; g.fillStyle = gold; g.font = '600 30px Inter, Helvetica, Arial, sans-serif';
    const sub = String(D.subtitle || '').toUpperCase().split('').join(String.fromCharCode(8202)); g.fillText(sub, W / 2, 330);
    g.fillStyle = ink; g.font = '700 98px Georgia, "Times New Roman", serif'; g.fillText(D.title || '', W / 2, 425);
    g.strokeStyle = gold; g.lineWidth = 3; g.beginPath(); g.moveTo(W / 2 - 260, 490); g.lineTo(W / 2 - 30, 490); g.moveTo(W / 2 + 30, 490); g.lineTo(W / 2 + 260, 490); g.stroke();
    g.save(); g.translate(W / 2, 490); g.rotate(Math.PI / 4); g.fillStyle = gold; g.fillRect(-10, -10, 20, 20); g.restore();
    g.fillStyle = mu; g.font = 'italic 30px Georgia, serif'; wrap(g, D.intro, W / 2, 548, 1300, 40, 2);
    g.fillStyle = ac; g.font = '800 64px Inter, Helvetica, Arial, sans-serif'; g.fillText(c.product || D.product, W / 2, 655);
    g.textAlign = 'left';
    // UK number plate, centred under the product
    let gy = 760;
    if (c.reg) { const pw = 380, ph = 86, px = W / 2 - pw / 2, py = 700; g.fillStyle = '#f7d117'; rr(g, px, py, pw, ph, 12); g.fill(); g.fillStyle = '#1a47b8'; rr(g, px, py, 54, ph, 12); g.fill(); g.fillRect(px + 38, py, 16, ph);
      g.fillStyle = '#fff'; g.font = '700 20px Arial'; g.textAlign = 'center'; g.fillText('UK', px + 27, py + 64); g.fillStyle = '#111'; g.font = '700 60px "Arial Narrow", Arial, sans-serif'; g.fillText(String(c.reg).toUpperCase(), px + 54 + (pw - 54) / 2, py + ph / 2 + 2); g.textAlign = 'left'; gy = 840; }
    // details grid (4 x 2)
    const exp = c.expires_on || (c.applied_on ? addYears(c.applied_on, c.warranty_years ?? D.warranty) : '');
    const wy = +(c.warranty_years ?? D.warranty);
    const rows = [['Owner', c.customer_name || '—'], ['Vehicle', c.vehicle || '—'], ['Colour', c.colour || '—'], ['Layers applied', String(c.layers || D.layers)], ['Date applied', fmt(c.applied_on)], ['Warranty', `${wy} year${wy === 1 ? '' : 's'}`], ['Protected until', fmt(exp)], ['Coverage', c.coverage || 'Full exterior']];
    const gx = 150, cw = 430, rh = 104;
    rows.forEach((r, i) => { const x = gx + (i % 4) * cw, y = gy + Math.floor(i / 4) * rh;
      g.fillStyle = mu; g.font = '600 21px Inter, Helvetica, Arial, sans-serif'; g.fillText(r[0].toUpperCase(), x, y);
      g.fillStyle = ink; g.font = '700 33px Inter, Helvetica, Arial, sans-serif'; let t = r[1]; while (g.measureText(t).width > cw - 40 && t.length > 3) t = t.slice(0, -2) + '…'; g.fillText(t, x, y + 44);
      g.strokeStyle = dark ? 'rgba(255,255,255,.12)' : 'rgba(0,0,0,.12)'; g.lineWidth = 2; g.beginPath(); g.moveTo(x, y + 72); g.lineTo(x + cw - 40, y + 72); g.stroke(); });
    // aftercare box
    const ax = gx, ay = gy + 2 * rh + 20, aw = 1000, ah = H - 120 - ay;
    if (ah > 110) { g.fillStyle = dark ? 'rgba(255,255,255,.04)' : 'rgba(0,0,0,.035)'; rr(g, ax, ay, aw, ah, 18); g.fill(); g.strokeStyle = dark ? 'rgba(255,255,255,.1)' : 'rgba(0,0,0,.1)'; g.lineWidth = 2; g.stroke();
      g.fillStyle = gold; g.font = '700 21px Inter, Helvetica, Arial, sans-serif'; g.fillText('AFTERCARE', ax + 28, ay + 38);
      g.font = '500 24px Inter, Helvetica, Arial, sans-serif'; const L = String(D.aftercare || '').split('\n').filter(Boolean); const lh = Math.min(34, (ah - 70) / Math.max(1, L.length));
      L.forEach((t, i) => { const y = ay + 76 + i * lh; if (y > ay + ah - 10) return; g.fillStyle = ac; g.fillText('•', ax + 28, y); g.fillStyle = ink; let s2 = t; while (g.measureText(s2).width > aw - 80 && s2.length > 3) s2 = s2.slice(0, -2) + '…'; g.fillText(s2, ax + 50, y); }); }
    // QR + signature
    const qs = 200, qx = W - 130 - qs, qy = H - 160 - qs - 14;
    if (D.qr !== false && o.verifyUrl) { await loadQR(); if (window.qrLocal) { const q = window.qrLocal(o.verifyUrl); const n = q.getModuleCount(), s = qs / (n + 2);
      g.fillStyle = '#fff'; rr(g, qx - 10, qy - 10, qs + 20, qs + 20, 14); g.fill(); g.fillStyle = '#0b0f19'; for (let r = 0; r < n; r++) for (let k = 0; k < n; k++) if (q.isDark(r, k)) g.fillRect(qx + (k + 1) * s, qy + (r + 1) * s, Math.ceil(s), Math.ceil(s));
      g.fillStyle = mu; g.font = '600 19px Inter, Helvetica, Arial, sans-serif'; g.textAlign = 'center'; g.fillText('SCAN TO VERIFY', qx + qs / 2, qy + qs + 40); g.textAlign = 'left'; } }
    const sx = 1200, sy = H - 150;
    if (D.sign) { g.fillStyle = ink; g.font = 'italic 50px "Brush Script MT", "Segoe Script", cursive'; g.fillText(D.sign, sx, sy - 16); }
    g.strokeStyle = gold; g.lineWidth = 2; g.beginPath(); g.moveTo(sx, sy); g.lineTo(sx + 380, sy); g.stroke();
    g.fillStyle = mu; g.font = '600 20px Inter, Helvetica, Arial, sans-serif'; g.fillText((D.role || '').toUpperCase(), sx, sy + 30);
    // seal
    const ex = sx + 190, ey = sy - 160; g.save(); g.translate(ex, ey); g.scale(.82, .82);
    for (let i = 0; i < 24; i++) { g.rotate(Math.PI / 12); g.fillStyle = gold; g.beginPath(); g.moveTo(0, -92); g.lineTo(10, -78); g.lineTo(-10, -78); g.fill(); }
    g.beginPath(); g.arc(0, 0, 80, 0, 7); const sg = g.createLinearGradient(-80, -80, 80, 80); sg.addColorStop(0, '#f5d77a'); sg.addColorStop(.5, gold); sg.addColorStop(1, '#8a6a14'); g.fillStyle = sg; g.fill();
    g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 3; g.beginPath(); g.arc(0, 0, 64, 0, 7); g.stroke();
    g.fillStyle = '#2a1e00'; g.textAlign = 'center'; g.font = '800 22px Inter, Arial, sans-serif'; g.fillText('GENUINE', 0, -14); g.font = '800 34px Inter, Arial, sans-serif'; g.fillText(`${+(c.warranty_years ?? D.warranty)} YR`, 0, 22); g.font = '700 15px Inter, Arial, sans-serif'; g.fillText('PROTECTION', 0, 48); g.restore();
    // footer
    g.textAlign = 'center'; g.fillStyle = mu; g.font = '500 22px Inter, Helvetica, Arial, sans-serif';
    g.fillText([D.footer, o.phone, o.email].filter(Boolean).join('   ·   '), W / 2, H - 92); g.textAlign = 'left';
    if (c.void) { g.save(); g.translate(W / 2, H / 2); g.rotate(-.35); g.fillStyle = 'rgba(220,38,38,.75)'; g.font = '900 260px Inter, Arial, sans-serif'; g.textAlign = 'center'; g.fillText('VOID', 0, 90); g.restore(); }
    return cv;
  }
  function rr(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
  window.CERT_DEF = DEF; window.certCanvas = certCanvas; window.certAddYears = addYears; window.certFmt = fmt;
})();
