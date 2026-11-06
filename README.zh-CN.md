# MenuBarLyrics

[English](README.md)

一个很小的 macOS 菜单栏歌词工具，主要面向 Apple Music 和系统 Now Playing。

MenuBarLyrics 会显示当前一句歌词，并用轻量的绿色覆盖效果显示大致进度。可以放在菜单栏里，也可以切换成独立悬浮窗；悬浮时菜单栏只保留一个小音符图标，给刘海屏腾出空间。

![菜单栏歌词模拟截图](docs/screenshots/apple-music-menubar.png)

![中文歌词模拟截图](docs/screenshots/netease-menubar.png)

## 功能

- 原生 macOS 菜单栏应用，没有 Dock 图标。
- 可选悬浮歌词：拖动左侧把手移动，点击歌词展开播放控制，点减号收起。
- 支持上一首、播放/暂停、下一首，控制对象与当前显示的播放信息保持一致。
- 记住显示模式、收起状态和窗口位置；切换显示器后可从菜单重置位置。
- 启动歌词工具时不主动打开 Music.app，只有手动选择菜单里的 Open Apple Music 才会打开。
- 通过 Music.app 自动化读取 Apple Music 当前播放信息。
- 通过系统 Now Playing / MediaRemote 获取当前播放信息。
- 网易云音乐在系统播放时间戳稳定时可 best-effort 支持。
- 优先从 LRCLIB 获取同步歌词，中文歌可回退到网易云歌词接口。
- 菜单里可调整歌词偏移、显示宽度和刷新率。
- 歌词会缓存在本机 Application Support 目录。
- 开启系统“减少动态效果”后显示静态歌词，不滚动文字或逐字变色。

## 悬浮歌词怎么用

点击菜单栏图标，选择 **Floating Lyrics (Notch-friendly)**。窗口首次出现在菜单栏下方，位于屏幕可用区域内，避开刘海。拖动左侧把手可以换位置或移动到其他显示器。显示窗口不会主动切走当前应用。

点击歌词展开或收起 **上一首 / 播放或暂停 / 下一首**。没有当前歌曲时按钮不可用；只有手动点击才会发送播放命令，控制不可用时会显示原因。

点减号可以把窗口收回菜单栏。再从音符图标的菜单选择 **Show Floating Lyrics** 恢复，或重新打开应用找回已收起的窗口；选择 **Reset Floating Position** 把窗口移回当前屏幕，选择 **Menu Bar Lyrics** 切回原来的菜单栏歌词。原用户保持原显示方式，需要时自行切换。

## 当前限制

这个工具刻意保持很小，所以有几个限制需要提前说清楚：

- 大多数歌词源只提供逐句 LRC 时间，不是真正逐字时间轴。绿色覆盖是基于当前句子的平滑模拟。
- 网易云音乐不总是向 macOS 暴露可靠的播放进度。进度不可靠时，应用会避免显示误导性的歌词。
- 应用通过 helper 读取 macOS 私有 MediaRemote 信息，更适合作为个人工具，而不是 App Store 风格的软件。
- 当前构建后的 app 需要系统里存在 `/usr/bin/swift`，用于执行 Now Playing helper。
- 系统播放控制使用私有 MediaRemote API，取决于播放器的支持情况；接口接受命令不代表每个播放器都会实际执行。

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

运行 `./scripts/test.sh` 进行本地回归检查。运行 `./scripts/test.sh --preview` 可打开带有明确测试标记的示例歌词界面，用于检查交互，不会控制真实播放器。

## 权限

读取 Apple Music 时，macOS 可能会请求允许 MenuBarLyrics 控制 Music.app。这个权限用于读取当前歌曲和播放进度，以及响应手动点击的播放控制。Music.app 关闭时，轮询和播放按钮都不会主动打开它。

MenuBarLyrics 不需要登录，也不会保存任何音乐账号凭据。

## 隐私

应用会读取当前歌曲名、歌手、专辑、时长和播放进度，并用这些信息查询公开歌词服务。获取到的歌词会缓存在本机：

```text
~/Library/Application Support/MenuBarLyrics/lyrics-cache.json
```

仓库里的截图是模拟图，不包含真实桌面、账号或工作空间信息。

## 为什么做这个

MenuBarLyrics 只显示当前一句歌词和工作时需要的几个播放控制。根据屏幕空间选择菜单栏或小悬浮窗，不用来回切换播放器窗口。

## 免责声明

本项目与 Apple、网易云音乐、LRCLIB 或任何音乐服务都没有关联。歌词可用性和时间轴准确度取决于第三方歌词源。

## License

MIT
