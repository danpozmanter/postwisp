#!/usr/bin/env node
// scripts/check-editor.js — exercise the /editor page's inline script
// (the code the browser actually runs) under a minimal DOM stub. No
// browser and no npm packages needed: `node scripts/check-editor.js`.
//
// What it drives: the styled-view / raw-view toggle (markdown round-trips
// without losing edits), word count and read time, insert-at-cursor in
// both views, the heading outline (parse, render, jump), live slug
// feedback, and the unsaved-edits state line.

'use strict';
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'editor.html'), 'utf8');
const appCss = fs.readFileSync(path.join(__dirname, '..', 'web', 'app.css'), 'utf8');

// ---- static page checks ------------------------------------------
// Copy and structure the DOM stub cannot observe: the page's labels, the
// placeholder text, and the raw view's entry outline.
const staticChecks = [
    ['heading says "New Post"', /<h1[^>]*id="heading"[^>]*>\s*New Post\s*</.test(html), true],
    ['the "Write in markdown." subtitle is gone', html.includes('Write in markdown.'), false],
    ['editor placeholder reads "Begin writing here"', html.includes("placeholder: 'Begin writing here'"), true],
    ['raw textarea placeholder reads "Begin writing here"', /<textarea id="raw"[^>]*placeholder="Begin writing here"/.test(html), true],
    ['raw view keeps the entry outline (component border)', /\.editor-shell textarea\.raw-source\s*\{[^}]*border:\s*1px solid var\(--line\)/.test(appCss), true],
    ['raw view gets the input focus treatment', /\.editor-shell textarea\.raw-source:focus/.test(appCss), true],
    ['title input accepts 450 characters (96 grown by half twice over 200)', /<input id="title" maxlength="450"/.test(html), true],
    ['slug input accepts 216 characters (96 grown by half twice)', /<input id="slug" maxlength="216"/.test(html), true],
    ['tags input has no length cap', /<input id="tags"(?![^>]*maxlength)/.test(html), true],
];
let staticFailures = 0;
for (const c of staticChecks) {
    const ok = c[1] === c[2];
    console.log((ok ? 'ok   ' : 'FAIL ') + c[0] +
        (ok ? '' : '  got=' + JSON.stringify(c[1]) + ' want=' + JSON.stringify(c[2])));
    if (!ok) staticFailures++;
}
if (staticFailures) {
    console.error('editor page static checks FAILED: ' + staticFailures + ' check(s) failed');
    process.exit(1);
}

// the page's inline script is the last <script> block in the file
const start = html.lastIndexOf('<script>');
const end = html.lastIndexOf('</script>');
if (start < 0 || end < 0 || end < start) {
    console.error('editor.html: no inline script found');
    process.exit(1);
}
const pageScript = html.slice(start + '<script>'.length, end);

// ---- DOM stub ------------------------------------------------------
// Seeded from the real markup where it matters: the toggle button's
// initial label and aria-pressed come from the HTML itself, so the
// initial-state checks below assert the shipped page, not stub defaults.
const btnTag = html.match(/<button[^>]*id="rawbtn"[^>]*>[^<]*<\/button>/);
if (!btnTag) {
    console.error('editor.html: the #rawbtn toggle button is missing');
    process.exit(1);
}
const seed = {
    rawbtn: {
        text: (btnTag[0].match(/>([^<]*)</) || [])[1] || '',
        'aria-pressed': (btnTag[0].match(/aria-pressed="([^"]*)"/) || [])[1] || '',
    },
};
function makeEl(id) {
    const listeners = {};
    const el = {
        id: id, hidden: false, value: '', textContent: '', title: '', href: '',
        innerHTML: '', scrollTop: 0, clientHeight: 300,
        selectionStart: 0, selectionEnd: 0, style: {},
        files: [],
        addEventListener: (t, f) => { (listeners[t] = listeners[t] || []).push(f); },
        removeEventListener: () => {},
        dispatch: (t, ev) => (listeners[t] || []).forEach(f => f(ev || {})),
        setAttribute: function (k, v) { this['attr_' + k] = String(v); },
        getAttribute: function (k) { return this['attr_' + k]; },
        setSelectionRange: function (a, b) { this.selectionStart = a; this.selectionEnd = b; },
        classList: { toggle: () => {}, add: () => {}, remove: () => {} },
        focus: () => {}, click: () => {},
    };
    const s = seed[id];
    if (s) {
        el.textContent = s.text;
        Object.keys(s).forEach(k => { if (k !== 'text') el['attr_' + k] = s[k]; });
    }
    return el;
}
const els = {};
const document = {
    getElementById: id => (els[id] = els[id] || makeEl(id)),
    createElement: tag => makeEl('created-' + tag),
};
const storage = new Map();
const localStorage = {
    getItem: k => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: k => storage.delete(k),
};
const window = {
    addEventListener: () => {},
    location: { search: '', href: '' },
};
const sandbox = {
    document, localStorage, window,
    location: window.location,
    history: { replaceState: () => {} },
    fetch: () => Promise.resolve({ ok: false, status: 401, json: () => Promise.resolve({}) }),
    URLSearchParams: URLSearchParams,
    setTimeout: setTimeout, clearTimeout: clearTimeout,
    confirm: () => false,
    console: console,
};

