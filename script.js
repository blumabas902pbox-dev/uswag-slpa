/* USWAG presentation site. Shared script: page keys, present mode, SQL gallery, entity gallery, document viewer, live ERD. */
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

  /* ---------- Proximity Spotlight & Cursor Glow Tracker ---------- */
  function updatePointer(e, clientX, clientY) {
    const interactives = document.querySelectorAll('.card, .decomp-step, .btn, nav a, nav button');
    interactives.forEach(el => {
      const rect = el.getBoundingClientRect();
      const x = clientX - rect.left;
      const y = clientY - rect.top;
      el.style.setProperty('--x', `${x}px`);
      el.style.setProperty('--y', `${y}px`);
    });
  }

  document.addEventListener('mousemove', (e) => {
    updatePointer(e, e.clientX, e.clientY);
  });

  document.addEventListener('touchmove', (e) => {
    if (!e.touches.length) return;
    const touch = e.touches[0];
    updatePointer(e, touch.clientX, touch.clientY);
  }, { passive: true });

  /* ---------- Phase 3 Decomposition Dropdown & Blinds Handler ---------- */
  document.addEventListener('click', function (e) {
    var step = e.target.closest('.decomp-step');
    if (step) {
      step.classList.toggle('open');
      return;
    }

    var toggleBtn = e.target.closest('#blindToggleBtn');
    if (toggleBtn) {
      var blinds = $('#normalizationBlinds');
      var icon = $('#blindChevronIcon');
      if (blinds) {
        var isOpen = blinds.style.display === 'flex';
        blinds.style.display = isOpen ? 'none' : 'flex';
        if (icon) {
          icon.style.transform = isOpen ? 'rotate(0deg)' : 'rotate(180deg)';
        }
      }
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

  function drawErd(node, onFail) {
    if (!node) return;
    var fail = function () {
      if (onFail) { onFail(); return; }
      node.outerHTML = '<div style="padding:2em; text-align:center; color:var(--text); background:var(--card);">ERD Crow’s Foot Diagram (12 Entities, 16 Relationships)</div>';
    };
    if (!initMermaid()) { fail(); return; }
    return window.mermaid.run({ nodes: [node] }).catch(fail);
  }

  var erdNode = $('#erd');
  var erdReady = null;
  if (erdNode) {
    var erdBox = $('.erdbox');
    if (erdBox) erdBox.addEventListener('click', function () { openDoc('erd'); });
    erdReady = drawErd(erdNode);
  }

  /* ---------- ERD Entity Slider Gallery (Phase 2) ---------- */
  var ENTITIES = [
    {
      n: 'Accounts',
      def: 'erDiagram\n    Accounts {\n        int account_id PK\n        enum role\n        varchar(50) username UK\n        varchar(100) email UK\n        varchar(15) contact_number UK\n        varchar(150) address\n        varchar(255) password_hash\n        char(64) api_token_hash UK\n        datetime api_token_expires_at\n        tinyint failed_login_attempts\n        datetime locked_until\n        datetime last_login_at\n        tinyint is_active\n        datetime created_at\n    }'
    },
    {
      n: 'Capital_Ledger',
      def: 'erDiagram\n    Capital_Ledger {\n        bigint ledger_id PK\n        int seller_id FK\n        varchar(30) entry_type\n        decimal amount\n        decimal balance_after\n        int reference_id\n        varchar(150) note\n        datetime created_at\n    }'
    },
    {
      n: 'Capital_Management',
      def: 'erDiagram\n    Capital_Management {\n        int capital_id PK\n        int seller_id FK\n        decimal initial_capital\n        decimal current_balance\n        datetime last_updated\n    }'
    },
    {
      n: 'Categories',
      def: 'erDiagram\n    Categories {\n        int category_id PK\n        varchar(50) category_name UK\n    }'
    },
    {
      n: 'Contact_Messages',
      def: 'erDiagram\n    Contact_Messages {\n        int message_id PK\n        varchar(100) sender_name\n        varchar(100) sender_email\n        varchar(15) contact_number\n        varchar(50) subject\n        text message_body\n        enum status\n        char(32) public_token\n        char(64) ip_hash\n        tinyint sms_sent\n        tinyint email_sent\n        int reviewed_by_account_id FK\n        datetime reviewed_at\n        datetime created_at\n    }'
    },
    {
      n: 'Expenses',
      def: 'erDiagram\n    Expenses {\n        int expense_id PK\n        int seller_id FK\n        enum expense_category\n        decimal amount\n        datetime expense_date\n        varchar(150) description\n    }'
    },
    {
      n: 'Inventory_Transactions',
      def: 'erDiagram\n    Inventory_Transactions {\n        int transaction_id PK\n        int product_id FK\n        int sale_detail_id FK\n        enum transaction_type\n        enum verification_status\n        decimal quantity\n        datetime transaction_date\n        varchar(150) remarks\n        int verified_by_account_id FK\n        datetime verified_at\n    }'
    },
    {
      n: 'Products',
      def: 'erDiagram\n    Products {\n        int product_id PK\n        int seller_id FK\n        int category_id FK\n        varchar(100) product_name\n        varchar(20) unit_of_measure\n        decimal unit_price\n        decimal current_stock\n        decimal reorder_level\n        tinyint is_active\n    }'
    },
    {
      n: 'Receipts',
      def: 'erDiagram\n    Receipts {\n        bigint receipt_id PK\n        int sale_id FK\n        int account_id FK\n        varchar(50) receipt_number UK\n        enum receipt_type\n        longtext receipt_data\n        datetime issued_at\n        tinyint is_downloaded\n        enum sync_status\n    }'
    },
    {
      n: 'Sales',
      def: 'erDiagram\n    Sales {\n        int sale_id PK\n        int seller_id FK\n        int buyer_account_id FK\n        datetime sale_date\n        enum status\n        enum sync_status\n        char(36) client_id\n    }'
    },
    {
      n: 'Sale_Details',
      def: 'erDiagram\n    Sale_Details {\n        int sale_detail_id PK\n        int sale_id FK\n        int product_id FK\n        decimal quantity_sold\n        decimal unit_price_at_sale\n        decimal line_total\n    }'
    },
    {
      n: 'Sellers',
      def: 'erDiagram\n    Sellers {\n        int seller_id PK\n        int account_id FK\n        varchar(50) first_name\n        varchar(50) last_name\n        varchar(15) contact_number UK\n        varchar(50) barangay_zone\n        varchar(100) slp_association\n        date join_date\n        tinyint is_active\n    }'
    }
  ];

  var ei = 0;

  function initErdEntityGallery() {
    var etrk = $('#etrk');
    if (!etrk) return;

    etrk.innerHTML = ENTITIES.map(function (x, i) {
      return '<div class="cell"><div class="sc" data-ei="' + i + '" style="min-height: 380px;"><h3>' + esc(x.n) + ' Entity</h3><div class="erdbox" style="margin-top:0.5em; padding:1em; min-height: 300px; display:flex; align-items:center; justify-content:center;"><pre class="mermaid" id="e_mermaid_' + i + '">' + esc(x.def) + '</pre></div></div></div>';
    }).join('');

    // Draw one diagram at a time, after the main ERD. Mermaid names each drawing from the clock, so drawings
    // started together can share a name and get painted over each other.
    var drawn = Promise.resolve(erdReady);
    ENTITIES.forEach(function (_, i) {
      drawn = drawn.then(function () {
        var n = $('#e_mermaid_' + i);
        return n ? drawErd(n) : null;
      });
    });

    $$('#etrk .sc').forEach(function (c) {
      c.onclick = function () {
        // opens the full ERD code (all entities and relationships), not just the one card
        openText('ERD Crow’s Foot Notation (Mermaid code)', U.ERD || ENTITIES[c.dataset.ei].def);
      };
    });

    erdEntityMove(0);
  }

  function erdEntityMove(d) {
    var etrk = $('#etrk');
    if (!etrk) return;
    var n = ENTITIES.length;
    ei = (ei + d + n) % n;
    etrk.style.transform = 'translateX(-' + ei * 100 + '%)';
    $$('#etrk .cell').forEach(function (c, i) { c.classList.toggle('cur', i === ei); });
    var ecnt = $('#ecnt');
    if (ecnt) ecnt.textContent = 'Entity ' + (ei + 1) + ' / ' + n;
  }

  if ($('#etrk')) {
    $('#ep').onclick = function () { erdEntityMove(-1); };
    $('#en').onclick = function () { erdEntityMove(1); };
    
    var eview = $('#etrk').parentElement;
    if (eview) {
      var ex = null;
      eview.addEventListener('touchstart', function (e) { ex = e.touches[0].clientX; e.stopPropagation(); }, { passive: true });
      eview.addEventListener('touchend', function (e) {
        e.stopPropagation();
        if (ex === null) return;
        var dx = e.changedTouches[0].clientX - ex;
        if (Math.abs(dx) > 40) erdEntityMove(dx < 0 ? 1 : -1);
        ex = null;
      });

      eview.setAttribute('tabindex', '0');
      eview.addEventListener('keydown', function (e) {
        if (e.key === 'ArrowLeft') {
          e.preventDefault();
          erdEntityMove(-1);
        } else if (e.key === 'ArrowRight') {
          e.preventDefault();
          erdEntityMove(1);
        }
      });
    }

    initErdEntityGallery();
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
  pbar.innerHTML = '<button id="pprev" aria-label="Previous slide">&#8249;</button><button id="pcount" disabled>1</button><button id="pnext" aria-label="Next slide">&#8250;</button><button id="pexit">Exit</button>';
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
      return '<div class="cell"><div class="sc" data-i="' + i + '" style="min-height: 380px;"><h3>' + esc(x.n) + '</h3><pre style="max-height: 280px; overflow: hidden;">' + esc(x.s.split('\n').slice(0, 20).join('\n')) + '</pre></div></div>';
    }).join('');
    $$('.sc', trk).forEach(function (c) { c.onclick = function () { openText(list[c.dataset.i].n, list[c.dataset.i].s); }; });
    galMove(0);
  }

  function galMove(d) {
    var list = GAL[gk];
    if (!list) return;
    var n = list.length;
    gi = (gi + d + n) % n;
    var trk = $('#trk');
    if (trk) trk.style.transform = 'translateX(-' + gi * 100 + '%)';
    $$('.cell', trk).forEach(function (c, i) { c.classList.toggle('cur', i === gi); });
    var cnt = $('#cnt');
    if (cnt) cnt.textContent = gk + ' ' + (gi + 1) + ' / ' + n;
  }

  if ($('#trk')) {
    $('#gp').onclick = function () { galMove(-1); };
    $('#gn').onclick = function () { galMove(1); };
    var gx = null;
    var gv = $('#trk').parentElement;
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
    freeBlob();
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

  /* ----- file lookup: works from any folder layout, on http(s) and on file:// ----- */
  var blobUrl = null;
  var MIME = {
    pdf: 'application/pdf', svg: 'image/svg+xml', png: 'image/png',
    sql: 'text/plain;charset=utf-8', mmd: 'text/plain;charset=utf-8', md: 'text/plain;charset=utf-8',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  };

  function extOf(name) {
    var m = /\.([a-z0-9]+)$/i.exec(name || '');
    return m ? m[1].toLowerCase() : '';
  }

  function freeBlob() {
    if (blobUrl) { URL.revokeObjectURL(blobUrl); blobUrl = null; }
  }

  // The listed path first, then the same file with the folder removed, at the site root and next to the page.
  function candidates(d) {
    var out = [];
    [d.file].concat(d.alt || []).forEach(function (f) {
      if (!f) return;
      var base = f.split('/').pop();
      var bare = f.replace(/^(\.\.\/|\.\/)+/, '');
      [f, bare, './' + base, base, '../' + base, '/' + bare].forEach(function (p) {
        if (out.indexOf(p) < 0) out.push(p);
      });
    });
    return out;
  }

  // Resolves to a Blob, or null when the file cannot be fetched (not found, or the site runs from file://).
  function fetchFile(d) {
    var list = candidates(d), i = 0;
    if (!list.length || !window.fetch || location.protocol === 'file:') return Promise.resolve(null);
    function next() {
      if (i >= list.length) return Promise.resolve(null);
      return fetch(list[i++]).then(function (r) {
        if (!r.ok) return next();
        // some hosts answer a missing file with index.html and status 200
        if (/text\/html/i.test(r.headers.get('content-type') || '') && extOf(d.file) !== 'html') return next();
        return r.blob();
      }).catch(next);
    }
    return next();
  }

  function saveBlob(name, blob) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
  }

  function typed(blob, name) {
    return new Blob([blob], { type: MIME[extOf(name)] || blob.type });
  }

  function missing(body, name) {
    body.innerHTML = '<div class="paper"><h1>File not found</h1><p><b>' + esc(name) + '</b> is not on this site. Check that the file sits in the folder listed in script.js.</p></div>';
  }

  window.openText = function (title, text) {
    var ext = /^\s*erDiagram/.test(text) ? '.mmd' : '.sql';
    viewing = { name: title.replace(/\W+/g, '_').replace(/^_+|_+$/g, '') + ext, text: text };
    var mb = $('#mb');
    if (mb) mb.innerHTML = numbered(text);
    openModal(title);
  };

  function outline(id) {
    var list = (U.OUTLINES || {})[id] || U.SLIDES || [];
    return '<div class="paper"><h1>USWAG Project Overview & Document Outline</h1>' + list.map(function (s, i) {
      return '<h3>' + (i + 1) + '. ' + esc(s.t) + '</h3><ul>' + s.b.map(function (b) { return '<li>' + esc(b) + '</li>'; }).join('') + '</ul>';
    }).join('') + '<p style="margin-top:1em;"><i>Preview only. Use Download for the full file.</i></p></div>';
  }

  // Document list. The paths match the folders used by the site; anything in U.DOCS overrides it.
  var FALLBACK_DOCS = {
    'erd': { title: 'ERD (Crow’s Foot)', file: '../diagrams/uswag_erd_crowsfoot.svg', kind: 'erd' },
    'mmd': { title: 'ERD Mermaid Code', file: '../diagrams/uswag_erd.mmd', kind: 'text', text: U.ERD },
    'rules': { title: 'Business Rules', file: '../documents/USWAG_Business_Rules.pdf', kind: 'pdf' },
    'norm': { title: 'Normalization Proofs', file: '../documents/USWAG_Normalization_Proofs.pdf', kind: 'pdf' },
    'perf': { title: 'Performance Report', file: '../documents/USWAG_Performance_Report.pdf', kind: 'pdf' },
    'sql': { title: 'uswag_db.sql', file: '../database/uswag_db.sql', kind: 'text', text: U.SQL },
    'docx': { title: 'Proposal (Word)', file: '../presentation/USWAG_Project_Proposal.docx', kind: 'office' },
    'pdf': { title: 'Proposal (PDF)', file: '../presentation/USWAG_Project_Proposal.pdf', kind: 'pdf' },
    'pptx': { title: 'Slides (Plain)', file: '../presentation/USWAG_Slides_Plain.pptx', kind: 'office' },
    'interface': { title: 'Slides (Interface)', file: '../presentation/USWAG_Slides_Interface.pptx', kind: 'office' },
    'readme': { title: 'READ.md', file: '../READ.md', alt: ['../README.md'], kind: 'text' }
  };

  // If a button carries a data-doc value that is not listed above, match it by its card title.
  var TITLE_IDS = [
    ['mermaid code', 'mmd'], ['crow', 'erd'], ['business rules', 'rules'], ['normalization', 'norm'],
    ['performance', 'perf'], ['uswag_db', 'sql'], ['proposal (word)', 'docx'], ['proposal (pdf)', 'pdf'],
    ['slides (plain)', 'pptx'], ['slides (interface)', 'interface'], ['read.md', 'readme'], ['readme', 'readme']
  ];

  function docIdFor(el) {
    var id = el.dataset.doc;
    var t = (el.textContent || '').toLowerCase();
    var hits = [];
    TITLE_IDS.forEach(function (p) { if (t.indexOf(p[0]) > -1 && hits.indexOf(p[1]) < 0) hits.push(p[1]); });
    // the card title is what the person sees, so it decides when it names exactly one document
    if (hits.length === 1) return hits[0];
    return id;
  }

  function showErd(body, v) {
    body.innerHTML = '<div class="erdbox" style="padding:1.5em;"><pre class="mermaid" id="erdbig">' + esc(U.ERD || '') + '</pre></div>';
    // Last resort when Mermaid cannot load: show the saved SVG file instead.
    var asImage = function () { if (viewing === v) showFile(body, v, 'img'); };
    if (!U.ERD) { asImage(); return; }
    drawErd($('#erdbig'), asImage);
  }

  function showFile(body, v, tag) {
    fetchFile(v).then(function (b) {
      if (viewing !== v) return; // the window was closed or another file opened meanwhile
      var src;
      if (b) {
        v.blob = typed(b, v.name);
        freeBlob();
        blobUrl = URL.createObjectURL(v.blob);
        src = blobUrl;
      } else if (location.protocol === 'file:') {
        src = v.file;
      } else {
        missing(body, v.name);
        return;
      }
      body.innerHTML = tag === 'img'
        ? '<div class="erdbox" style="padding:1.5em;"><img src="' + src + '" alt="' + esc(v.title) + '" style="max-width:100%;height:auto;"></div>'
        : '<iframe src="' + src + '" title="' + esc(v.title) + '"></iframe>';
    });
  }

  window.openDoc = function (id) {
    var d = (U.DOCS || {})[id] || FALLBACK_DOCS[id];
    if (!d) { toast('Document not available'); return; }
    var body = $('#mb');
    freeBlob();

    var v = viewing = { name: d.file ? d.file.split('/').pop() : id, title: d.title || id, file: d.file || '', alt: d.alt, text: d.text || '' };
    openModal(v.title);
    if (!body) return;
    body.innerHTML = '';

    if (d.kind === 'erd' || id === 'erd') {
      // the rendered diagram is the fallback download if the .svg file is missing
      v.text = function () {
        var svg = $('#mb svg');
        return svg ? '<?xml version="1.0" encoding="UTF-8"?>\n' + new XMLSerializer().serializeToString(svg) : '';
      };
      showErd(body, v);
    } else if (d.kind === 'office') {
      body.innerHTML = outline(id);
    } else if (d.kind === 'pdf') {
      showFile(body, v, 'iframe');
    } else if (v.text) {
      body.innerHTML = numbered(v.text);
    } else if (d.file) {
      // text file that is not embedded: read it, then number the lines
      fetchFile(v).then(function (b) {
        if (viewing !== v) return;
        if (!b) { if (location.protocol === 'file:') showFile(body, v, 'iframe'); else missing(body, v.name); return; }
        v.blob = typed(b, v.name);
        b.text().then(function (t) { if (viewing === v) body.innerHTML = numbered(t); });
      });
    } else {
      body.innerHTML = outline(id);
    }
  };

  var mx = $('#mx');
  if (mx) mx.onclick = closeModal;

  var mdl = $('#mdl');
  if (mdl) mdl.onclick = function () {
    if (!viewing) return;
    var v = viewing;
    var started = function () { toast('Download started for ' + v.name); };
    if (v.blob) { saveBlob(v.name, v.blob); started(); return; }
    fetchFile(v).then(function (b) {
      var text = typeof v.text === 'function' ? v.text() : v.text;
      if (b) { saveBlob(v.name, typed(b, v.name)); started(); }
      else if (text) { saveBlob(v.name, new Blob([text], { type: MIME[extOf(v.name)] || 'text/plain;charset=utf-8' })); started(); }
      else if (v.file && location.protocol === 'file:') {
        var a = document.createElement('a');
        a.href = v.file;
        a.download = v.name;
        document.body.appendChild(a);
        a.click();
        a.remove();
        started();
      } else {
        toast('File not found: ' + v.name);
      }
    });
  };

  var mpr = $('#mpr');
  if (mpr) mpr.onclick = function () {
    var f = $('#mb iframe');
    if (f) {
      try {
        f.contentWindow.print();
        return;
      } catch (e) {
        var printWin = window.open(blobUrl || (viewing && viewing.file) || '', '_blank');
        if (printWin) {
          printWin.print();
          return;
        }
      }
    }
    
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

  $$('[data-doc]').forEach(function (b) { b.onclick = function () { openDoc(docIdFor(b)); }; });
  $$('[data-print]').forEach(function (b) { b.onclick = function () { window.print(); }; });
})();