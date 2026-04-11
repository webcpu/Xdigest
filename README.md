# Xdigest

A macOS menu bar app that filters your X (Twitter) For You feed for high-signal posts using your bookmarks as taste signal.

**How it works:** Your bookmarks define your taste. Xdigest fetches your feed, asks Claude to score each post against your bookmarks, and surfaces the best matches in a local reader.

## Requirements

- macOS 15+
- [Claude Code](https://code.claude.com/docs/en/setup) -- install it, then run `claude` and use `/login` to sign in with your subscription (not API key)
- [bird](https://github.com/steipete/bird) CLI (`brew install steipete/tap/bird`)
- **Logged into X (Twitter) in Safari, Chrome, or Firefox** -- bird reads browser cookies

> **Note:** If you added x.com to your dock as a web app, it has isolated cookies that bird can't read. Log in through the browser's regular window instead.

Xdigest checks all requirements on launch and shows a setup window telling you exactly what's missing and how to fix it. You don't need to configure anything manually.

## Install

### Download the DMG (easiest)

Grab the latest release from [Releases](https://github.com/webcpu/Xdigest/releases), open the DMG, drag Xdigest to Applications.

### Build from source

```bash
git clone https://github.com/webcpu/Xdigest.git
cd Xdigest
swift build -c release
./.build/release/Xdigest
```

Or build the DMG:

```bash
./scripts/make-dmg.sh
```

## Usage

Launch Xdigest. The **XD** wordmark appears in your menu bar (template image, adapts to light/dark/tinted menu bar). Click it:

- **Generate Digest** -- fetches your feed, scores with Claude, updates the reader
- **Open Reader** -- opens `http://localhost:8408` in your browser
- **Check for Updates...** -- queries GitHub for a newer release
- **Quit**

Or click the refresh button in the reader. When new posts are generated, a blue "N new posts" banner appears at the top -- click to reveal them.

**Launching Xdigest opens today's reader automatically.** If today's digest already has posts, the reader opens immediately. Otherwise Xdigest runs the pipeline first, then opens when done.

### Access from iPhone/iPad

The reader is accessible from any device on the same network. Open Safari on your iPhone or iPad and go to `http://your-mac.local:8408`.

On first launch, macOS will ask whether Xdigest can accept incoming connections. **Click Allow** -- otherwise iPhone/iPad can't reach the reader. If you click Deny by mistake, Xdigest detects this and shows a setup window with a link to fix it.

**Reveal state is synced across devices**: when you click the "N new posts" banner on one device, the others catch up automatically. Section open/closed state is local for now.

## Architecture

Data-centric, layered, Unix-style pipeline. Each module does one thing.

```
BirdService -> ScorerService -> DigestService -> ServerService -> Browser
     |               |               |               |
  [Tweet]      [ScoredPost]      [Digest]        [HTML]
```

- **XdigestCore** -- shared data types, typed errors, process runner
- **BirdService** -- fetches and normalizes tweets from bird CLI
- **ScorerService** -- scores tweets against bookmarks using Claude
- **DigestService** -- assembles scored posts into a digest with dedup
- **ServerService** -- HTTP server with HTML reader and video proxy
- **Pipeline** -- orchestrates the flow with retry and caching
- **Updater** -- checks GitHub Releases for newer versions (reusable as a standalone SPM target)

## Features

- Bookmark-based taste matching via Claude Opus
- Tag-based search (Claude generates tags at scoring time)
- Cross-run dedup (won't show the same post twice)
- Repost detection (shows original author)
- Video playback via local proxy (no CORS issues)
- Foldable timestamp sections
- Real-time cross-device sync via Server-Sent Events
- Auto-open on launch -- goes straight to today's digest
- Single-instance policy (latest launch wins)
- Built-in update checker (notifies when a new release is available)
- Responsive (works on Mac, iPhone, iPad)
- Per-day digest files (scales to years of use)
- Setup check on launch (guides users through missing requirements)

## Privacy

Xdigest runs entirely on your Mac. Your feed, bookmarks, and scores never leave your machine. The only external calls are:

- `bird` fetching from x.com (your own account)
- `claude` scoring posts (your own subscription)
- Video proxy streaming from `video.twimg.com`

No analytics, no telemetry, no accounts.

## License

MIT
