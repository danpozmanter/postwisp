// postwisp — admin-nav.js
// The one nav every admin surface shares: the appbar (top bar) plus the
// admin sub-nav row. admin.html, editor.html and settings.html all load
// this file, so navigating between them can never change either bar —
// the markup and the render function are literally the same bytes.
//
// The bar starts hidden in each page's static markup; renderAdminNav(me)
// un-hides it and fills both rows from the session. me is the /api/me
// answer (null on any of this page's full-screen states: the caller
// passes null before login). activeView names the sub-nav entry to mark
// as the current page ('settings' | 'account' | 'users' | 'media' |
// 'posts' | '' on the editor, where no entry is current).

function pwEsc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

// Theme flip for the appbar's toggle. Same behaviour as every page's
// local toggle: theme-boot.js applied the saved choice pre-paint, this
// only flips it and remembers it.
function pwToggleTheme() {
  const cur = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = cur;
  localStorage.setItem('postwisp-theme', cur);
}

// Fallbacks for the top bar's two inline-handler buttons, so the bar
// works on every page that renders it. admin.html and editor.html define
// their own richer versions later (later script blocks win), which simply
// overwrite these; settings.html keeps these.
async function openAbout() {
  try {
    const r = await fetch('/api/posts', { credentials: 'same-origin' });
    const posts = await r.json();
    const mine = (Array.isArray(posts) ? posts : []).find(p => p.slug === 'about');
    if (mine) { location.href = '/editor?nav=' + mine.nav; return; }
    location.href = '/editor';
  } catch (e) { location.href = '/editor'; }
}

async function doLogout() {
  try { await fetch('/api/logout', { method: 'POST', credentials: 'same-origin' }); } catch (e) {}
  location.href = '/dashboard';
}

function pwRenderAdminNav(me, activeView) {
  const bar = document.getElementById('bar');
  const right = document.getElementById('bar-right');
  // The sub-nav row is optional: the editor carries the top bar but no
  // admin sub-nav, so an empty list is fine — only the bar is required.
  const subs = document.querySelectorAll('.admin-links');
  if (!bar || !right) return;

  // Logged out (or a full-screen state like login/setup): no bar at all,
  // exactly as those pages look today.
  if (!me) { right.innerHTML = ''; subs.forEach(s => { s.innerHTML = ''; }); bar.classList.add('hidden'); return; }

  const link = (view, href, label, title) =>
    `<a class="btn ghost${view === activeView ? ' nav-active' : ''}" href="${href}"${view === activeView ? ' aria-current="page"' : ''} title="${title}">${label}</a>`;

  // The top bar carries the six site-wide destinations. Admin points at
  // the admin landing (the Settings view), never at the posts list.
  right.innerHTML =
    `<span class="who">Welcome, ${pwEsc(me.username)}</span>
     <a class="btn ghost" href="/dashboard#/posts" title="Manage your drafts and published posts">Posts</a>
     <a class="btn ghost" href="/editor" title="Write a post in the full editor">New Post</a>
     <button class="ghost" onclick="openAbout()" title="Create or edit your about page">About Page</button>
     <a class="btn ghost" href="/dashboard#/settings" title="Site settings, your account, users, media and posts">Admin</a>
     <button class="ghost" onclick="pwToggleTheme()" aria-label="Toggle light or dark theme" title="Toggle light/dark theme">◐</button>
     <button class="ghost" onclick="doLogout()">Log Out</button>`;

  // The sub-nav: the five admin pages, in the order the admin asked for
  // them — Settings first, Export All Posts last. One identical row on
  // every admin page (each view's own .admin-links div gets the same
  // markup). Users is admin-only: hidden for other roles, the cosmetic
  // twin of the server's own gate on POST /api/users.
  const subHtml =
    link('settings', '/dashboard#/settings', 'Settings', 'Title, tagline, theme and other site settings') +
    link('account', '/dashboard#/account', 'Account', 'Change your email or password') +
    `${me.role === 'admin' ? link('users', '/dashboard#/users', 'Users', 'Add another author to this postwisp') : ''}` +
    link('media', '/dashboard#/media', 'Media Library', 'Your uploaded photos, videos and audio') +
    link('posts', '/dashboard#/posts', 'Dashboard Posts', 'Your drafts and published posts') +
    `<a class="btn ghost" href="/api/posts.zip" download title="Download all posts as markdown in a zip">Export All Posts (.zip)</a>`;

  subs.forEach(s => { s.innerHTML = subHtml; });
  bar.classList.remove('hidden');
}
