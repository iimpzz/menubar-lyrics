import AppKit
import Foundation

struct TrackSnapshot: Equatable {
    var state: String
    var position: TimeInterval
    var name: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var positionIsReliable: Bool = true

    var isPlaying: Bool {
        state.lowercased() == "playing"
    }

    var key: String {
        [
            artist.normalizedKey,
            name.normalizedKey,
            album.normalizedKey,
            String(Int(duration.rounded()))
        ].joined(separator: "|")
    }

    var displayName: String {
        if artist.isEmpty { return name }
        return "\(name) - \(artist)"
    }
}

struct RawNowPlaying {
    var name: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var rate: TimeInterval
    var timestamp: TimeInterval

    var key: String {
        [
            artist.normalizedKey,
            name.normalizedKey,
            album.normalizedKey,
            String(Int(duration.rounded()))
        ].joined(separator: "|")
    }
}

struct LyricLine: Codable {
    var time: TimeInterval
    var text: String
}

struct CachedLyrics: Codable {
    var lines: [LyricLine]
    var fetchedAt: Date
}

struct LRCLibResponse: Decodable {
    var trackName: String?
    var name: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?
}

struct NetEaseSearchResponse: Decodable {
    var result: Result?

    struct Result: Decodable {
        var songs: [Song]?
    }

    struct Song: Decodable {
        var name: String
        var id: Int
        var duration: Int?
        var album: Album?
        var artists: [Artist]?
    }

    struct Album: Decodable {
        var name: String?
    }

    struct Artist: Decodable {
        var name: String?
    }
}

struct NetEaseLyricsResponse: Decodable {
    var lrc: Lyric?

    struct Lyric: Decodable {
        var lyric: String?
    }
}

final class MusicReader {
    private let script: NSAppleScript

    init?() {
        let source = """
        if application id "com.apple.Music" is not running then return ""
        set sep to ASCII character 31
        tell application "Music"
            try
                if player state is playing or player state is paused then
                    set trackName to name of current track as text
                    set trackArtist to artist of current track as text
                    set trackAlbum to album of current track as text
                    set trackDuration to duration of current track
                    set trackPosition to player position
                    set trackState to player state as text
                    return trackState & sep & trackPosition & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & trackDuration
                end if
            on error
                return ""
            end try
        end tell
        return ""
        """
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        self.script = script
    }

    func read() throws -> TrackSnapshot? {
        // AppleScript would launch Music when querying it if it is not running.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw NSError(domain: "MenuBarLyrics.MusicReader", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let output = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count >= 6,
              let position = TimeInterval(parts[1]),
              let duration = TimeInterval(parts[5]) else {
            return nil
        }

        return TrackSnapshot(
            state: parts[0],
            position: position,
            name: parts[2],
            artist: parts[3],
            album: parts[4],
            duration: duration
        )
    }
}

final class NowPlayingReader {
    private var latestSnapshot: TrackSnapshot?
    private var lastProbeDate = Date.distantPast
    private let minimumProbeInterval: TimeInterval = 1.0
    private let helperURL: URL?
    private var refreshInFlight = false
    private var freshZeroProgressKey: String?
    private var freshZeroProgressFirstSeen = Date.distantPast
    private let unreliableProgressGrace: TimeInterval = 2.5

    init() {
        helperURL = Bundle.main.resourceURL?.appendingPathComponent("NowPlayingProbe.swift")
    }

    func read() -> TrackSnapshot? {
        if Date().timeIntervalSince(lastProbeDate) >= minimumProbeInterval {
            refreshFromHelper()
        }
        return latestSnapshot
    }

