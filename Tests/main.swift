import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else {
        fputs("FAIL: \(description)\n", stderr)
        exit(1)
    }
    passed += 1
    print("PASS: \(description)")
}

func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

let safeArea = NSRect(x: 0, y: 70, width: 1512, height: 874)
let offscreen = NSRect(x: -3000, y: 2400, width: 440, height: 112)
check(safeArea.contains(FloatingLyricsPanel.fittedFrame(offscreen, in: safeArea)), "Disconnected display position returns inside visible area")
let secondaryArea = NSRect(x: -1920, y: -600, width: 1920, height: 1050)
check(secondaryArea.contains(FloatingLyricsPanel.fittedFrame(offscreen, in: secondaryArea)), "Negative-coordinate display uses its own bounds")
let narrowArea = NSRect(x: 20, y: 30, width: 320, height: 600)
check(FloatingLyricsPanel.fittedFrame(offscreen, in: narrowArea).width == 320, "Panel fits a narrow display")
check(FloatingLyricsPanel.fittedFrame(offscreen, in: safeArea).maxY <= safeArea.maxY, "Panel stays below the menu bar and camera housing")

let panel = FloatingLyricsPanel()
panel.resetPosition()
let views = descendants(of: panel.contentView!)
let buttons = views.compactMap { $0 as? NSButton }
let playbackButtons = buttons.filter { ["Previous track", "Play", "Next track"].contains($0.toolTip ?? "") }
check(playbackButtons.count == 3, "All three native playback buttons exist")
check(playbackButtons.allSatisfy { !$0.isEnabled }, "Playback controls are disabled without an active track")
let top = panel.frame.maxY
panel.toggleControls()
check(panel.controlsExpanded && panel.frame.height == 112, "Click expansion opens the control row")
check(abs(panel.frame.maxY - top) < 0.1, "Expansion keeps the lyric row in place")
panel.toggleControls()
check(!panel.controlsExpanded && panel.frame.height == 52, "Second click restores the compact lyric row")
check(panel.styleMask.contains(.nonactivatingPanel) && panel.hidesOnDeactivate == false, "Floating lyrics stay visible without activating the app")

let handle = views.first { $0.toolTip == "Drag to move floating lyrics" }!
let beforeDrag = panel.frame.origin
func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                      windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                      clickCount: 1, pressure: 1)!
}
handle.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 26)))
handle.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: -80, y: -54)))
check(panel.frame.origin == NSPoint(x: beforeDrag.x - 100, y: beforeDrag.y - 80), "Dragging the handle moves the window by the pointer displacement")
handle.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 20, y: 26)))
check(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) }, "Releasing a drag leaves the complete panel on a visible display")

