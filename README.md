# Xdigest

A macOS menu bar app that filters your X (Twitter) For You feed for high-signal posts using your bookmarks as taste signal.

**How it works:** Your bookmarks define your taste. Xdigest fetches your feed, asks Claude to score each post against your bookmarks, and surfaces the best matches in a local reader.

## Requirements

- macOS 15+
- [Claude Code](https://claude.ai/code) with active subscription
- [bird](https://github.com/nicebyte/bird) CLI (`brew install steipete/tap/bird`)

## Install

```bash
git clone https://github.com/webcpu/Xdigest.git
cd Xdigest
swift build -c release
cp .build/release/Xdigest /usr/local/bin/
```

## Usage

Launch the app:

```bash
Xdigest
```

A menu bar icon appears (magnifying glass). Click it to:

- **Generate Digest** -- fetches your feed, scores with Claude, shows results
- **Open Reader** -- opens the reader at `http://localhost:8408`
- **Quit**

Or click the blue refresh button in the reader to generate directly.

### Access from iPhone/iPad

The reader is accessible from any device on the same network. Open Safari on your iPhone or iPad and go to `http://your-mac.local:8408`.

## Architecture

Data-centric, layered, Unix-style pipeline. Each module does one thing.

```
BirdService -> ScorerService -> DigestService -> ServerService -> Browser
     |               |               |               |
  [Tweet]      [ScoredPost]      [Digest]        [HTML]
```

- **XdigestCore** -- shared data types and error handling
- **BirdService** -- fetches and normalizes tweets from bird CLI
- **ScorerService** -- scores tweets against bookmarks using Claude
- **DigestService** -- assembles scored posts into a digest with dedup
- **ServerService** -- HTTP server with HTML reader
- **Pipeline** -- orchestrates the flow with retry and caching

## Features

- Bookmark-based taste matching via Claude Opus
- Tag-based search (Claude generates tags at scoring time)
- Cross-run dedup (won't show the same post twice)
- Repost detection (shows original author)
- Video playback via local proxy
- Foldable timestamp sections
- Hot reload (polls for new posts)
- Responsive (works on Mac, iPhone, iPad)
- Per-day digest files (scales to years of use)

## License

MIT
