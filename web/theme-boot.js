// theme-boot.js — pre-paint theme choice, then the shared postwisp UI
// modules. Served at /theme-boot.js and loaded synchronously in <head> by
// the admin pages and (optionally) the public templates.
//
// Sections:
//   1. theme        — apply saved visitor choice, else the site setting
//   2. pw helpers   — esc, fmtDate, toggleTheme
//   3. pw cover     — cover-image convention: the FIRST markdown image of
//                     a post's source is its cover/header image
//   4. pw unsplash  — Hashnode-style picker modal: search, grid, choose

// ---------------------------------------------------------------- 1. theme
(function () {
    var saved = null;
    try { saved = localStorage.getItem('postwisp-theme'); } catch (e) { /* private mode */ }
    if (saved === 'light' || saved === 'dark') {
        document.documentElement.dataset.theme = saved;
        return;
    }
    // No visitor choice yet: follow the site-wide setting (async, but the
    // html attribute from the server is already correct for public pages).
    fetch('/api/public/site', { credentials: 'same-origin' })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (s) {
            if (s && (s.theme === 'light' || s.theme === 'dark')) {
                document.documentElement.dataset.theme = s.theme;
            }
        })
        .catch(function () { /* offline: keep server default */ });
})();

// --------------------------------------------------------------- 2. helpers
window.pw = window.pw || {};

pw.esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
};

pw.fmtDate = function (ms) {
    if (!ms) return '';
    // The document's lang (set server-side from the visitor's language)
    // picks the locale, so card dates and the server-rendered post dates
    // agree: en "March 5, 2024", de "5. März 2024", fr "5 mars 2024",
    // es "5 de marzo de 2024".
    var tags = { en: 'en-US', de: 'de-DE', fr: 'fr-FR', es: 'es-ES' };
    var tag = tags[pw.lang()] || undefined;
    try {
        return new Date(ms).toLocaleDateString(tag,
            { year: 'numeric', month: 'long', day: 'numeric' });
    } catch (e) { return ''; }
};

pw.toggleTheme = function () {
    var root = document.documentElement;
    var next = root.dataset.theme === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    try { localStorage.setItem('postwisp-theme', next); } catch (e) { /* ignore */ }
};

// ---- language ----
// The active language: what the server put on <html lang>. The choice a
// visitor makes is a cookie the server reads on every request, so public
// pages, error pages and dates all follow it without any client catalog.

pw.lang = function () {
    var l = document.documentElement.lang || 'en';
    return { en: 'en', de: 'de', fr: 'fr', es: 'es' }[l] || 'en';
};

pw.setLang = function (code) {
    if (!/^(en|de|fr|es)$/.test(code)) return;
    try {
        document.cookie = 'postwisp-lang=' + code +
            ';path=/;max-age=31536000;samesite=lax';
    } catch (e) { /* ignore */ }
    location.reload();
};

// ------------------------------------------------------------------ 3. cover
// The cover of a post is the first markdown image of its source, e.g.
//   ![Photo by Jane Doe on Unsplash](https://images.unsplash.com/...?w=1600)
// The editors manage that line via this module; the post template hoists
// the first rendered <img> of the article into a header figure.

var COVER_RE = /^\s*!\[([^\]]*)\]\(\s*(<[^>]*>|[^\s)]+)[^)]*\)[^\n]*\n?/;

pw.coverFrom = function (source) {
    var m = COVER_RE.exec(String(source == null ? '' : source));
    if (!m) return null;
    return { alt: m[1], url: m[2].replace(/^<|>$/g, ''), raw: m[0] };
};

pw.removeCover = function (source) {
    var s = String(source == null ? '' : source);
    return s.replace(COVER_RE, '').replace(/^\s+/, '');
};

