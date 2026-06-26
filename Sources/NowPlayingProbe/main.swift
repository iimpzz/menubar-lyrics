import Foundation
import Dispatch
import Darwin

typealias MRNowPlayingInfoBlock = @convention(block) (CFDictionary?) -> Void
typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping MRNowPlayingInfoBlock) -> Void

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW),
      let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
    exit(1)
}

let getNowPlayingInfo = unsafeBitCast(symbol, to: MRGetNowPlayingInfo.self)
let semaphore = DispatchSemaphore(value: 0)
var output = ""

getNowPlayingInfo(DispatchQueue.global(qos: .userInitiated)) { dictionary in
    defer { semaphore.signal() }
    guard let info = dictionary as? [String: Any],
          let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
          !title.isEmpty else {
        return
    }

    let separator = "\u{1F}"
    let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
    let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
    let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
    let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
    let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
    let timestamp = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)?.timeIntervalSince1970 ?? 0

    output = [
        title,
        artist,
        album,
        String(duration),
        String(elapsed),
        String(rate),
        String(timestamp)
    ].joined(separator: separator)
}

let result = semaphore.wait(timeout: .now() + .milliseconds(350))
if result == .success, !output.isEmpty {
    print(output)
    exit(0)
}

exit(2)
