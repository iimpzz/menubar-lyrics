import AppKit

private final class LyricsDragHandle: NSImageView {
    private var dragOffset: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragOffset = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragOffset else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragOffset = nil
        (window as? FloatingLyricsPanel)?.fitOnScreen()
        window?.saveFrame(usingName: "FloatingLyrics")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

final class FloatingLyricsPanel: NSPanel {
    var onHide: (() -> Void)?
    var onCommand: ((PlaybackCommand) -> Void)?

    private let lyricButton = NSButton(title: "♪", target: nil, action: nil)
    private let previousButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let detailsLabel = NSTextField(labelWithString: "Start playback in your music player")
    private let controls = NSStackView()
    private(set) var controlsExpanded = false
    private var trackName = ""
    private var trackKey: String?
    private var commandMessage: String?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Floating Lyrics"
        identifier = NSUserInterfaceItemIdentifier("FloatingLyrics")
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        let handle = LyricsDragHandle()
        handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Move floating lyrics")
        handle.contentTintColor = .secondaryLabelColor
        handle.toolTip = "Drag to move floating lyrics"
        handle.setAccessibilityLabel("Move floating lyrics")
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.widthAnchor.constraint(equalToConstant: 20).isActive = true
        handle.heightAnchor.constraint(equalToConstant: 28).isActive = true

        lyricButton.isBordered = false
        lyricButton.target = self
        lyricButton.action = #selector(toggleControls)
        lyricButton.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        lyricButton.cell?.lineBreakMode = .byTruncatingTail
        lyricButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lyricButton.setAccessibilityHelp("Click to show or hide playback controls")
        lyricButton.identifier = NSUserInterfaceItemIdentifier("TogglePlaybackControls")

        let hideButton = NSButton()
        configure(hideButton, symbol: "minus", label: "Hide floating lyrics", action: #selector(hideLyrics))
        hideButton.keyEquivalent = "\u{1b}"
        hideButton.keyEquivalentModifierMask = []

        let row = NSStackView(views: [handle, lyricButton, hideButton])
        row.spacing = 6
        row.alignment = .centerY
        lyricButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        hideButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true

        configure(previousButton, symbol: "backward.end.fill", label: "Previous track", action: #selector(previousTrack))
        configure(playPauseButton, symbol: "play.fill", label: "Play", action: #selector(togglePlayback))
        configure(nextButton, symbol: "forward.end.fill", label: "Next track", action: #selector(nextTrack))
        playPauseButton.keyEquivalent = " "
        playPauseButton.keyEquivalentModifierMask = []
        let buttons = NSStackView(views: [previousButton, playPauseButton, nextButton])
        buttons.spacing = 20
        buttons.alignment = .centerY
        [previousButton, playPauseButton, nextButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: 32).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }

        detailsLabel.font = .systemFont(ofSize: 11)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.alignment = .center
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controls.orientation = .vertical
        controls.alignment = .centerX
        controls.spacing = 6
        controls.addArrangedSubview(buttons)
        controls.addArrangedSubview(detailsLabel)
        controls.isHidden = true

        let stack = NSStackView(views: [row, controls])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailsLabel.widthAnchor.constraint(lessThanOrEqualTo: controls.widthAnchor)
        ])
        updatePlayback(nil)
        updateTitle(NSAttributedString(string: "Start playback in your music player", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]))

        if !setFrameUsingName("FloatingLyrics") { resetPosition() }
        setFrameAutosaveName("FloatingLyrics")
        resizeForControls()
    }

    func updateTitle(_ title: NSAttributedString) {
        let displayTitle = NSMutableAttributedString(attributedString: title)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        displayTitle.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: displayTitle.length))
        lyricButton.attributedTitle = displayTitle
        lyricButton.toolTip = "\(title.string)\nClick for playback controls · Drag the handle to move"
        lyricButton.setAccessibilityLabel(title.string)
    }

    func updatePlayback(_ track: TrackSnapshot?) {
        if track?.key != trackKey { commandMessage = nil }
        trackKey = track?.key
        trackName = track?.displayName ?? "Start playback in your music player"
        [previousButton, playPauseButton, nextButton].forEach { $0.isEnabled = track != nil }
        let playing = track?.isPlaying == true
        playPauseButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: playing ? "Pause" : "Play")
        playPauseButton.setAccessibilityLabel(playing ? "Pause" : "Play")
        playPauseButton.toolTip = playing ? "Pause" : "Play"
        updateDetails()
    }

    func showMessage(_ message: String?) {
        commandMessage = message
        updateDetails()
    }

    func show() {
        fitOnScreen()
        orderFrontRegardless()
    }

    func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.maxY - frame.height - 12))
        fitOnScreen()
    }

    func fitOnScreen() {
        let screens = NSScreen.screens
        let screen = screens.max { lhs, rhs in
            let left = frame.intersection(lhs.visibleFrame)
            let right = frame.intersection(rhs.visibleFrame)
            return left.width * left.height < right.width * right.height
        }
        guard let screen else { return }
        let area = screen.visibleFrame
        let overlaps = screens.contains { frame.intersects($0.visibleFrame) }
        let targetArea = overlaps ? area : (NSScreen.main ?? screen).visibleFrame
        setFrame(Self.fittedFrame(frame, in: targetArea), display: true)
    }

    static func fittedFrame(_ frame: NSRect, in area: NSRect) -> NSRect {
        let width = min(440, area.width)
        let height = min(frame.height, area.height)
        return NSRect(
            x: min(max(frame.minX, area.minX), area.maxX - width),
            y: min(max(frame.minY, area.minY), area.maxY - height),
            width: width,
            height: height
        )
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateDetails() {
        detailsLabel.stringValue = commandMessage ?? trackName
        detailsLabel.toolTip = detailsLabel.stringValue
        detailsLabel.textColor = commandMessage == nil ? .secondaryLabelColor : .systemOrange
    }

    private func resizeForControls() {
        let height: CGFloat = controlsExpanded ? 112 : 52
        // Keep the lyric row fixed and expand downward, without animation.
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
        fitOnScreen()
    }

    @objc func toggleControls() {
        controlsExpanded.toggle()
        controls.isHidden = !controlsExpanded
        resizeForControls()
    }

    @objc private func hideLyrics() { onHide?() }
    @objc private func previousTrack() { onCommand?(.previous) }
    @objc private func togglePlayback() { onCommand?(.togglePlayPause) }
    @objc private func nextTrack() { onCommand?(.next) }
}