// ---- run the page's script, then drive it --------------------------
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
    let backing = 'hello world';

    // a live editor behind #source, standing in for Crepe
    md = {
        getMarkdown: () => backing,
        setMarkdown: s => { backing = s; },
        insert: t => { backing += t; },
        focus: () => {},
    };

    const raw = document.getElementById('raw');
    const source = document.getElementById('source');
    const btn = document.getElementById('rawbtn');
    const wc = document.getElementById('wc');
    const list = document.getElementById('outline-list');
    const savestate = document.getElementById('savestate');

    // ---- styled / raw toggle ----
    eq('toggle starts unpressed', btn.getAttribute('aria-pressed'), 'false');
    eq('toggle starts labelled Raw markdown', btn.textContent, 'Raw markdown');

    setMode(true);
    eq('raw view: textarea carries the markdown', raw.value, 'hello world');
    eq('raw view: styled editor hidden', source.hidden, true);
    eq('raw view: pressed', btn.getAttribute('aria-pressed'), 'true');
    eq('raw view: label flips to Styled view', btn.textContent, 'Styled view');
    eq('raw view: word count + read time follow', wc.textContent, '2 words · 1 min read');

    raw.value = 'one two three four';
    raw.dispatch('input');
    eq('raw edit: word count updates', wc.textContent, '4 words · 1 min read');
    eq('raw edit: save state names unsaved edits', savestate.textContent, 'unsaved edits');

    raw.selectionStart = raw.selectionEnd = 0;
    insertMd('![x](u) ');
    eq('raw insert: spliced at the cursor', raw.value, '![x](u) one two three four');

    setMode(false);
    eq('styled view: markdown carried back', backing, '![x](u) one two three four');
    eq('styled view: toggle released', btn.getAttribute('aria-pressed'), 'false');
    eq('styled view: label flips back', btn.textContent, 'Raw markdown');
    eq('styled view: word count follows', wc.textContent, '5 words · 1 min read');

    insertMd(' + tail');
    eq('styled insert: goes to the editor', backing, '![x](u) one two three four + tail');

    clearDrafts('new');
    eq('clearDrafts clears the save state', savestate.textContent, '');

    // ---- outline ----
    setMode(true);
    setSrc('# One\\n\\nintro text\\n\\n## Two words\\n\\n\\u0060\\u0060\\u0060\\n# fenced, not a heading\\n\\u0060\\u0060\\u0060\\n\\n### Three');
    const heads = parseOutline(raw.value);
    eq('outline: headings found', heads.length, 3);
    eq('outline: fenced code skipped', heads.some(h => h.text === 'fenced, not a heading'), false);
    eq('outline: levels kept', heads.map(h => h.level).join(','), '1,2,3');
    eq('outline: text trimmed', heads[1].text, 'Two words');

    renderOutline();
    eq('outline: rendered into the list', list.innerHTML.includes('Two words'), true);
    eq('outline: level rides as data-level', list.innerHTML.includes('data-level="2"'), true);
    eq('outline: entries are clickable', list.innerHTML.includes('data-i="1"'), true);

    setSrc('just prose, no headings at all');
    renderOutline();
    eq('outline: empty state explains how to start', list.innerHTML.includes('outline-empty'), true);

    // clicking an entry jumps to that heading (raw view: caret + scroll).
    // The filler makes the target far enough down to need real scrolling.
    setSrc('para\\n\\n# A\\n' + 'filler line\\n'.repeat(12) + '\\n## B target');
    renderOutline();
    list.dispatch('click', {
        preventDefault: () => {},
        target: { closest: () => ({ getAttribute: () => '1' }) },
    });
    eq('outline: click jumps the caret to the heading', raw.selectionStart, raw.value.indexOf('## B'));
    eq('outline: click scrolls the heading into view', raw.scrollTop > 0, true);

    // ---- slug feedback ----
    eq('slug: valid shape accepted', validSlug('a-b-2'), true);
    eq('slug: uppercase rejected', validSlug('Nope'), false);
    eq('slug: 216 characters accepted', validSlug('a'.repeat(216)), true);
    eq('slug: 217 characters rejected', validSlug('a'.repeat(217)), false);
    eq('slugify: a long title derives at most 216', slugify('a'.repeat(450)).length, 216);
    eq('slugify: the cut never leaves a trailing dash', slugify('a'.repeat(215) + '-' + 'b'.repeat(10)).length, 215);
    applySlugResult({ ok: true });
    eq('slug: available named', document.getElementById('slug-state').textContent, '✓ available');
    applySlugResult({ ok: false, reason: 'taken' });
    eq('slug: taken named', document.getElementById('slug-state').textContent, '✗ taken — pick another');
    applySlugResult({ ok: false, reason: 'invalid' });
    eq('slug: malformed named', document.getElementById('slug-state').textContent, 'letters, digits, single hyphens');
    postId = 'nav-7';
    eq('slug: own post excluded from the check', slugCheckUrl('a'), '/api/slug-check?slug=a&except=nav-7');
    postId = null;

    if (failures) { print(out.join('\\n')); throw new Error(failures + ' check(s) failed'); }
    print(out.join('\\n'));
})();
`;

sandbox.print = s => console.log(s);
try {
    vm.createContext(sandbox);
    vm.runInContext(pageScript + '\n' + driver, sandbox, { timeout: 5000 });
    console.log('editor page script: all checks passed');
    process.exit(0);
} catch (e) {
    console.error('editor page script check FAILED: ' + e.message);
    process.exit(1);
}
