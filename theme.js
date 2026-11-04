/* USWAG dark-mode switch. Separate from script.js: it only sets data-theme on <html> and remembers the choice. */
(function () {
  'use strict';

  var KEY = 'uswag-theme';
  var root = document.documentElement;

  function saved() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }

  function remember(value) {
    try { localStorage.setItem(KEY, value); } catch (e) { /* storage can be blocked; the switch still works for this visit */ }
  }

  function apply(value) {
    if (value === 'dark') { root.setAttribute('data-theme', 'dark'); } else { root.removeAttribute('data-theme'); }
  }

  apply(saved());

  document.addEventListener('DOMContentLoaded', function () {
    var sw = document.getElementById('themeSwitch');
    if (!sw) return;

    function sync() { sw.setAttribute('aria-checked', root.getAttribute('data-theme') === 'dark' ? 'true' : 'false'); }

    sync();
    sw.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      apply(next);
      remember(next);
      sync();
    });
  });
})();