    private func refreshFromHelper() {
        lastProbeDate = Date()
        guard let helperURL,
              FileManager.default.fileExists(atPath: helperURL.path),
              !refreshInFlight else {
            return
        }
        refreshInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let rawNowPlaying = self?.runHelper(at: helperURL)
            DispatchQueue.main.async {
                self?.latestSnapshot = rawNowPlaying.flatMap { self?.snapshot(from: $0) }
                self?.refreshInFlight = false
            }
        }
    }

    private func runHelper(at helperURL: URL) -> RawNowPlaying? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [helperURL.path]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count >= 7,
              let duration = TimeInterval(parts[3]),
              let elapsed = TimeInterval(parts[4]),
              let rate = TimeInterval(parts[5]),
              let timestamp = TimeInterval(parts[6]) else {
            return nil
        }

        return RawNowPlaying(
            name: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: duration,
            elapsed: elapsed,
            rate: rate,
            timestamp: timestamp
        )
    }

    private func snapshot(from raw: RawNowPlaying) -> TrackSnapshot {
        let now = Date()
        let timestampDelta = raw.timestamp > 0 ? max(0, now.timeIntervalSince1970 - raw.timestamp) : 0
        let projectedPosition = raw.rate > 0 ? raw.elapsed + timestampDelta * raw.rate : raw.elapsed
        let hasFreshZeroProgress = raw.rate > 0 && raw.elapsed <= 0.05 && timestampDelta < 1.5

        if hasFreshZeroProgress {
            if freshZeroProgressKey != raw.key {
                freshZeroProgressKey = raw.key
                freshZeroProgressFirstSeen = now
            }
        } else {
            freshZeroProgressKey = nil
            freshZeroProgressFirstSeen = Date.distantPast
        }

        let positionIsReliable = !hasFreshZeroProgress
            || now.timeIntervalSince(freshZeroProgressFirstSeen) < unreliableProgressGrace

        return TrackSnapshot(
            state: raw.rate > 0 ? "playing" : "paused",
            position: max(0, projectedPosition),
            name: raw.name,
            artist: raw.artist,
            album: raw.album,
            duration: raw.duration,
            positionIsReliable: positionIsReliable
        )
    }
}

final class LyricsCache {
    private let cacheURL: URL
    private var storage: [String: CachedLyrics] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MenuBarLyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("lyrics-cache.json")
        load()
    }

    func lyrics(for key: String) -> [LyricLine]? {
        storage[key]?.lines
    }

    func save(_ lines: [LyricLine], for key: String) {
        guard !lines.isEmpty else { return }
        storage[key] = CachedLyrics(lines: lines, fetchedAt: Date())
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CachedLyrics].self, from: data) else {
            return
        }
        storage = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

