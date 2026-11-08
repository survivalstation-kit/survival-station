// Shared bits for every portal page: server addresses, status checks, language, theme toggle.
// Needs i18n.js loaded first.
const SURVIVAL = (() => {
  const served = location.protocol.startsWith('http');
  const host = served ? location.hostname : 'localhost';
  const ai = served ? location.origin : 'http://localhost:8080';
  // Plain http: each server on its own port. Secure mode (https on 8443, so phones may use the microphone):
  // one address, and the kit's Caddy passes /library, /tiles and /voice on (a secure page can't call plain http).
  const secure = location.protocol === 'https:';
  const libHost = secure ? location.origin : `http://${host}:8090`;   // the library's own links start /library/...
  const library = libHost + '/library';
  const tiles = secure ? location.origin + '/tiles' : `http://${host}:8092`;   // maps over 2 GB (map server)
  const voice = secure ? location.origin + '/voice' : `http://${host}:8093`;   // speech to text

  async function up(url, ms = 2500) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), ms);
      // no-cors: an opaque reply is enough to prove the server is running
      await fetch(url, { mode: 'no-cors', signal: ctl.signal, cache: 'no-store' });
      clearTimeout(t);
      return true;
    } catch { return false; }
  }

  function store(key, value) {
    try {
      if (value === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, value);
    } catch { return null; }
  }

  // ---- language: saved choice, else the browser's language, else English
  function pickLang() {
    const saved = store('lang');
    if (saved && I18N[saved]) return saved;
    for (const l of navigator.languages || [navigator.language || 'en']) {
      const code = Object.keys(I18N).find(k => k.toLowerCase() === l.toLowerCase())
        || Object.keys(I18N).find(k => k.split('-')[0] === l.split('-')[0]);
      if (code) return code;
    }
    return 'en';
  }
  const lang = pickLang();
  const dict = I18N[lang];
  if (document.body.dataset.page === 'cards' && document.body.dataset.lang !== lang) location.replace(dict._cards);
  const t = (key, vars = {}) => {
    let s = dict[key] ?? I18N.en[key] ?? key;
    if (typeof s === 'string') for (const [k, v] of Object.entries(vars)) s = s.replace(`{${k}}`, v);
    return s;
  };

  function applyI18n() {
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
    document.querySelectorAll('[data-i18n-html]').forEach(el => { el.innerHTML = t(el.dataset.i18nHtml); });
    document.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.dataset.i18nPh); });
    document.querySelectorAll('[data-i18n-title]').forEach(el => { el.title = t(el.dataset.i18nTitle); el.setAttribute('aria-label', el.title); });
    document.querySelectorAll('a[data-cards]').forEach(a => { a.href = dict._cards; });

    const sel = document.querySelector('.lang-select');
    if (sel) {
      sel.replaceChildren(...Object.entries(I18N).map(([code, d]) => new Option(d._name, code, false, code === lang)));
      sel.addEventListener('change', () => {
        store('lang', sel.value);
        // the emergency cards are a separate page per language
        if (document.body.dataset.page === 'cards') location.href = I18N[sel.value]._cards;
        else location.reload();
      });
    }
  }

  // ---- low power (home page switch): dark pages, no library lookup and shorter answers in the chat
  const lowPower = () => store('lowpower') === '1';
  function setLowPower(on) {
    store('lowpower', on ? '1' : '0');
    const theme = on ? 'dark' : (store('theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
    document.documentElement.dataset.theme = theme;
    document.dispatchEvent(new CustomEvent('themechange', { detail: theme }));
  }

  function initTheme() {
    const saved = store('theme');
    if (saved) document.documentElement.dataset.theme = saved;
    if (lowPower()) document.documentElement.dataset.theme = 'dark';   // dark screens use less power on phones
    const btn = document.querySelector('.theme-btn');
    if (!btn) return;
    btn.addEventListener('click', () => {
      const dark = matchMedia('(prefers-color-scheme: dark)').matches;
      const now = document.documentElement.dataset.theme || (dark ? 'dark' : 'light');
      const next = now === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = next;
      store('theme', next);
      document.dispatchEvent(new CustomEvent('themechange', { detail: next }));
    });
  }

  function isDark() {
    const set = document.documentElement.dataset.theme;
    return set ? set === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  }

  // version tag next to the brand on every page (version.js works even when a page is opened as a file)
  function showVersion() {
    const s = document.createElement('script');
    s.src = 'version.js';
    s.onload = () => {
      const v = window.SURVIVAL_VERSION, brand = document.querySelector('.brand');
      if (!v || !brand) return;
      const tag = document.createElement('span');
      tag.className = 'version-tag';
      tag.textContent = 'v' + v.version;
      tag.title = `Survival Station ${v.version} (${v.date})`;
      brand.after(tag);
      if (served) refreshIfUpdated(v.version);
    };
    document.head.append(s);
  }

  // The AI server sends no caching rules, so after an update a browser can keep showing its saved copy
  // of the old pages (old version tag, old map page). Compare with the kit's version.js and, if it
  // changed, fetch this page and its scripts and styles fresh, then reload once.
  async function refreshIfUpdated(have) {
    try {
      const text = await (await fetch('version.js', { cache: 'no-store' })).text();
      const now = (text.match(/version:\s*'([^']+)'/) || [])[1];
      if (!now || now === have || sessionStorage.getItem('refreshed-for') === now) return;
      sessionStorage.setItem('refreshed-for', now);   // never loops, even if a copy stays stale
      const urls = [location.href, ...[...document.querySelectorAll('script[src], link[rel=stylesheet]')].map(e => e.src || e.href)];
      await Promise.all(urls.map(u => fetch(u, { cache: 'reload' }).catch(() => {})));
      location.reload();
    } catch { }
  }

  // "use at your own risk" on every page: at the bottom, under the chat's question box; the map, which fills the
  // screen, carries it in its credits (map.html)
  function showDisclaimer() {
    const page = document.body.dataset.page;
    if (page === 'map') return;
    const p = document.createElement('p');
    p.className = 'disclaimer';
    p.textContent = t(page === 'chat' ? 'disclaimer.short' : 'disclaimer');
    (page === 'chat' ? document.querySelector('.composer') : document.querySelector('main') || document.body)?.append(p);
  }

  initTheme();
  applyI18n();
  showVersion();
  showDisclaimer();
  return { served, host, ai, secure, libHost, library, tiles, voice, up, store, lang, dict, t, isDark, lowPower, setLowPower };
})();
