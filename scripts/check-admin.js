#!/usr/bin/env node
// scripts/check-admin.js — exercise the /dashboard page's inline script
// (the code the browser actually runs) under a minimal DOM stub, and
// prove the consolidation: the dashboard no longer embeds an editor, and
// every editing entry point navigates to /editor, the single writing
// surface. No browser and no npm packages: `node scripts/check-admin.js`.

'use strict';
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'admin.html'), 'utf8');
// The shared admin nav lives in its own file; the New Post link, the
// Admin link and the sub-nav row all render from it, so its bytes are
// what the nav checks assert against.
const navJs = fs.readFileSync(path.join(__dirname, '..', 'web', 'admin-nav.js'), 'utf8');
// the region of admin-nav.js where the sub-nav row is built
const subNavStart = navJs.indexOf('const subHtml');
const subNavRegion = navJs.slice(subNavStart, navJs.indexOf('subs.forEach', subNavStart));

// ---- consolidation: the shipped markup itself ----------------------
// These assert the page the server sends, before any script runs.
const markupChecks = [
    ['no editor bundle on the dashboard', html.includes('/milkdown.js'), false],
    ['no editor stylesheet on the dashboard', html.includes('/milkdown.css'), false],
    ['no embedded editor view', html.includes('view-editor'), false],
    ['no raw-toggle button', html.includes('dash-rawbtn'), false],
    ['New Post link is in the shared nav, opens /editor', /href="\/editor"[^>]*title="Write a post in the full editor"[^>]*>New Post</.test(navJs), true],
    ['each post edit link opens /editor', html.includes('href="/editor?nav=${p.nav}"'), true],
    // ---- page titles in Proper Case (the five hash views' <h1>s) ----
    ['h1 "Dashboard Posts" is Proper Case', /<h1[^>]*>\s*Dashboard Posts\s*</.test(html), true],
    ['h1 "Account" is Proper Case', /<h1[^>]*>\s*Account\s*</.test(html), true],
    ['h1 "Users" is Proper Case', /<h1[^>]*>\s*Users\s*</.test(html), true],
    ['h1 "Media Library" is Proper Case', /<h1[^>]*>\s*Media Library\s*</.test(html), true],
    ['h1 "Settings" is Proper Case', /<h1[^>]*>\s*Settings\s*</.test(html), true],
    ['old "Your Posts" heading is gone', /<h1[^>]*>\s*Your Posts\s*/.test(html), false],
    ['sub-nav order: Settings first, Export All Posts last', (() => {
        const labels = ['Settings', 'Account', 'Users', 'Media Library', 'Dashboard Posts', 'Export All Posts'];
        const pos = labels.map(l => subNavRegion.indexOf(l));
        if (pos.some(p => p < 0)) return false;
        return pos.every((p, i) => i === 0 || p > pos[i - 1]);
    })(), true],
    ['Admin in the top bar points at the Settings view', /href="\/dashboard#\/settings"[^>]*title="[^"]*"[^>]*>Admin</.test(navJs), true],
    ['login heading "Log In" is Proper Case', /<h1>\s*Log In\s*</.test(html), true],
    ['two-factor heading "Login Code" is Proper Case', /<h1>\s*Login Code\s*</.test(html), true],
    ['recovery heading "Recover Your Account" is Proper Case', /<h1>\s*Recover Your Account\s*</.test(html), true],
    ['reset heading "Set a New Password" is Proper Case', /<h1>\s*Set a New Password\s*</.test(html), true],
    ['setup heading "First Boot — Create the Admin Account" is Proper Case', /<h1>\s*First Boot — Create the Admin Account\s*</.test(html), true],
    ['no lowercase page headings remain', /<h[12][^>]*>\s*(Log in|Login code|Recover your account|Set a new password|Your posts|Your account|Media library|First boot)/.test(html), false],
];
let bad = 0;
for (const [name, got, want] of markupChecks) {
    console.log((got === want ? 'ok   ' : 'FAIL ') + name);
    if (got !== want) bad++;
}
if (bad) { console.error('admin.html: ' + bad + ' markup check(s) failed'); process.exit(1); }