pw.setCover = function (source, alt, url) {
    var clean = pw.removeCover(source);
    // the label rides in the image title — the slot Milkdown keeps when
    // it round-trips a post (the alt slot is rewritten to a size ratio)
    var a = String(alt == null ? '' : alt).replace(/["'()[\]]/g, '').replace(/\s+/g, ' ').trim();
    return '![](' + url + (a ? ' "' + a + '"' : '') + ')\n\n' + clean.replace(/^\s+/, '');
};

// Older helper, kept for custom templates: pulls a leading image markdown
// reference out of excerpt text. The server now sends the header image on
// the summary's own "cover" field and keeps the excerpt clean, so the
// built-in cards no longer need this.
pw.coverFromExcerpt = function (excerpt) {
    var m = /^\s*!\[([^\]]*)\]\(\s*([^\s)]+)[^)]*\)\s*/.exec(String(excerpt == null ? '' : excerpt));
    if (!m) return { url: null, text: String(excerpt == null ? '' : excerpt).trim() };
    return {
        url: m[2],
        alt: m[1],
        text: String(excerpt).slice(m[0].length).replace(/\s+/g, ' ').trim()
    };
};

// ---------------------------------------------------------------- 4. unsplash
// Client-side Unsplash search. The access key lives on the server only
// (setup.sh or the settings page): the editor page sets _serverUnsplashKey
// from /api/settings after login, and the picker reads it through here.
// There is no key entry in the picker — with no key configured the modal
// opens to a gentle note pointing at the settings page instead.

pw.unsplashApiKey = function () {
    return pw._serverUnsplashKey || '';
};

// The gentle note for a server with no key configured yet.
var PW_NO_KEY_NOTE = 'Unsplash search isn\u2019t set up on this server yet. A free access ' +
    'key from unsplash.com/oauth/applications can be added on the Settings page, ' +
    'and the search will work right away.';

