# MenuBarLyrics

[中文说明](README.zh-CN.md)

A tiny macOS menu bar lyrics display for Apple Music and system Now Playing.

MenuBarLyrics keeps one current lyric line in the menu bar, with a lightweight green progress overlay so you can follow music while working without keeping a full lyrics window open.

![Menu bar lyrics mock screenshot](docs/screenshots/apple-music-menubar.png)

![Chinese lyrics mock screenshot](docs/screenshots/netease-menubar.png)

## Features

- Native macOS menu bar app, no Dock icon.
- Apple Music support through Music.app automation.
- System Now Playing support through MediaRemote probing.
- Best-effort NetEase Cloud Music support when its Now Playing timestamp is stable.
- Synced lyric lookup from LRCLIB, with NetEase lyric fallback for Chinese songs.
- Adjustable lyric offset, width, and refresh rate from the menu.
- Small local cache under Application Support.

## Current Limits

MenuBarLyrics is intentionally small, and there are a few honest limitations:

- Most lyric sources provide line-level LRC timing, not true per-word timing. The green progress is a smooth simulation across the current line.
- NetEase Cloud Music does not always expose a reliable playback position to macOS. When progress is unreliable, the app avoids showing misleading lyrics.
- The app uses macOS private MediaRemote information through a helper script, so this is a personal utility rather than App Store-style software.
- A built app currently expects `/usr/bin/swift` to be available for the Now Playing helper.

## Build

Requirements:

- macOS 13 or later
- Xcode Command Line Tools

Build the app:

```sh
./scripts/build.sh
```

The app and zip archive will be written to `dist/`.

Run it:

```sh
open dist/MenuBarLyrics.app
```

## Permissions

For Apple Music, macOS may ask for permission to let MenuBarLyrics control Music.app. This is used only to read the current track and playback position when system Now Playing is not enough.

MenuBarLyrics does not require a login and does not store music account credentials.

## Privacy

The app reads the current track title, artist, album, duration, and playback position. It uses those fields to query public lyric services and stores fetched lyrics locally in:

```text
~/Library/Application Support/MenuBarLyrics/lyrics-cache.json
```

Screenshots in this repository are mock images and do not contain a real desktop, account, or workspace.

## Why

Most lyrics apps are full windows, floating panels, or feature-rich players. This one is deliberately boring: one line in the menu bar, enough timing to stay oriented, and as little UI as possible.

## Disclaimer

This project is not affiliated with Apple, NetEase Cloud Music, LRCLIB, or any music service. Lyrics availability and timing quality depend on third-party sources.

## License

MIT