final class LyricsService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "MenuBarLyrics/0.1 (local macOS menu bar lyric tool)"
        ]
        session = URLSession(configuration: config)
    }

    func fetchLyrics(for track: TrackSnapshot) async -> [LyricLine] {
        if let exact = await fetchExact(track), !exact.isEmpty {
            return exact
        }
        if let searched = await search(track), !searched.isEmpty {
            return searched
        }
        if let netEase = await fetchNetEase(track), !netEase.isEmpty {
            return netEase
        }
        return []
    }

    private func fetchExact(_ track: TrackSnapshot) async -> [LyricLine]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/get"
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]

        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            guard decoded.instrumental != true,
                  let synced = decoded.syncedLyrics,
                  !synced.isEmpty else {
                return nil
            }
            return parseLRC(synced)
        } catch {
            return nil
        }
    }

    private func search(_ track: TrackSnapshot) async -> [LyricLine]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]

        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
            let best = bestMatch(in: results, track: track)
            guard best?.instrumental != true,
                  let synced = best?.syncedLyrics,
                  !synced.isEmpty else {
                return nil
            }
            return parseLRC(synced)
        } catch {
            return nil
        }
    }

    private func bestMatch(in results: [LRCLibResponse], track: TrackSnapshot) -> LRCLibResponse? {
        let targetTitle = track.name.normalizedKey
        let targetArtist = track.artist.normalizedKey
        let exact = results.first { result in
            (result.trackName ?? result.name ?? "").normalizedKey == targetTitle
                && (result.artistName ?? "").normalizedKey == targetArtist
                && result.syncedLyrics?.isEmpty == false
        }
        if let exact { return exact }

        let titleOnly = results.first { result in
            (result.trackName ?? result.name ?? "").normalizedKey == targetTitle
                && result.syncedLyrics?.isEmpty == false
        }
        return titleOnly ?? results.first { $0.syncedLyrics?.isEmpty == false }
    }

    private func fetchNetEase(_ track: TrackSnapshot) async -> [LyricLine]? {
        var components = URLComponents(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/search")
        components?.queryItems = [
            URLQueryItem(name: "keywords", value: "\(track.name) \(track.artist)"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
            guard let songs = decoded.result?.songs else { return nil }
            let candidates = songs.filter { isLikelyNetEaseMatch($0, track: track) }

            for song in candidates {
                guard let lines = await fetchNetEaseLyrics(songID: song.id), !lines.isEmpty else {
                    continue
                }
                return lines
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchNetEaseLyrics(songID: Int) async -> [LyricLine]? {
        var components = URLComponents(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric")
        components?.queryItems = [URLQueryItem(name: "id", value: String(songID))]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(NetEaseLyricsResponse.self, from: data)
            guard let raw = decoded.lrc?.lyric else { return nil }
            let lines = parseLRC(unescapeHTMLEntities(raw))
                .filter { !isCreditLine($0.text) }
            if lines.count <= 1 || lines.last?.time == 0 {
                return nil
            }
            return lines
        } catch {
            return nil
        }
    }

    private func isLikelyNetEaseMatch(_ song: NetEaseSearchResponse.Song, track: TrackSnapshot) -> Bool {
        let songName = song.name.normalizedKey
        let artistName = song.artists?.first?.name?.normalizedKey ?? ""
        let albumName = song.album?.name?.normalizedKey ?? ""
        let titleMatch = songName == track.name.normalizedKey || songName.contains(track.name.normalizedKey) || track.name.normalizedKey.contains(songName)
        let artistMatch = artistName == track.artist.normalizedKey || artistName.contains(track.artist.normalizedKey) || track.artist.normalizedKey.contains(artistName)
        let albumMatch = !albumName.isEmpty && !track.album.normalizedKey.isEmpty && (albumName == track.album.normalizedKey || albumName.contains(track.album.normalizedKey) || track.album.normalizedKey.contains(albumName))
        let durationMatch: Bool
        if let duration = song.duration {
            durationMatch = abs(Double(duration) / 1000.0 - track.duration) <= 3.0
        } else {
            durationMatch = false
        }
        return titleMatch && (artistMatch || albumMatch || durationMatch)
    }

    private func unescapeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "\\\n", with: "\n")
    }

    private func isCreditLine(_ text: String) -> Bool {
        let prefixes = ["作词", "作曲", "编曲", "制作人", "监制", "词", "曲", "OP", "SP"]
        return prefixes.contains { text.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
    }

    private func parseLRC(_ input: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rows = input
            .replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .newlines)

        for row in rows {
            let timestamps = timestamps(in: row)
            guard !timestamps.isEmpty else { continue }

            var text = row.replacingOccurrences(of: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"<\d{1,2}:\d{2}(?:\.\d{1,3})?>"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for time in timestamps {
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    private func timestamps(in row: String) -> [TimeInterval] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(row.startIndex..<row.endIndex, in: row)
        return regex.matches(in: row, range: nsRange).compactMap { match in
            guard let minuteRange = Range(match.range(at: 1), in: row),
                  let secondRange = Range(match.range(at: 2), in: row) else {
                return nil
            }
            let minutes = TimeInterval(row[minuteRange]) ?? 0
            let seconds = TimeInterval(row[secondRange]) ?? 0
            var fraction: TimeInterval = 0
            if let fractionRange = Range(match.range(at: 3), in: row) {
                let raw = String(row[fractionRange])
                fraction = (TimeInterval(raw) ?? 0) / pow(10, TimeInterval(raw.count))
            }
            return minutes * 60 + seconds + fraction
        }
    }
}

final class MenuBarLyricsApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reader = MusicReader()
    private let nowPlayingReader = NowPlayingReader()
    private let lyricsService = LyricsService()
    private let cache = LyricsCache()

    private var currentTrack: TrackSnapshot?
    private var lastPollDate = Date()
    private var lastKnownPosition: TimeInterval = 0
    private var lyrics: [LyricLine] = []
    private var loadingKey: String?
    private var isLoading = false
    private var offset: TimeInterval = UserDefaults.standard.object(forKey: "offsetSeconds") as? TimeInterval ?? 0.5
    private var maxCharacters: Int = UserDefaults.standard.object(forKey: "maxCharacters") as? Int ?? 66
    private var framesPerSecond: Int = UserDefaults.standard.object(forKey: "framesPerSecond") as? Int ?? 60
    private var lastRenderedToken = ""
    private var renderedTrackKey = ""
    private var renderedLineIndex = -1
    private var renderedCharIndex = 0
    private var renderTimer: Timer?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        installMusicNotificationObserver()
        pollMusic()
        startTimers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureStatusItem() {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        applyTitle(plainTitle("♪"))
        statusItem.button?.toolTip = "MenuBarLyrics"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "MenuBarLyrics", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let offsetTitle = NSMenuItem(title: offsetText(), action: nil, keyEquivalent: "")
        offsetTitle.tag = 1001
        menu.addItem(offsetTitle)
        menu.addItem(NSMenuItem(title: "Offset +0.1s", action: #selector(increaseOffset), keyEquivalent: "]"))
        menu.addItem(NSMenuItem(title: "Offset -0.1s", action: #selector(decreaseOffset), keyEquivalent: "["))
        menu.addItem(NSMenuItem(title: "Reset Offset to +0.5s", action: #selector(resetOffset), keyEquivalent: "0"))
        menu.addItem(NSMenuItem.separator())

        let fpsTitle = NSMenuItem(title: "60 FPS", action: #selector(setFPS60), keyEquivalent: "6")
        fpsTitle.tag = 2001
        menu.addItem(fpsTitle)
        menu.addItem(NSMenuItem(title: "30 FPS", action: #selector(setFPS30), keyEquivalent: "3"))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Width 48", action: #selector(width48), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Width 66", action: #selector(width66), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Width 84", action: #selector(width84), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Refresh Lyrics", action: #selector(refreshLyrics), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Apple Music", action: #selector(openMusic), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func installMusicNotificationObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged(_:)),
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
    }

    private func startTimers() {
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / TimeInterval(framesPerSecond), repeats: true) { [weak self] _ in
            self?.render()
        }
        RunLoop.main.add(renderTimer!, forMode: .common)

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.pollMusic()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        pollMusic()
    }

    private func pollMusic() {
        do {
            guard let snapshot = try readPreferredSnapshot() else {
                currentTrack = nil
                lyrics = []
                setStatusText("♪", token: "idle")
                return
            }

            let previousTrack = currentTrack
            let trackChanged = snapshot.key != previousTrack?.key
            updatePlayhead(with: snapshot, trackChanged: trackChanged)
            currentTrack = snapshot

            guard snapshot.positionIsReliable else {
                lyrics = []
                isLoading = false
                loadingKey = nil
                setStatusText("播放器未提供进度", token: "unreliable-progress-\(snapshot.key)")
                return
            }

            if trackChanged {
                lyrics = []
                resetRenderProgress()
                loadLyrics(for: snapshot)
            }
        } catch {
            setStatusText("Allow Music Automation", token: "automation-error")
        }
    }

    private func updatePlayhead(with snapshot: TrackSnapshot, trackChanged: Bool) {
        let now = Date()
        defer { lastPollDate = now }

        guard snapshot.positionIsReliable else {
            lastKnownPosition = snapshot.position
            return
        }

        guard !trackChanged, currentTrack?.isPlaying == true, snapshot.isPlaying else {
            lastKnownPosition = snapshot.position
            resetRenderProgress()
            return
        }

        let predicted = baseEstimatedPosition(at: now)
        let drift = snapshot.position - predicted
        if abs(drift) > 1.2 {
            lastKnownPosition = snapshot.position
            resetRenderProgress()
        } else if abs(drift) > 0.12 {
            lastKnownPosition = predicted + drift * 0.12
        } else {
            lastKnownPosition = predicted
        }
    }

    private func readPreferredSnapshot() throws -> TrackSnapshot? {
        let nowPlaying = nowPlayingReader.read()
        if nowPlaying?.isPlaying == true && nowPlaying?.positionIsReliable == true {
            return nowPlaying
        }

        if let appleMusic = try reader?.read(), appleMusic.isPlaying {
            return appleMusic
        }

        if nowPlaying?.isPlaying == true {
            return nowPlaying
        }

        if let nowPlaying {
            return nowPlaying
        }
        return try reader?.read()
    }

    private func loadLyrics(for track: TrackSnapshot) {
        let key = track.key
        if let cached = cache.lyrics(for: key), !cached.isEmpty {
            lyrics = cached
            return
        }

        guard loadingKey != key else { return }
        loadingKey = key
        isLoading = true
        setStatusText("Finding lyrics...", token: "loading-\(key)")

        Task {
            let fetched = await lyricsService.fetchLyrics(for: track)
            await MainActor.run {
                self.isLoading = false
                guard self.currentTrack?.key == key else { return }
                self.lyrics = fetched
                self.cache.save(fetched, for: key)
                self.lastRenderedToken = ""
                if fetched.isEmpty {
                    self.setStatusText(track.displayName, token: "no-lyrics-\(key)")
                }
            }
        }
    }

    private func estimatedPosition() -> TimeInterval {
        baseEstimatedPosition() + offset
    }

    private func baseEstimatedPosition(at date: Date = Date()) -> TimeInterval {
        guard currentTrack?.isPlaying == true else {
            return lastKnownPosition
        }
        return lastKnownPosition + date.timeIntervalSince(lastPollDate)
    }

    private func render() {
        guard let track = currentTrack else { return }
        guard !lyrics.isEmpty else {
            if !isLoading {
                setStatusText(track.displayName, token: "fallback-\(track.key)")
            }
            return
        }

        let position = estimatedPosition()
        var state = lyricState(at: position)
        stabilizeRenderState(&state, trackKey: track.key)
        let token = "\(track.key)|\(state.index)|\(state.charIndex)|\(track.isPlaying)|\(offset)|\(maxCharacters)"
        guard token != lastRenderedToken else { return }
        lastRenderedToken = token
        applyTitle(attributedLyric(
            line: state.line.text,
            progressCharIndex: state.charIndex
        ))
    }

    private func stabilizeRenderState(_ state: inout (line: LyricLine, index: Int, charIndex: Int), trackKey: String) {
        if renderedTrackKey != trackKey || renderedLineIndex != state.index {
            renderedTrackKey = trackKey
            renderedLineIndex = state.index
            renderedCharIndex = state.charIndex
            return
        }

        state.charIndex = max(state.charIndex, renderedCharIndex)
        renderedCharIndex = state.charIndex
    }

    private func resetRenderProgress() {
        lastRenderedToken = ""
        renderedTrackKey = ""
        renderedLineIndex = -1
        renderedCharIndex = 0
    }

    private func lyricState(at position: TimeInterval) -> (line: LyricLine, index: Int, charIndex: Int) {
        var index = 0
        if let match = lyrics.lastIndex(where: { $0.time <= position }) {
            index = match
        }

        let line = lyrics[index]
        let nextTime: TimeInterval
        if index + 1 < lyrics.count {
            nextTime = max(lyrics[index + 1].time, line.time + 0.4)
        } else {
            nextTime = max(line.time + 4.0, currentTrack?.duration ?? line.time + 4.0)
        }

        let duration = max(nextTime - line.time, 0.35)
        let progress = min(max((position - line.time) / duration, 0), 1)
        let characters = Array(line.text)
        let charIndex = min(max(Int((Double(max(characters.count, 1)) * progress).rounded(.down)), 0), characters.count)
        return (line, index, charIndex)
    }

    private func attributedLyric(line: String, progressCharIndex: Int) -> NSAttributedString {
        let window = visibleWindow(for: line, progressCharIndex: progressCharIndex)
        let visible = Array(window.text)
        let progress = max(0, min(progressCharIndex - window.sourceStart + window.prefixCount, visible.count))

        let result = NSMutableAttributedString(
            string: window.text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )

        let sungColor = NSColor.systemGreen
        let restColor = NSColor.white.withAlphaComponent(0.58)

        if !visible.isEmpty {
            result.addAttribute(.foregroundColor, value: restColor, range: NSRange(location: 0, length: visible.count))
            if progress > 0 {
                result.addAttribute(.foregroundColor, value: sungColor, range: NSRange(location: 0, length: progress))
            }
        }

        return result
    }

    private func visibleWindow(for text: String, progressCharIndex: Int) -> (text: String, sourceStart: Int, prefixCount: Int) {
        let chars = Array(text)
        guard chars.count > maxCharacters else {
            return (text, 0, 0)
        }

        let bodyMax = max(maxCharacters - 2, 12)
        var start = max(0, progressCharIndex - bodyMax / 2)
        var end = min(chars.count, start + bodyMax)
        if end - start < bodyMax {
            start = max(0, end - bodyMax)
        }
        end = min(chars.count, start + bodyMax)

        var visible = String(chars[start..<end])
        var prefixCount = 0
        if start > 0 {
            visible = "…" + visible
            prefixCount = 1
        }
        if end < chars.count {
            visible += "…"
        }
        return (visible, start, prefixCount)
    }

    private func setStatusText(_ text: String, token: String) {
        guard token != lastRenderedToken else { return }
        lastRenderedToken = token
        applyTitle(plainTitle(truncate(text, max: maxCharacters)))
    }

    private func plainTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ]
        )
    }

    private func applyTitle(_ title: NSAttributedString) {
        statusItem.button?.title = title.string
        statusItem.button?.attributedTitle = title
        statusItem.length = NSStatusItem.variableLength
    }

    private func truncate(_ text: String, max: Int) -> String {
        let chars = Array(text)
        guard chars.count > max else { return text }
        return String(chars.prefix(max - 1)) + "…"
    }

    private func savePreferences() {
        UserDefaults.standard.set(offset, forKey: "offsetSeconds")
        UserDefaults.standard.set(maxCharacters, forKey: "maxCharacters")
        UserDefaults.standard.set(framesPerSecond, forKey: "framesPerSecond")
        refreshMenuTitles()
    }

    private func refreshMenuTitles() {
        statusItem.menu?.item(withTag: 1001)?.title = offsetText()
        statusItem.menu?.item(withTag: 2001)?.title = "\(framesPerSecond) FPS"
    }

    private func offsetText() -> String {
        String(format: "Offset: %+.1fs", offset)
    }

    @objc private func increaseOffset() {
        offset = min(offset + 0.1, 3.0)
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func decreaseOffset() {
        offset = max(offset - 0.1, -3.0)
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func resetOffset() {
        offset = 0.5
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func setFPS60() {
        framesPerSecond = 60
        savePreferences()
        startTimers()
    }

    @objc private func setFPS30() {
        framesPerSecond = 30
        savePreferences()
        startTimers()
    }

    @objc private func width48() {
        maxCharacters = 48
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func width66() {
        maxCharacters = 66
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func width84() {
        maxCharacters = 84
        savePreferences()
        lastRenderedToken = ""
    }

    @objc private func refreshLyrics() {
        guard let track = currentTrack else { return }
        lyrics = []
        loadingKey = nil
        loadLyrics(for: track)
    }

    @objc private func openMusic() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension String {
    var normalizedKey: String {
        lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]"#, with: "", options: .regularExpression)
    }
}

let app = NSApplication.shared
let delegate = MenuBarLyricsApp()
app.delegate = delegate
app.run()