// pick({ defaultQuery }, onPick) — onPick receives
// { url, thumb, alt, credit, creditUrl } for the chosen photo.
pw.pickUnsplash = function (opts, onPick) {
    opts = opts || {};
    var key = pw.unsplashApiKey();
    var modal = ensureModal();
    var state = modal._state;

    state.onPick = onPick;
    modal.root.hidden = false;
    document.body.classList.add('pw-modal-open');
    state.query = opts.defaultQuery || '';
    state.page = 1;

    if (!key) { showNoKey(); return; }
    modal.noteRow.hidden = true;
    // the search input lives on the modal object, not on _state
    modal.search.value = state.query;
    if (state.query) doSearch(); else { modal.grid.innerHTML = ''; setStatus('Type a word or two and press Enter — try “mountains”, “desk setup”, “abstract”.'); }
    setTimeout(function () { modal.search.focus(); }, 30);

    function ensureModal() {
        var root = document.getElementById('pw-modal');
        if (root) return root._modal;
        root = document.createElement('div');
        root.id = 'pw-modal';
        root.className = 'pw-modal';
        root.hidden = true;
        root.innerHTML =
            '<div class="pw-modal-card" role="dialog" aria-modal="true" aria-label="Search Unsplash photos">' +
            '  <div class="pw-modal-head">' +
            '    <strong class="pw-modal-title">Unsplash photos</strong>' +
            '    <button type="button" class="btn btn-ghost pw-close" aria-label="Close">&#215;</button>' +
            '  </div>' +
            '  <div class="pw-modal-search">' +
            '    <input type="text" class="pw-search-input" placeholder="Search photos — try “foggy forest”…">' +
            '    <button type="button" class="btn btn-primary pw-search-btn">Search</button>' +
            '  </div>' +
            '  <div class="pw-status" role="status"></div>' +
            '  <div class="pw-note-row" hidden>' +
            '    <p></p>' +
            '  </div>' +
            '  <div class="pw-grid"></div>' +
            '  <div class="pw-modal-foot">Photos by their creators, via <a href="https://unsplash.com" target="_blank" rel="noopener">Unsplash</a> — click one to use it.</div>' +
            '</div>';
        document.body.appendChild(root);

        var m = {
            root: root,
            search: root.querySelector('.pw-search-input'),
            searchBtn: root.querySelector('.pw-search-btn'),
            status: root.querySelector('.pw-status'),
            grid: root.querySelector('.pw-grid'),
            noteRow: root.querySelector('.pw-note-row'),
            note: root.querySelector('.pw-note-row p'),
            _state: { query: '', page: 1, onPick: null, busy: false }
        };
        root._modal = m;

        root.addEventListener('click', function (ev) { if (ev.target === root) close(); });
        root.querySelector('.pw-close').addEventListener('click', close);
        document.addEventListener('keydown', function (ev) {
            if (ev.key === 'Escape' && !root.hidden) close();
        });
        m.search.addEventListener('keydown', function (ev) {
            if (ev.key === 'Enter') { ev.preventDefault(); m._state.query = m.search.value.trim(); m._state.page = 1; doSearch(); }
        });
        m.searchBtn.addEventListener('click', function () {
            m._state.query = m.search.value.trim(); m._state.page = 1; doSearch();
        });
        m.grid.addEventListener('click', function (ev) {
            var tile = ev.target.closest('[data-pw-photo]');
            if (!tile) return;
            var d = JSON.parse(tile.getAttribute('data-pw-photo'));
            close();
            if (m._state.onPick) m._state.onPick(d);
        });
        m.grid.addEventListener('scroll', function () { }, { passive: true });
        return m;
    }

    function close() {
        modal.root.hidden = true;
        document.body.classList.remove('pw-modal-open');
    }
    function setStatus(t) { modal.status.textContent = t; }
    function showNoKey(msg) {
        modal.note.textContent = msg || PW_NO_KEY_NOTE;
        modal.noteRow.hidden = false;
        modal.grid.innerHTML = '';
        setStatus('');
    }

    function doSearch() {
        if (state.busy) return;
        var q = state.query;
        if (!q) { setStatus('Type something to search for first.'); return; }
        if (!pw.unsplashApiKey()) { showNoKey(); return; }
        state.busy = true;
        setStatus('Searching Unsplash for “' + q + '”…');
        if (state.page === 1) modal.grid.innerHTML = '';
        var url = 'https://api.unsplash.com/search/photos?client_id=' + encodeURIComponent(pw.unsplashApiKey()) +
            '&query=' + encodeURIComponent(q) +
            '&page=' + state.page + '&per_page=12&content_filter=high&orientation=landscape';
        fetch(url).then(function (r) {
            if (r.status === 401 || r.status === 403) throw new Error('Unsplash rejected the access key — check it on the settings page.');
            if (!r.ok) throw new Error('Unsplash returned HTTP ' + r.status + '.');
            return r.json();
        }).then(function (d) {
            state.busy = false;
            var results = (d && d.results) || [];
            if (!results.length) { setStatus('No photos matched “' + q + '”. Try different words.'); return; }
            setStatus('Showing ' + results.length + ' of ' + (d.total || results.length) + ' results for “' + q + '”.');
            modal.grid.insertAdjacentHTML('beforeend', results.map(function (p) {
                var alt = 'Photo by ' + (p.user && p.user.name || 'Unsplash') + ' on Unsplash';
                var data = pw.esc(JSON.stringify({
                    url: p.urls.regular,
                    thumb: p.urls.small,
                    alt: alt,
                    credit: (p.user && p.user.name) || 'Unsplash',
                    creditUrl: (p.user && p.user.links && p.user.links.html) || 'https://unsplash.com'
                }));
                return '<button type="button" class="pw-tile" data-pw-photo="' + data + '" title="' + pw.esc(alt) + '">' +
                    '<span class="pw-tile-img" style="background-image:url(' + pw.esc(p.urls.small) + ')"></span>' +
                    '<span class="pw-tile-credit">' + pw.esc((p.user && p.user.name) || '') + '</span>' +
                    '</button>';
            }).join(''));
            if (results.length === 12) {
                ensureMore();
            }
        }).catch(function (e) {
            state.busy = false;
            setStatus(e.message || 'Could not reach Unsplash.');
            if (/rejected the access key/.test(e.message || '')) { keyRejected(); }
        });
    }

    function keyRejected() {
        showNoKey('The Unsplash access key configured on this server was rejected \u2014 ' +
            'please check or replace it on the Settings page.');
    }

    function ensureMore() {
        var old = modal.grid.querySelector('.pw-more');
        if (old) old.remove();
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'btn btn-ghost pw-more';
        b.textContent = 'Load more';
        b.addEventListener('click', function () {
            b.remove();
            state.page += 1;
            doSearch();
        });
        modal.grid.appendChild(b);
    }
};
