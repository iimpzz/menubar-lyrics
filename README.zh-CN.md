# MenuBarLyrics

[English](README.md)

一个很小的 macOS 菜单栏歌词工具，主要面向 Apple Music 和系统 Now Playing。

MenuBarLyrics 会把当前歌词放在菜单栏里，并用轻量的绿色覆盖效果显示大致进度。它适合工作时瞄一眼歌词，不需要一直打开完整歌词窗口。

![菜单栏歌词模拟截图](docs/screenshots/apple-music-menubar.png)

![中文歌词模拟截图](docs/screenshots/netease-menubar.png)

## 功能

- 原生 macOS 菜单栏应用，没有 Dock 图标。
- 通过 Music.app 自动化读取 Apple Music 当前播放信息。
- 通过系统 Now Playing / MediaRemote 获取当前播放信息。
- 网易云音乐在系统播放时间戳稳定时可 best-effort 支持。
- 优先从 LRCLIB 获取同步歌词，中文歌可回退到网易云歌词接口。
- 菜单里可调整歌词偏移、显示宽度和刷新率。
- 歌词会缓存在本机 Application Support 目录。

## 当前限制

这个工具刻意保持很小，所以有几个限制需要提前说清楚：

- 大多数歌词源只提供逐句 LRC 时间，不是真正逐字时间轴。绿色覆盖是基于当前句子的平滑模拟。
- 网易云音乐不总是向 macOS 暴露可靠的播放进度。进度不可靠时，应用会避免显示误导性的歌词。
- 应用通过 helper 读取 macOS 私有 MediaRemote 信息，更适合作为个人工具，而不是 App Store 风格的软件。
- 当前构建后的 app 需要系统里存在 `/usr/bin/swift`，用于执行 Now Playing helper。

## 构建

需要：

- macOS 13 或更新版本
- Xcode Command Line Tools

构建：

```sh
./scripts/build.sh
```

构建产物会输出到 `dist/`。

运行：

```sh
open dist/MenuBarLyrics.app
```

## 权限

读取 Apple Music 时，macOS 可能会请求允许 MenuBarLyrics 控制 Music.app。这个权限只用于读取当前歌曲和播放进度。

MenuBarLyrics 不需要登录，也不会保存任何音乐账号凭据。

## 隐私

应用会读取当前歌曲名、歌手、专辑、时长和播放进度，并用这些信息查询公开歌词服务。获取到的歌词会缓存在本机：

```text
~/Library/Application Support/MenuBarLyrics/lyrics-cache.json
```

仓库里的截图是模拟图，不包含真实桌面、账号或工作空间信息。

## 为什么做这个

很多歌词软件会做成完整窗口、悬浮窗或播放器。MenuBarLyrics 只想解决一个很小的问题：把当前歌词安静地放在菜单栏里，让你工作时不用切窗口也能跟上。

## 免责声明

本项目与 Apple、网易云音乐、LRCLIB 或任何音乐服务都没有关联。歌词可用性和时间轴准确度取决于第三方歌词源。

## License

MIT
