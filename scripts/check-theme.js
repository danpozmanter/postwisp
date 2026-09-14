#!/usr/bin/env node
// scripts/check-theme.js — exercise the shared theme-boot.js module (the
// code every page's <head> actually runs) under a minimal DOM stub. No
// browser and no npm packages needed: `node scripts/check-theme.js`.
//
// What it drives: the Unsplash picker's key story. The access key comes
// from the server only, so with none configured the modal opens to a
// gentle note pointing at the settings page (and no key input exists
// anywhere in it), while a configured key sends the search straight to
// the Unsplash API and a picked photo reaches the caller. A key the API
// rejects brings the note back, with guidance.

'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'theme-boot.js'), 'utf8');

// ---- DOM stub ------------------------------------------------------
// A per-selector map stands in for querySelector: the picker is the only
// user of it and builds exactly one modal, so every lookup for a given
// selector answers the same stub the page code last touched.
const bySel = {};
const registered = {};
function makeEl() {
    const listeners = {};
    return {
        hidden: false, value: '', textContent: '', innerHTML: '', id: '',
        className: '', dataset: {},
        addEventListener: (t, f) => { (listeners[t] = listeners[t] || []).push(f); },
        dispatch: (t, ev) => (listeners[t] || []).forEach(f => f(ev || {})),
        classList: { add() {}, remove() {}, toggle() {} },
        appendChild(child) { if (child && child.id) registered[child.id] = child; },
        remove() {}, focus() {}, click() {},
        setAttribute() {}, getAttribute() { return null; },
        insertAdjacentHTML(pos, html) { this.innerHTML += html; },
        querySelector(sel) { return bySel[sel] || (bySel[sel] = makeEl()); },
    };
}
const documentListeners = {};
const document = {
    documentElement: { dataset: {}, lang: 'en' },
    body: makeEl(),
    getElementById: id => registered[id] || null,
    createElement: () => makeEl(),
    addEventListener: (t, f) => { (documentListeners[t] = documentListeners[t] || []).push(f); },
    dispatch: (t, ev) => (documentListeners[t] || []).forEach(f => f(ev || {})),
};
const storage = new Map();
const localStorage = {
    getItem: k => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: k => storage.delete(k),
};

const sandbox = {
    document: document,
    localStorage: localStorage,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout,
    console: console,
    fetchCalls: [],
    __unsplash: null,
};
// theme-boot keeps its module state on `window.pw` and the page scripts
// read it back as bare `pw`: aliasing window to the context itself keeps
// both spellings on one object.
sandbox.window = sandbox;
sandbox.fetch = function (url) {
    sandbox.fetchCalls.push(String(url));
    if (String(url).indexOf('api.unsplash.com') >= 0 && sandbox.__unsplash) {
        return Promise.resolve(sandbox.__unsplash());
    }
    // the boot-time /api/public/site probe: answered as "not ok" so the
    // theme section just keeps the server default
    return Promise.resolve({ ok: false, status: 404, json: () => Promise.resolve({}) });
};

// ---- run the module, then drive the picker ------------------------
const driver = `
(async function () {
    const out = [];
    let failures = 0;
    const eq = (name, got, want) => {
        const ok = got === want;
        out.push((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
        if (!ok) failures++;
    };
    const tick = () => new Promise(r => setTimeout(r, 0));
    const unsplashCalled = () => fetchCalls.some(u => u.indexOf('api.unsplash.com') >= 0);

    // ---- the access key is a server-side fact ----
    eq('no server key: unsplashApiKey is empty', pw.unsplashApiKey(), '');
    localStorage.setItem('postwisp-unsplash-key', 'stale-browser-key');
    eq('a stale per-browser key is ignored', pw.unsplashApiKey(), '');
    pw._serverUnsplashKey = 'server-key-1';
    eq('server key: unsplashApiKey hands it over', pw.unsplashApiKey(), 'server-key-1');

    // ---- no key configured: a gentle note, and no key entry ----
    pw._serverUnsplashKey = '';
    let picked = null;
    pw.pickUnsplash({}, d => { picked = d; });
    const root = document.getElementById('pw-modal');
    eq('picker: the modal opens', root.hidden, false);
    eq('picker markup ships the note row', root.innerHTML.indexOf('pw-note-row') >= 0, true);
    eq('no key input exists anywhere in the modal',
        /pw-key-input|pw-key-form|Save key/.test(root.innerHTML), false);
    const noteRow = root.querySelector('.pw-note-row');
    const note = root.querySelector('.pw-note-row p');
    eq('no key: the gentle note shows', noteRow.hidden, false);
    eq('no key: the note names Unsplash and the settings page',
        /unsplash/i.test(note.textContent) && /settings page/i.test(note.textContent), true);
    eq('no key: nothing was searched', unsplashCalled(), false);

    document.dispatch('keydown', { key: 'Escape' });
    eq('Escape closes the picker', root.hidden, true);

    // ---- a configured key: the search reaches the Unsplash API ----
    pw._serverUnsplashKey = 'server-key-1';
    __unsplash = function () {
        return {
            ok: true, status: 200,
            json: () => Promise.resolve({
                total: 1,
                results: [{
                    urls: { regular: 'https://img/one?w=1600', small: 'https://img/t1' },
                    user: { name: 'Jane Doe', links: { html: 'https://unsplash.com/@jane' } }
                }]
            })
        };
    };
    pw.pickUnsplash({ defaultQuery: 'foggy forest' }, d => { picked = d; });
    eq('with key: the note is hidden again', noteRow.hidden, true);
    const search = root.querySelector('.pw-search-input');
    eq('with key: the default query fills the search box', search.value, 'foggy forest');
    await tick();
    const last = fetchCalls[fetchCalls.length - 1] || '';
    eq('with key: the search carries the server key', last.indexOf('client_id=server-key-1') >= 0, true);
    eq('with key: the search carries the query', last.indexOf('query=foggy%20forest') >= 0, true);
    const grid = root.querySelector('.pw-grid');
    eq('with key: photos land in the grid', grid.innerHTML.indexOf('pw-tile') >= 0, true);
    const status = root.querySelector('.pw-status');
    eq('with key: the status names the result count', status.textContent.indexOf('Showing 1 of 1') >= 0, true);

    grid.dispatch('click', {
        target: { closest: () => ({ getAttribute: () => JSON.stringify({ url: 'https://img/one?w=1600', credit: 'Jane Doe' }) }) }
    });
    eq('picking a tile hands the photo to the caller', picked && picked.credit, 'Jane Doe');
    eq('picking closes the picker', root.hidden, true);

    // ---- a key the API rejects: the note returns, with guidance ----
    pw._serverUnsplashKey = 'bad-key';
    __unsplash = function () { return { ok: false, status: 401, json: () => Promise.resolve({}) }; };
    pw.pickUnsplash({ defaultQuery: 'x' }, () => {});
    await tick();
    eq('rejected key: the note shows again', noteRow.hidden, false);
    eq('rejected key: the note still points at the settings page', /settings page/i.test(note.textContent), true);

    if (failures) { print(out.join('\\n')); throw new Error(failures + ' check(s) failed'); }
    print(out.join('\\n'));
})();
`;

sandbox.print = s => console.log(s);
vm.createContext(sandbox);
Promise.resolve(vm.runInContext(src + '\n;' + driver, sandbox)).then(() => {
    console.log('theme-boot module: all checks passed');
    process.exit(0);
}, e => {
    console.error('theme-boot module check FAILED: ' + (e && e.message));
    process.exit(1);
});