// the dashboard's page script is the FIRST inline <script> block; the
// last one is the tiny fatal-error handler.
const start = html.indexOf('<script>');
const startEnd = html.indexOf('</script>', start);
if (start < 0 || startEnd < 0) {
    console.error('admin.html: no inline script found');
    process.exit(1);
}
const pageScript = html.slice(start + '<script>'.length, startEnd) +
    // the page's catch blocks call showFatal(), which the LAST inline
    // block defines — evaluate it alongside the page script
    '\n' + html.slice(html.lastIndexOf('<script>') + '<script>'.length,
                      html.indexOf('</script>', html.lastIndexOf('<script>')));

// ---- DOM stub ------------------------------------------------------
function makeEl(id) {
    const listeners = {};
    const el = {
        id: id, hidden: false, value: '', textContent: '', title: '', href: '',
        innerHTML: '',
        addEventListener: (t, f) => { (listeners[t] = listeners[t] || []).push(f); },
        removeEventListener: () => {},
        dispatch: (t, ev) => (listeners[t] || []).forEach(f => f(ev || {})),
        setAttribute: function (k, v) { this['attr_' + k] = String(v); },
        getAttribute: function (k) { return this['attr_' + k]; },
        classList: { toggle: () => {}, add: () => {}, remove: () => {}, contains: () => false },
        focus: () => {}, click: () => {},
    };
    return el;
}
const els = {};
const document = {
    getElementById: id => (els[id] = els[id] || makeEl(id)),
    createElement: tag => makeEl('created-' + tag),
    // not 'loading', so the page's onReady() runs its wiring immediately
    readyState: 'complete',
    documentElement: { dataset: {} },
    addEventListener: () => {},
};
const storage = new Map();
const localStorage = {
    getItem: k => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: k => storage.delete(k),
};
const window = { addEventListener: () => {} };

const sandbox = {
    document, localStorage, window,
    location: { search: '', pathname: '/dashboard', href: '' },
    fetch: () => Promise.resolve({ ok: false, status: 401, json: () => Promise.resolve({}) }),
    URLSearchParams: URLSearchParams,
    setTimeout: setTimeout, clearTimeout: clearTimeout,
    console: console,
};

// ---- run the page's script, then drive the dashboard ---------------
const vm = require('vm');
const driver = `
;(function () {
    const out = [];
    const eq = (name, got, want) => {
        const ok = got === want;
        out.push((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
        if (!ok) failures++;
    };
    let failures = 0;

    // ---- consolidation: no editor machinery survives in the page ----
    // eval(name) throws ReferenceError for a name nothing declares, so
    // it answers "defined" exactly when the page still carries it.
    const gone = ['openEditor', 'savePost', 'togglePublish', 'setMode',
                   'getSrc', 'setSrc', 'insertMd', 'ensureMd', 'uploadImage',
                   'pickImage', 'pickUnsplashImage', 'markDirty', 'saveDraft',
                   'clearDrafts', 'checkDraft', 'restoreDraft', 'rawMode'];
    for (const name of gone) {
        let state;
        try { eval(name); state = 'defined'; } catch (e) { state = 'undefined'; }
        eq('dashboard script no longer defines ' + name, state, 'undefined');
    }

    // ---- the post list routes every edit to /editor ----
    allPosts = [
        { nav: 'nav-5', title: 'Hello <b>world</b>', status: 'draft', username: 'dan',
          slug: 'hello', source: 'x', tags: 'a,b', modified_at: 1700000000000 },
        { nav: 'nav-9', title: 'Published one', status: 'published', username: 'dan',
          slug: 'pub', source: 'y', tags: '', published_at: 1700000000000 },
    ];
    renderDashboard();
    const rendered = document.getElementById('dash-lists').innerHTML;
    eq('draft edit link opens /editor', rendered.includes('href="/editor?nav=nav-5"'), true);
    eq('published edit link opens /editor', rendered.includes('href="/editor?nav=nav-9"'), true);
    eq('draft title link opens /editor', rendered.includes('href="/editor?nav=nav-5"'), true);
    eq('titles are escaped', rendered.includes('Hello &lt;b&gt;world&lt;/b&gt;'), true);
    eq('tags render as chips', rendered.includes('chip'), true);

    if (failures) { print(out.join('\\n')); throw new Error(failures + ' check(s) failed'); }
    print(out.join('\\n'));
})();
`;

sandbox.print = s => console.log(s);
try {
    vm.createContext(sandbox);
    vm.runInContext(pageScript + '\n' + driver, sandbox, { timeout: 5000 });
    console.log('admin page script: all checks passed');
    process.exit(0);
} catch (e) {
    console.error('admin page script check FAILED: ' + e.message);
    process.exit(1);
}
