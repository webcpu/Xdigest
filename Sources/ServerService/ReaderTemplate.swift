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
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
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
h1 { font-size: 2.5rem; font-weight: 600; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, sans-serif; color: #f5f5f7; letter-spacing: -0.03em; margin-bottom: 4px; }
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
#banner { display: none; background: rgba(29,155,240,0.95); color: #fff; text-align: center; padding: 10px; cursor: pointer; font-size: 14px; font-weight: 600; border-radius: 8px; margin: 8px 0; }
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
<body>
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
  fetch('/api/generate', {method: 'POST'}).then(function(r) { return r.json(); }).then(function(d) {
    btn.classList.remove('loading');
    btn.title = 'Generate more';
    if (d.picks > 0) {
      banner.textContent = d.picks + ' new post' + (d.picks > 1 ? 's' : '');
      banner.style.display = 'block';
      banner.onclick = function() {
        banner.textContent = 'Loading...';
        loadNewPosts(d.picks);
      };
    } else {
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

var lastMtime = 0;
var lastPostCount = 0;
lastPostCount = (tl.innerHTML.match(/\/status\//g) || []).length;

function loadNewPosts(newCount) {
  fetch('/api/digest').then(function(r) { return r.text(); }).then(function(html) {
    var existingIds = new Set();
    tl.querySelectorAll('a').forEach(function(a) {
      var href = a.getAttribute('href') || '';
      var m = href.match(/status\/(\d+)/);
      if (m) existingIds.add(m[1]);
    });
    var chunks = html.split(/(?=<details class="section")/);
    var newChunks = [];
    for (var i = 0; i < chunks.length; i++) {
      var chunk = chunks[i].trim();
      if (!chunk) continue;
      var ids = chunk.match(/status\/(\d+)/g) || [];
      var allExist = ids.length > 0 && ids.every(function(id) {
        return existingIds.has(id.replace('status/', ''));
      });
      if (!allExist && ids.length > 0) {
        newChunks.push(chunk);
      }
    }
    if (newChunks.length === 0) {
      banner.style.display = 'none';
      return;
    }
    var newHtml = newChunks.join('\n');
    var temp = document.createElement('div');
    temp.innerHTML = newHtml;
    temp.querySelectorAll('video').forEach(function(vid) {
      var src = vid.getAttribute('data-src') || vid.getAttribute('src') || '';
      var poster = vid.getAttribute('poster') || '';
      if (poster && src) {
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
    temp.querySelectorAll('div[style*="display:flex"]').forEach(function(post) {
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
    tl.querySelectorAll('details.section[open]').forEach(function(d) {
      d.removeAttribute('open');
    });
    tl.insertBefore(temp, tl.firstChild);
    var newSections = temp.querySelectorAll('details.section');
    for (var s = 0; s < newSections.length; s++) {
      if (s < newSections.length - 1) {
        newSections[s].removeAttribute('open');
      }
    }
    lastPostCount = (tl.innerHTML.match(/\/status\//g) || []).length;
    banner.style.display = 'none';
    lastMtime = Date.now() / 1000;
    window.scrollTo(0, 0);
  }).catch(function(e) {
    banner.textContent = 'Error: ' + e.message;
  });
}

setInterval(function() {
  fetch('/api/mtime').then(function(r) { return r.json(); }).then(function(d) {
    if (lastMtime === 0) {
      lastMtime = d.mtime;
      lastPostCount = d.postCount;
    } else if (d.mtime > lastMtime) {
      var newCount = d.postCount - lastPostCount;
      lastMtime = d.mtime;
      if (newCount > 0) {
        banner.textContent = newCount + ' new post' + (newCount > 1 ? 's' : '');
      } else {
        banner.textContent = 'New posts available';
      }
      banner.style.display = 'block';
      banner.onclick = function() {
        banner.textContent = 'Loading...';
        loadNewPosts(newCount);
      };
    }
  }).catch(function() {});
}, 10000);
</script>
</body>
</html>
"""##
