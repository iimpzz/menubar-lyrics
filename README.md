# MenuBarLyrics

[中文说明](README.zh-CN.md)

A tiny macOS lyrics display for Apple Music and system Now Playing, in the menu bar or a floating panel.

MenuBarLyrics keeps one current lyric line visible, with a lightweight green progress overlay so you can follow music while working without keeping a full lyrics window open. The optional floating mode leaves only a small music icon in the menu bar, making room on Macs with a camera housing.

![Menu bar lyrics mock screenshot](docs/screenshots/apple-music-menubar.png)

![Chinese lyrics mock screenshot](docs/screenshots/netease-menubar.png)

## Features

- Native macOS menu bar app, no Dock icon.
- Optional floating lyrics: drag the handle to move, click the lyric to expand playback controls, and use the minus button to hide.
- Previous, play/pause, and next controls follow the displayed player.
- Display mode, hidden state, and floating position survive relaunch. Reset the position from the menu after changing displays.
- Starting MenuBarLyrics never intentionally opens Music.app. Opening Apple Music remains an explicit menu action.
- Apple Music support through Music.app automation.
- System Now Playing support through MediaRemote probing.
- Best-effort NetEase Cloud Music support when its Now Playing timestamp is stable.
- Synced lyric lookup from LRCLIB, with NetEase lyric fallback for Chinese songs.
- Adjustable lyric offset, width, and refresh rate from the menu.
- Small local cache under Application Support.
- Respects Reduce Motion with a static lyric line instead of moving karaoke text.

## Floating lyrics

Click the menu bar item and choose **Floating Lyrics (Notch-friendly)**. The panel initially appears just below the menu bar, inside the screen's visible area rather than across the camera housing. Drag its left handle to move it to another position or display. It stays above ordinary windows without activating the app when shown.

Click the lyric to show or hide **Previous / Play or Pause / Next**. The buttons are disabled until a player provides a current track. Playback controls send commands only when clicked; unavailable controls show an explanation rather than opening a player.

The minus button hides the panel. Choose **Show Floating Lyrics** from the music icon to restore it, reopen the app to recover a hidden panel, use **Reset Floating Position** to bring it back to the current screen, or choose **Menu Bar Lyrics** to return to the original display. Existing users keep menu bar mode until they choose floating mode.

## Current Limits

MenuBarLyrics is intentionally small, and there are a few honest limitations:

- Most lyric sources provide line-level LRC timing, not true per-word timing. The green progress is a smooth simulation across the current line.
- NetEase Cloud Music does not always expose a reliable playback position to macOS. When progress is unreliable, the app avoids showing misleading lyrics.
- The app uses macOS private MediaRemote information through a helper script, so this is a personal utility rather than App Store-style software.
- A built app currently expects `/usr/bin/swift` to be available for the Now Playing helper.
- System playback commands use private MediaRemote APIs and depend on the active player's support. Accepting a command does not guarantee that a particular player will act on it.

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

Run the native regression checks with `./scripts/test.sh`. `./scripts/test.sh --preview` opens the floating UI with clearly labeled sample text for manual interaction checks; it does not control a real player.

## Permissions

For Apple Music, macOS may ask for permission to let MenuBarLyrics control Music.app. This reads the current track and playback position when system Now Playing is not enough, and handles playback commands when you click a control. If Music.app is closed, polling and playback controls leave it closed.

MenuBarLyrics does not require a login and does not store music account credentials.

## Privacy

The app reads the current track title, artist, album, duration, and playback position. It uses those fields to query public lyric services and stores fetched lyrics locally in:

```text
~/Library/Application Support/MenuBarLyrics/lyrics-cache.json
```

Screenshots in this repository are mock images and do not contain a real desktop, account, or workspace.

## Why

This app keeps a single lyric line and only the controls needed while working. Choose the menu bar or a small floating panel according to the space on your screen.

## Disclaimer

This project is not affiliated with Apple, NetEase Cloud Music, LRCLIB, or any music service. Lyrics availability and timing quality depend on third-party sources.

## License

MIT
