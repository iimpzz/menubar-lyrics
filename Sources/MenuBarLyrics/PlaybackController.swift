import AppKit
import Darwin

enum PlaybackCommand: Int32 {
    case togglePlayPause = 2
    case next = 4
    case previous = 5

    var appleScript: String {
        switch self {
        case .togglePlayPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }
}

enum PlaybackControlError: LocalizedError {
    case noPlayer
    case unavailable
    case automation(String)

    var errorDescription: String? {
        switch self {
        case .noPlayer: return "Start playback in your music player first."
        case .unavailable: return "This player did not accept the command. Use its own playback controls."
        case .automation(let message): return message
        }
    }
}

final class PlaybackController {
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    private let mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)

    deinit {
        if let mediaRemote { dlclose(mediaRemote) }
    }

    func send(_ command: PlaybackCommand, for track: TrackSnapshot?) throws {
        guard let track else { throw PlaybackControlError.noPlayer }
        switch track.source {
        case .appleMusic:
            // Never address a closed Music.app: AppleScript can otherwise launch it.
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
                throw PlaybackControlError.noPlayer
            }
            let source = """
            if application id "com.apple.Music" is not running then error "Music is not running."
            tell application id "com.apple.Music" to \(command.appleScript)
            """
            guard let script = NSAppleScript(source: source) else { throw PlaybackControlError.unavailable }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                throw PlaybackControlError.automation(
                    errorInfo[NSAppleScript.errorMessage] as? String ?? "Allow Music Automation in System Settings."
                )
            }
        case .system:
            guard let mediaRemote, let symbol = dlsym(mediaRemote, "MRMediaRemoteSendCommand") else {
                throw PlaybackControlError.unavailable
            }
            let sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
            guard sendCommand(command.rawValue, nil) else { throw PlaybackControlError.unavailable }
        }
    }
}