var sample = TrackSnapshot(state: "playing", position: 12, name: "UI Test — sample text", artist: "MenuBarLyrics", album: "", duration: 180)
panel.updatePlayback(sample)
check(playbackButtons.allSatisfy { $0.isEnabled }, "An active track enables playback controls")
check(playbackButtons.contains { $0.toolTip == "Pause" }, "Playing state exposes Pause")
sample.state = "paused"
panel.updatePlayback(sample)
check(playbackButtons.contains { $0.toolTip == "Play" }, "Paused state exposes Play")
panel.showMessage("Player unavailable — test message")
panel.updatePlayback(sample)
check(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Player unavailable — test message" }, "Command errors survive normal metadata polling")
sample.name = "A different test track"
panel.updatePlayback(sample)
check(!views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Player unavailable — test message" }, "A new track clears the previous command error")

let unicodeTitle = NSAttributedString(string: "工作时瞄一眼，歌词在这里 ♪ 😀 👨‍👩‍👧‍👦 " + String(repeating: "很长的示例文字 ", count: 12), attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: NSColor.white
])
panel.updateTitle(unicodeTitle)
let lyricButton = buttons.first { $0.identifier?.rawValue == "TogglePlaybackControls" }!
check(lyricButton.attributedTitle.string == unicodeTitle.string, "Unicode and long titles retain their full accessible text")
check(lyricButton.cell?.lineBreakMode == .byTruncatingTail, "Long text truncates within the floating panel")

let musicWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
let controller = PlaybackController()
do {
    try controller.send(.togglePlayPause, for: nil)
    check(false, "No-player command should fail")
} catch PlaybackControlError.noPlayer {
    check(true, "No-player command returns a useful error")
}
if !musicWasRunning {
    let reader = MusicReader()
    let closedMusicTrack = try reader?.read()
    check(closedMusicTrack == nil, "Polling a closed Music.app returns no track")
    sample.source = .appleMusic
    for command in [PlaybackCommand.previous, .togglePlayPause, .next] {
        do {
            try controller.send(command, for: sample)
            check(false, "A closed Music.app must not receive commands")
        } catch PlaybackControlError.noPlayer {
            check(true, "Closed Music.app rejects command \(command)")
        }
    }
    check(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty, "Neither polling nor playback commands launch Music.app")
} else {
    print("SKIP: Music.app is already running; no-launch checks require it to be closed.")
}

UserDefaults.standard.set(false, forKey: "floatingLyricsEnabled")
UserDefaults.standard.set(false, forKey: "floatingLyricsHidden")
let appDelegate = MenuBarLyricsApp()
let emojiLine = "A😀B👨‍👩‍👧‍👦C"
let coloredEmoji = appDelegate.attributedLyric(line: emojiLine, progressCharIndex: 2, reduceMotion: false)
check(coloredEmoji.length == emojiLine.utf16.count, "Karaoke formatting preserves complete Unicode characters")
check(coloredEmoji.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == .systemGreen,
      "The complete emoji uses the sung color")
check(coloredEmoji.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor != .systemGreen,
      "The character after the sung emoji retains its unsung color")
let longLine = String(repeating: "减少动态效果测试文字", count: 20)
let stillTitle = appDelegate.attributedLyric(line: longLine, progressCharIndex: 2, reduceMotion: true)
let laterStillTitle = appDelegate.attributedLyric(line: longLine, progressCharIndex: 120, reduceMotion: true)
check(stillTitle.isEqual(to: laterStillTitle), "Reduce Motion keeps text and color static as playback progresses")
appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
let appPanel = app.windows.compactMap { $0 as? FloatingLyricsPanel }.first { $0 !== panel }!
_ = appDelegate.perform(NSSelectorFromString("useFloatingLyrics"))
check(appPanel.isVisible && UserDefaults.standard.bool(forKey: "floatingLyricsEnabled"), "Choosing floating mode shows the panel and saves the mode")
_ = appDelegate.perform(NSSelectorFromString("toggleFloatingVisibility"))
check(!appPanel.isVisible && UserDefaults.standard.bool(forKey: "floatingLyricsHidden"), "Hiding lyrics removes the window and saves the hidden state")
_ = appDelegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
check(appPanel.isVisible && !UserDefaults.standard.bool(forKey: "floatingLyricsHidden"), "Reopening the app recovers hidden floating lyrics")
_ = appDelegate.perform(NSSelectorFromString("useMenuBarLyrics"))
check(!appPanel.isVisible && !UserDefaults.standard.bool(forKey: "floatingLyricsEnabled"), "Switching back restores menu bar mode and hides the panel")
appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

print("\(passed) checks passed.")

if CommandLine.arguments.contains("--preview") {
    sample.source = .system
    sample.name = "UI Test — sample text"
    sample.state = "playing"
    panel.updatePlayback(sample)
    panel.updateTitle(unicodeTitle)
    panel.onCommand = { command in
        if command == .togglePlayPause {
            sample.state = sample.isPlaying ? "paused" : "playing"
            panel.updatePlayback(sample)
        }
        panel.showMessage("UI test received: \(command)")
    }
    panel.onHide = { app.terminate(nil) }
    panel.resetPosition()
    panel.show()
    app.run()
}
