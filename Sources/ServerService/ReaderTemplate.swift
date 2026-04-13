/// The reader HTML template.
///
/// Contains the full HTML page with Typora Night theme CSS and reader JS.
/// The placeholder `<!--DIGEST_DATA-->` is replaced with rendered digest HTML.
///
/// JS features:
/// - Search: keyword + tag matching via data-tags attribute
/// - Foldable sections: `<details>` toggle
/// - Image lightbox: click to zoom
/// - Video thumbnails: poster + click-to-play
/// - Show more: clips long posts
/// - Polling: checks /api/mtime every 10s for new content
/// - FABs: search, scroll-to-top, generate
let readerTemplate = ##"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Xdigest">
<link rel="icon" type="image/png" sizes="32x32" href="/xd-icon.png">
<link rel="apple-touch-icon" href="/icon-180.png">
<link rel="manifest" href="/manifest.json">
<title>xdigest</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body {
  background: #363B40;
  color: #b8bfc6;
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.625rem;
  -webkit-font-smoothing: antialiased;
  margin: 0;
  padding: 0;
  width: 100%;
}
.page-wrapper {
  overflow-x: hidden;
  width: 100%;
  max-width: 100%;
  position: relative;
}
#app { max-width: 914px; width: 100%; box-sizing: border-box; margin: 0 auto; padding: 16px; overflow: hidden; word-break: break-word; }
#app * { max-width: 100%; box-sizing: border-box; }
@media (max-width: 430px) { #app { padding: 8px; } }
@media (min-width: 1400px) { #app { max-width: 1024px; } }
h1 { font-size: 2.5rem; font-weight: 600; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, sans-serif; color: #f5f5f7; letter-spacing: -0.03em; margin-bottom: 4px; padding-top: env(safe-area-inset-top, 0px); }
h2, h2.section-time { font-size: 1.2rem; font-weight: 600; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, sans-serif; color: #86868b; letter-spacing: -0.01em; padding: 20px 0 8px 0; border-bottom: 1px solid #424245; margin: 0; }
details.section { border-bottom: 1px solid #474d54; }
details.section > summary.section-time { cursor: pointer; list-style: none; font-size: 1.2rem; font-weight: 600; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, sans-serif; color: #86868b; letter-spacing: -0.01em; padding: 16px 0 8px 0; margin: 0; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #424245; }
details.section > summary.section-time::-webkit-details-marker { display: none; }
details.section > summary.section-time::after { content: '\25BC'; font-size: 10px; color: #86868b; transition: transform 0.2s; }
details.section:not([open]) > summary.section-time::after { content: '\25B6'; }
details.section > summary.section-time:hover { color: #f5f5f7; }
b, strong { color: #DEDEDE; }
a { color: #e0e0e0; text-decoration: underline; }
a:hover { color: #fff; }
img { max-width: 100%; border-radius: 16px; margin-top: 12px; }
video { max-width: 100%; border-radius: 16px; margin-top: 12px; }
.video-thumb { position: relative; cursor: pointer; margin-top: 12px; display: inline-block; max-width: 100%; }
.video-thumb img { max-width: 100%; max-height: 600px; border-radius: 16px; display: block; }
.video-thumb .play-btn { position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%); width: 60px; height: 60px; background: rgba(0,0,0,0.6); border-radius: 50%; display: flex; align-items: center; justify-content: center; }
.video-thumb .play-btn::after { content: ''; display: block; width: 0; height: 0; border-style: solid; border-width: 12px 0 12px 22px; border-color: transparent transparent transparent #fff; margin-left: 4px; }
.video-thumb:hover .play-btn { background: rgba(29,155,240,0.8); }
#banner { display: none; background: rgba(29,155,240,0.95); color: #fff; text-align: center; padding: 10px; cursor: pointer; font-size: 14px; font-weight: 600; border-radius: 8px; margin: 12px 0 16px 0; }
.search-bar { display: none; position: fixed; top: 0; left: 0; right: 0; z-index: 200; padding: 10px 16px; background: rgba(54,59,64,0.92); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); box-shadow: 0 2px 12px rgba(0,0,0,0.3); }
.search-row { display: flex; align-items: center; gap: 10px; }
.search-cancel { background: none; border: none; color: #DEDEDE; font-size: 15px; cursor: pointer; padding: 8px; flex-shrink: 0; -webkit-tap-highlight-color: transparent; }
.search-cancel:hover { color: #fff; }
.search-bar.active { display: block; }
.search-bar.active ~ #timeline { padding-top: 80px; }
.search-input-wrap { display: flex; align-items: center; gap: 10px; background: rgba(255,255,255,0.1); backdrop-filter: blur(24px) saturate(180%); -webkit-backdrop-filter: blur(24px) saturate(180%); border: 1px solid rgba(255,255,255,0.15); border-radius: 28px; padding: 10px 16px; box-shadow: 0 2px 12px rgba(0,0,0,0.2), inset 0 1px 1px rgba(255,255,255,0.1); }
.search-input-wrap svg { width: 18px; height: 18px; fill: rgba(255,255,255,0.5); flex-shrink: 0; }
.search-input-wrap input { flex: 1; background: none; border: none; outline: none; color: #DEDEDE; font-size: 16px; font-family: inherit; }
.search-input-wrap input::placeholder { color: rgba(255,255,255,0.35); }
.search-input-wrap .search-clear { cursor: pointer; padding: 2px; }
.search-count { font-size: 12px; color: #7a8088; padding: 4px 0; text-align: center; }
.search-highlight { background: rgba(29,155,240,0.3); border-radius: 2px; }
.fab-container { position: fixed; bottom: 24px; right: 16px; display: flex; flex-direction: column; gap: 10px; z-index: 999; }
@supports (padding: env(safe-area-inset-bottom)) { .fab-container { bottom: calc(24px + env(safe-area-inset-bottom)); } }
.fab { width: 36px; height: 36px; border-radius: 50%; border: 1px solid rgba(255,255,255,0.15); cursor: pointer; display: flex; align-items: center; justify-content: center; transition: transform 0.15s, box-shadow 0.2s; -webkit-tap-highlight-color: transparent; backdrop-filter: blur(24px) saturate(180%) brightness(1.1); -webkit-backdrop-filter: blur(24px) saturate(180%) brightness(1.1); background: rgba(255,255,255,0.12); box-shadow: 0 4px 20px rgba(0,0,0,0.3), 0 0 0 0.5px rgba(255,255,255,0.15), inset 0 1px 1px rgba(255,255,255,0.15), inset 0 -1px 1px rgba(0,0,0,0.1); }
.fab:active { transform: scale(0.88); box-shadow: 0 2px 10px rgba(0,0,0,0.3), inset 0 1px 1px rgba(255,255,255,0.1); }
.fab svg { width: 16px; height: 16px; fill: rgba(180,180,185,0.9); }
.fab-generate { background: rgba(29,155,240,0.35); border-color: rgba(29,155,240,0.3); }
.fab-generate svg { fill: rgba(180,180,185,0.9); }
.fab-generate.loading { pointer-events: none; }
@keyframes spin { to { transform: rotate(360deg); } }
.fab-generate.loading svg { animation: spin 1s linear infinite; opacity: 0.7; }
.post-body { position: relative; }
.post-body.clipped { max-height: 200px; overflow: hidden; }
.post-body.clipped::after { content: ''; position: absolute; bottom: 0; left: 0; right: 0; height: 60px; background: linear-gradient(transparent, #363B40); pointer-events: none; }
.show-more { color: #1d9bf0; cursor: pointer; padding: 4px 0; font-size: 15px; }
.show-more:hover { text-decoration: underline; }
.lightbox { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.85); z-index: 9999; display: flex; align-items: center; justify-content: center; cursor: zoom-out; backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); }
.lightbox img { max-width: 95%; max-height: 95vh; object-fit: contain; border-radius: 8px; }
img[style*="border-radius"]:not([width="32"]) { cursor: zoom-in; }
</style>
</head>
<body data-initial-position="<!--INITIAL_POSITION-->" data-initial-fraction="<!--INITIAL_FRACTION-->" data-initial-version="<!--INITIAL_VERSION-->" data-instance-id="<!--INSTANCE_ID-->">
<div class="page-wrapper">
<div id="app">
<h1>xdigest</h1>
<div id="banner" onclick="window.scrollTo({top:0,behavior:'smooth'});this.style.display='none'"></div>
<div class="search-bar" id="search-bar">
  <div class="search-row">
    <div class="search-input-wrap">
      <svg viewBox="0 0 24 24"><path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0016 9.5 6.5 6.5 0 109.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>
      <input type="text" id="search-input" placeholder="Search posts..." autocomplete="off" autocorrect="off" autocapitalize="off">
      <svg class="search-clear" id="search-clear" viewBox="0 0 24 24" onclick="searchInput.value='';searchClear.style.display='none';doSearch()" style="display:none;cursor:pointer"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
    </div>
    <button class="search-cancel" onclick="clearSearch()">Cancel</button>
  </div>
  <div class="search-count" id="search-count"></div>
</div>
<div id="timeline"><!--DIGEST_DATA--></div>
</div>
<div class="fab-container">
  <button class="fab fab-search" id="fab-search" onclick="toggleSearch()" title="Search">
    <svg viewBox="0 0 24 24"><path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0016 9.5 6.5 6.5 0 109.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>
  </button>
  <button class="fab fab-home" onclick="window.scrollTo({top:0,behavior:'smooth'})" title="Scroll to top">
    <svg viewBox="0 0 24 24"><path d="M12 3l-10 9h3v9h6v-6h2v6h6v-9h3z"/></svg>
  </button>
  <button class="fab fab-generate" id="fab-gen" onclick="generateMore()" title="Generate more">
    <svg viewBox="0 0 24 24"><path d="M17.65 6.35A7.958 7.958 0 0012 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0112 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
  </button>
</div>
</div>
<script>
var tl = document.getElementById('timeline');
var banner = document.getElementById('banner');
var searchBar = document.getElementById('search-bar');
var searchInput = document.getElementById('search-input');
var searchClear = document.getElementById('search-clear');
var searchCount = document.getElementById('search-count');
var searchActive = false;

function toggleSearch() {
  searchActive = !searchActive;
  if (searchActive) {
    searchBar.classList.add('active');
    searchInput.focus();
  } else {
    clearSearch();
  }
}

function clearSearch() {
  searchInput.value = '';
  searchClear.style.display = 'none';
  searchCount.textContent = '';
  searchBar.classList.remove('active');
  searchActive = false;
  tl.querySelectorAll('img[width="32"]').forEach(function(img) {
    var post = img.parentElement;
    if (post) post.style.display = '';
  });
  tl.querySelectorAll('details.section').forEach(function(d) {
    d.style.display = '';
    d.setAttribute('open', '');
  });
}

var searchTimeout = null;
searchInput.addEventListener('input', function() {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(doSearch, 200);
  searchClear.style.display = this.value ? 'block' : 'none';
});

function doSearch() {
  var q = searchInput.value.trim().toLowerCase();
  if (!q) {
    clearSearch();
    searchBar.classList.add('active');
    searchInput.focus();
    return;
  }
  var posts = [];
  tl.querySelectorAll('img[width="32"]').forEach(function(img) {
    var post = img.parentElement;
    if (post && post.tagName === 'DIV') posts.push(post);
  });
  var matched = 0;
  var total = posts.length;
  posts.forEach(function(post) { post.style.display = 'none'; });
  tl.querySelectorAll('details.section').forEach(function(d) {
    d.removeAttribute('open');
    d.style.display = 'none';
  });
  posts.forEach(function(post) {
    var text = post.textContent.toLowerCase().replace(/\s+/g, ' ');
    var tags = (post.getAttribute('data-tags') || '').toLowerCase();
    var searchable = text + ' ' + tags;
    var words = q.split(/\s+/).filter(function(w) { return w.length > 0; });
    var allMatch = words.every(function(w) { return searchable.indexOf(w) >= 0; });
    if (allMatch) {
      post.style.display = '';
      matched++;
      var section = post.closest('details.section');
      if (section) {
        section.style.display = '';
        section.setAttribute('open', '');
      }
    }
  });
  searchCount.textContent = matched + ' of ' + total + ' posts';
  if (matched > 0) window.scrollTo(0, 0);
}

function generateMore() {
  var btn = document.getElementById('fab-gen');
  btn.classList.add('loading');
  btn.title = 'Generating...';
  // Kick off server-side generation. The banner is NOT managed here --
  // the server's SSE broadcast triggers fetchPendingDigest which owns
  // the banner. This endpoint response only tells us the spinner can
  // stop; the banner appears via the SSE path.
  fetch('/api/generate', {method: 'POST'}).then(function(r) { return r.json(); }).then(function(d) {
    btn.classList.remove('loading');
    btn.title = 'Generate more';
    if (d.picks === 0) {
      btn.title = 'No new picks';
      setTimeout(function() { btn.title = 'Generate more'; }, 3000);
    }
  }).catch(function(e) {
    btn.classList.remove('loading');
    btn.title = 'Error: ' + e.message;
  });
}

document.addEventListener('click', function(e) {
  var img = e.target;
  if (img.tagName === 'IMG' && img.style.borderRadius && img.width !== 44) {
    var lb = document.createElement('div');
    lb.className = 'lightbox';
    var big = document.createElement('img');
    big.src = img.src;
    lb.appendChild(big);
    lb.onclick = function() { lb.remove(); };
    document.body.appendChild(lb);
  }
  if (img.classList && img.classList.contains('lightbox')) {
    img.remove();
  }
});
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    var lb = document.querySelector('.lightbox');
    if (lb) lb.remove();
  }
});

var urlParams = new URLSearchParams(window.location.search);
if (urlParams.has('q')) {
  toggleSearch();
  searchInput.value = urlParams.get('q');
  searchClear.style.display = 'block';
  doSearch();
}

try { document.querySelectorAll('div[style*="display:flex"]').forEach(function(post) {
  var bodyDivs = post.querySelectorAll('div[style*="font-size:15px"], div[style*="line-height:1.5"]');
  bodyDivs.forEach(function(body) {
    if (body.scrollHeight > 250) {
      body.classList.add('post-body', 'clipped');
      var link = document.createElement('div');
      link.className = 'show-more';
      link.textContent = 'Show more';
      link.onclick = function() {
        if (body.classList.contains('clipped')) {
          body.classList.remove('clipped');
          link.textContent = 'Show less';
        } else {
          body.classList.add('clipped');
          link.textContent = 'Show more';
        }
      };
      body.parentNode.insertBefore(link, body.nextSibling);
    }
  });
});
} catch(e) { console.error('show-more error:', e); }

try { document.querySelectorAll('video').forEach(function(vid) {
  var src = vid.getAttribute('data-src') || vid.getAttribute('src') || '';
  var poster = vid.getAttribute('poster') || '';
  if (poster && src) {
    var thumb = document.createElement('div');
    thumb.className = 'video-thumb';
    thumb.innerHTML = '<img src="' + poster + '"><div class="play-btn"></div>';
    thumb.onclick = function() {
      var w = thumb.querySelector('img').offsetWidth;
      var v = document.createElement('video');
      v.src = src;
      v.poster = poster;
      v.controls = true;
      v.playsInline = true;
      v.autoplay = true;
      v.style.width = w + 'px';
      v.style.borderRadius = '16px';
      v.style.marginTop = '12px';
      thumb.replaceWith(v);
    };
    vid.replaceWith(thumb);
  }
});
} catch(e) { console.error('video error:', e); }

// Cross-device sync state (tmux-style: server owns state, client applies
// strictly by version).
var localVersion = -1;       // highest version we've applied from the server
var serverMtime = 0;
var serverPosition = '';
var serverFraction = 0;      // the server's last-known fraction into serverPosition
var knownInstanceId = '';    // server instance ID we loaded; reload if it changes
var inProgrammaticScroll = 0;  // counter, handles overlapping programmatic scrolls
var lastUserScrollTime = 0;
var IDLE_MS = 3000;          // don't interrupt active reading within this window
var prefetchInFlight = false;
var serverCanGenerate = true;

// Extract post IDs from the timeline, in document order.
function extractPostIds() {
  var ids = [];
  allPosts().forEach(function(post) { ids.push(postIdOf(post)); });
  return ids;
}

// The "reading anchor": the y position in the viewport that represents
// the top of the user's "reading area." Everything above is "scrolled past."
var READING_ANCHOR = 60;

// --- Small, single-purpose helpers (Unix-style) ---

// Returns all post elements in document order.
function allPosts() {
  return tl.querySelectorAll('div[data-post-id]');
}

// Looks up a single post element by ID.
function postById(postId) {
  return tl.querySelector('div[data-post-id="' + postId + '"]');
}

// Returns the post ID from a post element.
function postIdOf(post) {
  return post.getAttribute('data-post-id');
}

// Does the post's visible range span the reading anchor?
function postContainsAnchor(rect) {
  return rect.top <= READING_ANCHOR && rect.bottom > READING_ANCHOR;
}

// Clamps a number to [0, 1].
function clamp01(x) {
  if (x < 0) return 0;
  if (x > 1) return 1;
  return x;
}

// Fractional offset from a post's top to the reading anchor.
function fractionAt(rect) {
  var height = rect.height || 1;
  return clamp01((READING_ANCHOR - rect.top) / height);
}

// Build an anchor object from a post element.
function anchorForPost(post, fraction) {
  return { postId: postIdOf(post), fraction: fraction };
}

// --- Main operations: findReadingAnchor and scrollToAnchor ---

// Find the post containing the reading anchor, and the fraction (0..1)
// from that post's top to the anchor.
//
// The `(postId, fraction)` pair is what transfers across devices: the
// sequence of posts is stable, and the fractional offset within a post
// is approximately stable under reflow. Together they reproduce the same
// "reading position" on a different screen size -- like resizing a browser
// window preserves the top of the visible content.
function findReadingAnchor() {
  var posts = allPosts();
  var lastAbove = null;
  for (var i = 0; i < posts.length; i++) {
    var rect = posts[i].getBoundingClientRect();
    if (postContainsAnchor(rect)) {
      return anchorForPost(posts[i], fractionAt(rect));
    }
    if (rect.top > READING_ANCHOR) {
      // The anchor falls in a gap above this post. Use this post's top.
      return anchorForPost(posts[i], 0);
    }
    lastAbove = posts[i];
  }
  // All posts are above the anchor. Clamp to the last one's bottom.
  if (lastAbove) {
    return anchorForPost(lastAbove, 1);
  }
  return { postId: '', fraction: 0 };
}

// Computes the target scrollY that places `fraction` into `post` at the anchor.
function targetScrollY(post, fraction) {
  var y = post.offsetTop + (fraction || 0) * post.offsetHeight - READING_ANCHOR;
  return Math.max(0, y);
}

// Wraps a programmatic scroll with the suppression counter so that the
// resulting scroll events don't feed back into sendAnchor.
function withSuppressedScrollSync(fn) {
  inProgrammaticScroll++;
  fn();
  requestAnimationFrame(function() {
    requestAnimationFrame(function() {
      inProgrammaticScroll--;
    });
  });
}

// Scroll so that `fraction` into `postId` sits at the reading anchor.
function scrollToAnchor(postId, fraction) {
  if (!postId) return;
  var post = postById(postId);
  if (!post) return;
  withSuppressedScrollSync(function() {
    window.scrollTo(0, targetScrollY(post, fraction));
  });
}

// --- Pending digest state ---
//
// When the server generates new posts, we FETCH the new digest HTML
// but do NOT apply it to the DOM until the user clicks the banner.
// This keeps the reader's "what's visible" consistent with the user's
// intent: new posts appear only when explicitly requested.
var pendingHTML = null;
var pendingNewCount = 0;
// Monotonic fetch sequence token. Incremented per request. Late-arriving
// responses from stale fetches are dropped by comparing against this.
var pendingFetchSeq = 0;

// Banner visibility for the "catch up to your reading position" case
// (user loaded the page mid-read, needs to scroll to newest).
// If there's pendingHTML, the pending flow owns the banner -- bail out
// so we don't clobber it.
function updateBanner() {
  if (pendingHTML !== null) return;
  if (!serverPosition) {
    banner.style.display = 'none';
    return;
  }
  var postIds = extractPostIds();
  var idx = postIds.indexOf(serverPosition);
  if (idx > 0) {
    banner.textContent = idx + ' new post' + (idx > 1 ? 's' : '');
    banner.style.display = 'block';
    banner.onclick = function() {
      banner.style.display = 'none';
      window.scrollTo(0, 0);
      var newest = postIds[0];
      if (newest) postAnchor({ postId: newest, fraction: 0 });
    };
  } else {
    banner.style.display = 'none';
  }
}

// Fetch the new digest HTML into `pendingHTML` WITHOUT applying it to
// the DOM. Show a banner with the new post count. User clicks the
// banner to reveal the posts via `applyPendingDigest`.
//
// If a newer fetchPendingDigest() starts while this one is still in
// flight, the stale response is dropped via `pendingFetchSeq`.
// On error, `serverMtime` is reset so the next SSE event retriggers.
function fetchPendingDigest(previousMtime) {
  pendingFetchSeq++;
  var mySeq = pendingFetchSeq;
  fetch('/api/digest').then(function(r) { return r.text(); }).then(function(html) {
    if (mySeq !== pendingFetchSeq) return;  // stale response; newer fetch in flight

    // Count how many posts are new: find the first existing post ID in
    // the new HTML; everything before it is new. If the first existing
    // post ID no longer exists in the new HTML (server truncated or
    // reordered, e.g. a new day's digest), treat it as a full reload.
    var oldIds = extractPostIds();
    var tmp = document.createElement('div');
    tmp.innerHTML = html;
    var newIds = Array.prototype.map.call(
      tmp.querySelectorAll('div[data-post-id]'),
      function(el) { return el.getAttribute('data-post-id'); }
    );
    var newCount;
    if (oldIds.length === 0) {
      newCount = newIds.length;
    } else {
      var anchorIdx = newIds.indexOf(oldIds[0]);
      newCount = anchorIdx >= 0 ? anchorIdx : newIds.length;
    }

    pendingHTML = html;
    pendingNewCount = newCount;
    showPendingBanner();
  }).catch(function() {
    if (mySeq !== pendingFetchSeq) return;  // newer fetch is active
    // Reset mtime so the next SSE event retriggers the fetch. Without
    // this, absorbServerState's update leaves us stuck -- next SSE will
    // see "no change" and skip.
    serverMtime = previousMtime;
  });
}

// Show the pending banner with the current count. Click reveals the
// pending HTML.
function showPendingBanner() {
  if (pendingNewCount <= 0) {
    // Nothing actually new (e.g. server broadcast fired but content is
    // unchanged). Drop the pending state and let updateBanner decide
    // whether the "catch up to your position" banner should show.
    pendingHTML = null;
    banner.style.display = 'none';
    updateBanner();
    return;
  }
  banner.textContent = pendingNewCount + ' new post' + (pendingNewCount > 1 ? 's' : '');
  banner.style.display = 'block';
  banner.onclick = applyPendingDigest;
}

// DOM swap helper: replace the timeline with `html`, hide the banner,
// and suppress scroll-sync during the swap. Callers decide what to do
// about scroll position afterwards.
function swapToHTML(html) {
  inProgrammaticScroll++;
  tl.innerHTML = html;
  enhanceTimeline();
  banner.style.display = 'none';
  requestAnimationFrame(function() {
    requestAnimationFrame(function() { inProgrammaticScroll--; });
  });
}

// Local reveal: user clicked the banner on THIS device. Swap in the
// pending HTML, scroll to top, and POST the new top as the server
// position so other devices see the reveal and sync their own DOM.
function applyPendingDigest() {
  if (pendingHTML === null) return;
  var html = pendingHTML;
  pendingHTML = null;
  pendingNewCount = 0;
  swapToHTML(html);
  window.scrollTo(0, 0);
  var ids = extractPostIds();
  if (ids.length > 0) {
    var anchor = { postId: ids[0], fraction: 0 };
    postAnchor(anchor);
    // Update dedup key so the next scroll handler doesn't re-POST
    // the same anchor via sendAnchor().
    lastSentKey = anchorKey(anchor);
  }
}

// Remote-reveal fallback: another client revealed but we don't have
// pendingHTML cached (the mtime-change SSE event hadn't arrived, or its
// fetch failed). Fetch fresh and apply immediately.
//
// Bumping `pendingFetchSeq` invalidates any in-flight `fetchPendingDigest`
// so its late-arriving response doesn't spuriously re-show the banner
// after we've already revealed.
function fetchAndApply() {
  pendingFetchSeq++;
  fetch('/api/digest').then(function(r) { return r.text(); }).then(function(html) {
    pendingHTML = null;
    pendingNewCount = 0;
    swapToHTML(html);
    // After the DOM swap, match the server's scroll position if the
    // user is idle. Active users stay where they are.
    if (serverPosition && !isUserActive() && !viewportMatchesServer()) {
      applyScrollThrottled(serverPosition, serverFraction);
    }
  }).catch(function() {});
}

// Apply video thumbnails, show-more, image lightbox to the timeline.
function enhanceTimeline() {
  try {
    tl.querySelectorAll('video').forEach(function(vid) {
      var src = vid.getAttribute('data-src') || vid.getAttribute('src') || '';
      var poster = vid.getAttribute('poster') || '';
      if (poster && src && !vid.dataset.enhanced) {
        vid.dataset.enhanced = '1';
        var thumb = document.createElement('div');
        thumb.className = 'video-thumb';
        thumb.innerHTML = '<img src="' + poster + '"><div class="play-btn"></div>';
        thumb.onclick = function() {
          var w = thumb.querySelector('img').offsetWidth;
          var v = document.createElement('video');
          v.src = src; v.poster = poster; v.controls = true;
          v.playsInline = true; v.autoplay = true;
          v.style.width = w + 'px'; v.style.borderRadius = '16px';
          v.style.marginTop = '12px';
          thumb.replaceWith(v);
        };
        vid.replaceWith(thumb);
      }
    });
    tl.querySelectorAll('div[data-post-id]').forEach(function(post) {
      var bodyDivs = post.querySelectorAll('div[style*="font-size:15px"], div[style*="line-height:1.5"]');
      bodyDivs.forEach(function(body) {
        if (!body.dataset.enhanced && body.scrollHeight > 250) {
          body.dataset.enhanced = '1';
          body.classList.add('post-body', 'clipped');
          var link = document.createElement('div');
          link.className = 'show-more';
          link.textContent = 'Show more';
          link.onclick = function() {
            if (body.classList.contains('clipped')) {
              body.classList.remove('clipped');
              link.textContent = 'Show less';
            } else {
              body.classList.add('clipped');
              link.textContent = 'Show more';
            }
          };
          body.parentNode.insertBefore(link, body.nextSibling);
        }
      });
    });
  } catch(e) { console.error('enhance error:', e); }
}

// --- Outgoing position updates ---
// The server is the single writer -- it assigns a version and broadcasts.

// Send a single anchor to the server. One job: HTTP POST.
function postAnchor(anchor) {
  if (!anchor.postId) return;
  fetch('/api/position', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      lastSeenPostId: anchor.postId,
      lastSeenFraction: anchor.fraction
    })
  }).catch(function() {});
}

// Two anchors are effectively the same if they're in the same post and
// within ~1% of each other in fraction. Used to dedup scroll events that
// don't meaningfully change position.
function anchorKey(anchor) {
  return anchor.postId + ':' + Math.round(anchor.fraction * 100);
}

// Creates a throttled function that calls `fn` at most once per `interval` ms.
// Trailing calls are deferred so the final value wins.
function throttle(fn, interval) {
  var timer = null;
  var lastCalledAt = 0;
  var pending = null;
  return function(arg) {
    pending = arg;
    var elapsed = Date.now() - lastCalledAt;
    if (elapsed >= interval) {
      lastCalledAt = Date.now();
      fn(pending);
      pending = null;
    } else if (!timer) {
      timer = setTimeout(function() {
        timer = null;
        if (pending !== null) {
          lastCalledAt = Date.now();
          fn(pending);
          pending = null;
        }
      }, interval - elapsed);
    }
  };
}

var throttledPostAnchor = throttle(postAnchor, 300);
var lastSentKey = '';

// Dedups + throttles anchor sends.
function sendAnchor(anchor) {
  var key = anchorKey(anchor);
  if (key === lastSentKey) return;
  lastSentKey = key;
  throttledPostAnchor(anchor);
}

// On scroll, capture the reading anchor and send to the server.
// Programmatic scrolls (scrollToAnchor) are ignored via the counter.
window.addEventListener('scroll', function() {
  if (inProgrammaticScroll > 0) return;
  lastUserScrollTime = Date.now();
  var anchor = findReadingAnchor();
  if (anchor.postId) sendAnchor(anchor);
  throttledCheckPrefetch();
}, { passive: true });

var throttledCheckPrefetch = throttle(checkPrefetch, 2000);

// Prefetch: when the user scrolls into the latest section, silently
// trigger a background generation so the next batch is ready when they
// finish reading. Fires once per section. Ignores programmatic scrolls
// (cross-device sync) to prevent duplicate triggers.
function checkPrefetch() {
  if (prefetchInFlight || !serverCanGenerate) return;
  var sections = tl.querySelectorAll('details.section');
  if (sections.length === 0) return;
  var latest = sections[0];

  var posts = latest.querySelectorAll('div[data-post-id]');
  if (posts.length === 0) return;
  var rect = latest.getBoundingClientRect();
  if (rect.bottom < 0 || rect.top > window.innerHeight) return;

  prefetchInFlight = true;
  fetch('/api/generate', {method: 'POST'}).then(function() {
    prefetchInFlight = false;
  }).catch(function() {
    prefetchInFlight = false;
  });
}

// Is the user actively reading right now?
function isUserActive() {
  return (Date.now() - lastUserScrollTime) < IDLE_MS;
}

// Throttled scroll: when many updates arrive (sender scrolling fast),
// coalesce to the latest target and apply at most every 80ms. If the
// user becomes active before the throttled call fires, we skip.
var applyAnchorIfIdle = throttle(function(anchor) {
  if (isUserActive()) return;
  scrollToAnchor(anchor.postId, anchor.fraction);
}, 80);

function applyScrollThrottled(postId, fraction) {
  applyAnchorIfIdle({ postId: postId, fraction: fraction });
}

// --- Incoming server state ---

// Was the server restarted since we loaded the page?
function isServerRestart(d) {
  return d.instanceId && knownInstanceId && d.instanceId !== knownInstanceId;
}

// Is this update strictly newer than what we've applied?
function isNewerState(d, mtimeChanged) {
  var v = (typeof d.version === 'number') ? d.version : -1;
  return v > localVersion || mtimeChanged;
}

// Absorb an incoming update into our local "what the server has" copy.
function absorbServerState(d) {
  serverMtime = d.mtime;
  localVersion = (typeof d.version === 'number') ? d.version : localVersion;
  serverPosition = d.lastSeenPostId || '';
  serverFraction = (typeof d.lastSeenFraction === 'number') ? d.lastSeenFraction : 0;
  if (typeof d.canGenerate === 'boolean') serverCanGenerate = d.canGenerate;
}

// Does our current viewport already match the server's anchor?
function viewportMatchesServer() {
  var here = findReadingAnchor();
  if (here.postId !== serverPosition) return false;
  return Math.abs(here.fraction - serverFraction) <= 0.02;
}

// Apply a server state update (from SSE or HTTP poll fallback).
// Strict version ordering: we only accept updates that are strictly newer
// than what we've already applied. The server is the single writer.
function applyServerState(d) {
  if (isServerRestart(d)) {
    window.location.reload();
    return;
  }

  var mtimeChanged = (d.mtime !== 0 && d.mtime !== serverMtime);
  if (!isNewerState(d, mtimeChanged)) return;

  var previousMtime = serverMtime;
  absorbServerState(d);

  if (mtimeChanged) {
    // New posts exist on the server. Fetch the new HTML and stash it
    // as pendingHTML; the user clicks the banner to reveal. Pass the
    // previous mtime so a failed fetch can roll back and retrigger.
    fetchPendingDigest(previousMtime);
    return;
  }

  // Remote reveal: if the server's position points to a post we don't
  // have in our DOM, another client has revealed new content. Apply
  // pendingHTML if we have it cached, otherwise fetch and apply.
  //
  // Assumption: "serverPosition not in DOM" unambiguously means "some
  // other client revealed content we don't yet have locally". Also
  // covers SSE reorder (mtime event arrives after its position event)
  // and day-rollover truncation -- both resolve by reloading the
  // current digest, which is the right thing. A server bug writing a
  // garbage post ID would loop here, but the server is the single
  // writer and only mutates via updatePosition / updateDigest.
  if (serverPosition && !postById(serverPosition)) {
    if (pendingHTML !== null) {
      var html = pendingHTML;
      pendingHTML = null;
      pendingNewCount = 0;
      swapToHTML(html);
      // Fall through to updateBanner + scroll sync below.
    } else {
      fetchAndApply();
      return;
    }
  }

  updateBanner();

  // Scroll to match the server unless the user is actively reading.
  if (serverPosition && !isUserActive() && !viewportMatchesServer()) {
    applyScrollThrottled(serverPosition, serverFraction);
  }
}

// Real-time sync via Server-Sent Events.
var eventSource = null;
function startEventStream() {
  if (eventSource) eventSource.close();
  eventSource = new EventSource('/api/events');
  eventSource.onmessage = function(e) {
    try { applyServerState(JSON.parse(e.data)); } catch(err) {}
  };
  eventSource.onerror = function() {
    setTimeout(startEventStream, 2000);
  };
}

// Force-fetch the server state. Used as a fallback for when SSE
// events were missed (background tab, network blip, etc.).
function forceSync() {
  fetch('/api/mtime').then(function(r) { return r.json(); }).then(function(d) {
    applyServerState(d);
  }).catch(function() {});
}

// When the tab becomes visible, immediately re-sync. Safari throttles
// SSE in background tabs, so events may have been missed.
document.addEventListener('visibilitychange', function() {
  if (document.visibilityState === 'visible') {
    forceSync();
    startEventStream();  // Reconnect SSE in case it died
  }
});

// Also force-sync when the window regains focus.
window.addEventListener('focus', forceSync);

// Throttled mouse-move sync: when the user is looking at this device
// (even without scrolling or clicking), refresh state.
var lastMouseSync = 0;
document.addEventListener('mousemove', function() {
  var now = Date.now();
  if (now - lastMouseSync > 1000) {
    lastMouseSync = now;
    forceSync();
  }
});

// Tight safety poll: catches anything SSE missed in idle background tabs.
setInterval(forceSync, 3000);

// Initial state: the server embeds the current position, fraction, version,
// and instance ID in body data-attrs. Seeding localVersion here means the
// first SSE event will be correctly compared against the snapshot we loaded.
// knownInstanceId lets us detect server restarts and auto-reload.
serverPosition = document.body.dataset.initialPosition || '';
serverFraction = parseFloat(document.body.dataset.initialFraction || '0');
if (isNaN(serverFraction)) serverFraction = 0;
knownInstanceId = document.body.dataset.instanceId || '';
localVersion = parseInt(document.body.dataset.initialVersion || '-1', 10);
if (isNaN(localVersion)) localVersion = -1;
if (serverPosition) {
  window.addEventListener('load', function() {
    scrollToAnchor(serverPosition, serverFraction);
  });
}
updateBanner();
startEventStream();
</script>
</body>
</html>
"""##
