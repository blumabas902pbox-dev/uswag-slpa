/* USWAG presentation site. Shared script: page keys, present mode, SQL gallery, document viewer, live ERD. */
(function () {
  'use strict';

  var U = window.USWAG || {};
  var GAL = U.GAL || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var esc = function (s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; });
  };

  function toast(msg) {
    var t = $('#toast');
    if (!t) return;
    t.textContent = msg;
    t.style.display = 'block';
    clearTimeout(toast.id);
    toast.id = setTimeout(function () { t.style.display = 'none'; }, 3000);
  }

  /* ---------- Phase 3 Decomposition Dropdown Handler ---------- */
  document.addEventListener('click', function (e) {
    var step = e.target.closest('.decomp-step');
    if (step) {
      step.classList.toggle('open');
    }
  });

  /* ---------- live ERD (Mermaid, Crow's Foot) ---------- */
  var mermaidReady = false;

  function initMermaid() {
    if (!window.mermaid || mermaidReady) return mermaidReady;
    window.mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict', er: { useMaxWidth: true } });
    mermaidReady = true;
    return true;
  }

  function drawErd(node) {
    if (!node) return;
    if (!initMermaid()) {
      node.outerHTML = '<div style="padding:2em; text-align:center; color:var(--text); background:var(--card);">ERD Crow’s Foot Diagram (12 Entities, 16 Relationships)</div>';
      return;
    }
    return window.mermaid.run({ nodes: [node] }).catch(function () {
      node.outerHTML = '<div style="padding:2em; text-align:center; color:var(--text); background:var(--card);">ERD Crow’s Foot Diagram (12 Entities, 16 Relationships)</div>';
    });
  }

  var erdNode = $('#erd');
  var erdReady = null;
  if (erdNode) {
    var erdBox = $('.erdbox');
    if (erdBox) erdBox.addEventListener('click', function () { openDoc('erd'); });
    erdReady = drawErd(erdNode);
  }

  /* ---------- slides and present mode ---------- */
  var slides = $$('.slide');
  var cur = 0;

  slides.forEach(function (s, i) {
    s.dataset.no = (i + 1) + ' / ' + slides.length;
    if (i === 0) s.classList.add('first');
  });

  function showSlide(i) {
    cur = Math.max(0, Math.min(slides.length - 1, i));
    slides.forEach(function (s, k) { s.classList.toggle('cur', k === cur); });
    var c = $('#pcount');
    if (c) c.textContent = (cur + 1) + ' / ' + slides.length;
  }

  function setPresent(on, last, auto) {
    document.body.classList.toggle('present', on);
    if (on) { showSlide(last ? slides.length - 1 : cur); } else { slides.forEach(function (s) { s.classList.remove('cur'); }); }
    var b = $('#presentBtn');
    if (b) b.textContent = on ? '\u25A0 Exit' : '\u25B6 Present';
    if (on && !auto && document.documentElement.requestFullscreen && !document.fullscreenElement) {
      document.documentElement.requestFullscreen().catch(function () {});
    }
    if (!on && document.fullscreenElement) document.exitFullscreen().catch(function () {});
  }

  function go(dir) {
    var b = document.body;
    var next = cur + dir;
    if (next >= 0 && next < slides.length) { showSlide(next); return; }
    if (dir > 0 && b.dataset.next) location.href = b.dataset.next + '#present';
    if (dir < 0 && b.dataset.prev) location.href = b.dataset.prev + '#present-last';
  }

  var pbar = document.createElement('div');
  pbar.className = 'pbar';
  pbar.innerHTML = '<button id="pprev" aria-label="Previous slide">\u2039</button><button id="pcount" disabled>1</button><button id="pnext" aria-label="Next slide">\u203A</button><button id="pexit">Exit</button>';
  document.body.appendChild(pbar);
  $('#pprev').onclick = function () { go(-1); };
  $('#pnext').onclick = function () { go(1); };
  $('#pexit').onclick = function () { setPresent(false); };
  if ($('#presentBtn')) $('#presentBtn').onclick = function () { setPresent(!document.body.classList.contains('present')); };

  if (location.hash.indexOf('#present') === 0) {
    Promise.resolve(erdReady).then(function () { setPresent(true, location.hash === '#present-last', true); });
  }

  document.addEventListener('keydown', function (e) {
    var modal = $('#modal');
    if (modal && modal.classList.contains('on')) { if (e.key === 'Escape') closeModal(); return; }
    var present = document.body.classList.contains('present');
    var b = document.body;
    if (e.key === 'Escape' && present) { setPresent(false); return; }
    if (e.key === 'p' || e.key === 'P') { setPresent(!present); return; }
    if (present) {
      if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') { e.preventDefault(); go(1); }
      if (e.key === 'ArrowLeft' || e.key === 'PageUp') go(-1);
      return;
    }
    if (e.key === 'ArrowRight' && b.dataset.next) location.href = b.dataset.next;
    if (e.key === 'ArrowLeft' && b.dataset.prev) location.href = b.dataset.prev;
  });

  var sx = null;
  document.addEventListener('touchstart', function (e) { sx = e.touches[0].clientX; }, { passive: true });
  document.addEventListener('touchend', function (e) {
    if (sx === null || !document.body.classList.contains('present')) { sx = null; return; }
    var dx = e.changedTouches[0].clientX - sx;
    if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
    sx = null;
  });

  /* ---------- SQL gallery: tables, triggers, procedures, views, queries ---------- */
  var gk = Object.keys(GAL)[0];
  var gi = 0;

  function galTabs() {
    var tabsEl = $('#tabs');
    if (!tabsEl) return;
    tabsEl.innerHTML = Object.keys(GAL).map(function (k) {
      return '<button class="pill' + (k === gk ? ' on' : '') + '" data-k="' + k + '">' + k + ' (' + GAL[k].length + ')</button>';
    }).join('');
    $$('.pill').forEach(function (p) { p.onclick = function () { gk = p.dataset.k; gi = 0; galTabs(); galDraw(); }; });
  }

  function galDraw() {
    var list = GAL[gk];
    if (!list) return;
    var trk = $('#trk');
    if (!trk) return;
    trk.innerHTML = list.map(function (x, i) {
      return '<div class="cell"><div class="sc" data-i="' + i + '"><h3>' + esc(x.n) + '</h3><pre>' + esc(x.s.split('\n').slice(0, 12).join('\n')) + '</pre></div></div>';
    }).join('');
    $$('.sc').forEach(function (c) { c.onclick = function () { openText(list[c.dataset.i].n, list[c.dataset.i].s); }; });
    galMove(0);
  }

  function galMove(d) {
    var list = GAL[gk];
    if (!list) return;
    var n = list.length;
    gi = (gi + d + n) % n;
    var trk = $('#trk');
    if (trk) trk.style.transform = 'translateX(-' + gi * 100 + '%)';
    $$('.cell').forEach(function (c, i) { c.classList.toggle('cur', i === gi); });
    var cnt = $('#cnt');
    if (cnt) cnt.textContent = gk + ' ' + (gi + 1) + ' / ' + n;
  }

  if ($('#trk')) {
    $('#gp').onclick = function () { galMove(-1); };
    $('#gn').onclick = function () { galMove(1); };
    var gx = null;
    var gv = $('.view');
    if (gv) {
      gv.addEventListener('touchstart', function (e) { gx = e.touches[0].clientX; e.stopPropagation(); }, { passive: true });
      gv.addEventListener('touchend', function (e) {
        e.stopPropagation();
        if (gx === null) return;
        var dx = e.changedTouches[0].clientX - gx;
        if (Math.abs(dx) > 40) galMove(dx < 0 ? 1 : -1);
        gx = null;
      });
    }
    galTabs();
    galDraw();
  }

  /* ---------- document viewer, download and print ---------- */
  var viewing = null;

  function closeModal() {
    var modal = $('#modal');
    if (modal) modal.classList.remove('on');
    var mb = $('#mb');
    if (mb) mb.innerHTML = '';
    viewing = null;
  }

  function openModal(title) {
    var mt = $('#mt');
    if (mt) mt.textContent = title;
    var modal = $('#modal');
    if (modal) modal.classList.add('on');
  }

  function numbered(text) {
    return '<div class="sqlv">' + text.split('\n').map(function (l, i) { return '<i>' + (i + 1) + '</i>' + esc(l); }).join('\n') + '</div>';
  }

  function saveText(name, text) {
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }));
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  window.openText = function (title, text) {
    viewing = { name: title.replace(/\W+/g, '_') + '.sql', text: text };
    var mb = $('#mb');
    if (mb) mb.innerHTML = numbered(text);
    openModal(title);
  };

  function outline() {
    return '<div class="paper"><h1>USWAG Project Overview & Document Outline</h1>' + (U.SLIDES || []).map(function (s, i) {
      return '<h3>' + (i + 1) + '. ' + esc(s.t) + '</h3><ul>' + s.b.map(function (b) { return '<li>' + esc(b) + '</li>'; }).join('') + '</ul>';
    }).join('') + '<p style="margin-top:1em;"><i>Available offline in real-time.</i></p></div>';
  }

  window.openDoc = function (id) {
    var d = (U.DOCS || {})[id];
    if (!d && id !== 'erd') return;
    
    if (id === 'erd') {
      viewing = { name: 'uswag_erd_crowsfoot.svg', href: '../diagrams/uswag_erd_crowsfoot.svg', text: U.ERD || '' };
      var body = $('#mb');
      openModal('ERD (Crow’s Foot)');
      body.innerHTML = '<div class="erdbox" style="padding:1.5em;"><pre class="mermaid" id="erdbig">' + esc(U.ERD || '') + '</pre></div>';
      drawErd($('#erdbig'));
      return;
    }

    viewing = { name: d.file.split('/').pop(), href: d.file, text: d.text };
    var body = $('#mb');
    openModal(d.title);
    if (d.kind === 'pdf') {
      body.innerHTML = '<iframe src="' + d.file + '" title="' + esc(d.title) + '"></iframe>';
    } else if (d.kind === 'office') {
      body.innerHTML = outline();
    } else {
      body.innerHTML = numbered(d.text);
    }
  };

  var mx = $('#mx');
  if (mx) mx.onclick = closeModal;

  var mdl = $('#mdl');
  if (mdl) mdl.onclick = function () {
    if (!viewing) return;
    if (viewing.href) {
      var a = document.createElement('a');
      a.href = viewing.href;
      a.download = viewing.name;
      document.body.appendChild(a);
      a.click();
      a.remove();
    } else {
      saveText(viewing.name, viewing.text);
    }
    toast('Download started for ' + viewing.name);
  };

  var mpr = $('#mpr');
  if (mpr) mpr.onclick = function () {
    var f = $('#mb iframe');
    if (f) {
      try {
        f.contentWindow.print();
        return;
      } catch (e) {
        // Fallback for cross-origin or offline PDF frames: Open direct print window / print preview
        var printWin = window.open(viewing && viewing.href ? viewing.href : '', '_blank');
        if (printWin) {
          printWin.print();
          return;
        }
      }
    }
    
    // For text, SQL scripts, and document outlines in the modal:
    var modalBodyHtml = $('#mb').innerHTML;
    var printWindow = window.open('', '_blank');
    if (printWindow) {
      printWindow.document.write('<!DOCTYPE html><html><head><title>USWAG Print Preview</title><style>body{font-family:Segoe UI,sans-serif;padding:2em;color:#000;background:#fff;}.sqlv{font:12px/1.5 Consolas,monospace;white-space:pre;background:#f1f5f3;padding:1em;border-radius:4px;}.sqlv i{display:inline-block;width:3em;opacity:0.5;font-style:normal;}</style></head><body>' + modalBodyHtml + '</body></html>');
      printWindow.document.close();
      printWindow.focus();
      setTimeout(function () {
        printWindow.print();
        printWindow.close();
      }, 250);
    } else {
      window.print();
    }
  };

  window.addEventListener('afterprint', function () { document.body.classList.remove('print-modal'); });

  $$('[data-doc]').forEach(function (b) { b.onclick = function () { openDoc(b.dataset.doc); }; });
  $$('[data-print]').forEach(function (b) { b.onclick = function () { window.print(); }; });
})();