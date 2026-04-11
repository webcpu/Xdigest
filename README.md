# Xdigest

**X's For You feed optimizes for engagement, not for you.** You scroll past noise to find a few posts that matter. Most of the good ones get lost in the flood.

**Your bookmarks are your taste.** They're the posts you actually cared about enough to save. But nothing uses them -- they just sit there.

**Xdigest closes that loop.** It fetches your feed, scores each post against your bookmarks with Claude, and gives you a short daily digest in your browser. No firehose. No doomscrolling. Just the posts you'd actually want to read.

**Read on any device.** Phone, Mac, iPad -- Xdigest keeps them all in sync. Pick up right where you left off, every time. It just works.

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

## Usage

Launch Xdigest. The **XD** wordmark appears in your menu bar (template image, adapts to light/dark/tinted menu bar). Click it:

- **Generate Digest** -- fetches your feed, scores with Claude, updates the reader
- **Open Reader** -- opens `http://localhost:8408` in your browser
- **Check for Updates...** -- queries GitHub for a newer release
- **Quit**

Or click the refresh button in the reader. When new posts are generated, a blue "N new posts" banner appears at the top -- click to reveal them.

**Launching Xdigest opens today's reader automatically.** If today's digest already has posts, the reader opens immediately. Otherwise Xdigest runs the pipeline first, then opens when done.

### Access from iPhone/iPad

**On the same Wi-Fi as your Mac**: open Safari on your iPhone or iPad and go to `http://your-mac.local:8408`.

**Not on the same Wi-Fi? Use [Tailscale](https://tailscale.com/).** Install it on your Mac and your iOS device, then use your Mac's Tailscale name: `http://your-mac-name:8408`. The reader works from anywhere -- your couch, a coffee shop, another country. No port forwarding, no public exposure, no dynamic DNS.

On first launch, macOS will ask whether Xdigest can accept incoming connections. **Click Allow** -- otherwise nothing (LAN or Tailscale) can reach the reader. If you click Deny by mistake, Xdigest detects it and shows a setup window with a link to fix it.

**Reveal state syncs across devices** in real time: click the "N new posts" banner on one device and the others catch up automatically.

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

## Privacy

Xdigest runs entirely on your Mac. Your feed, bookmarks, and scores never leave your machine. The only external calls are:

- `bird` fetching from x.com (your own account)
- `claude` scoring posts (your own subscription)
- Video proxy streaming from `video.twimg.com`

No analytics, no telemetry, no accounts.

## License

MIT
