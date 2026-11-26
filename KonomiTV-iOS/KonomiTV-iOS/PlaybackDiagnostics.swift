import CoreFoundation
import Foundation

/// 実機での停止順序を調べるための限定ログ。URL・番組名・Cookie・エラー本文は受け取らない。
enum PlaybackDiagnostics {
    private static var entries: [[String: Any]] = []
    private static let events: Set<String> = [
        "play", "playing", "pause", "waiting", "stalled", "ratechange", "error", "emptied",
        "loadedmetadata", "enterpictureinpicture", "leavepictureinpicture",
        "webkitpresentationmodechanged", "visibilitychange", "pagehide", "snapshot",
        "background-audio-attempt", "background-audio-started", "background-audio-rejected"
    ]

    static func record(_ event: String, _ values: [String: Any] = [:]) {
        entries.append(["receivedAt": Date().timeIntervalSince1970, "event": event, "values": values])
        // 直近の操作だけを保持し、長時間視聴でもメモリを増やし続けない。
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }

    @discardableResult
    static func recordWebMessage(_ message: [String: Any]) -> Bool {
        guard Set(message.keys) == ["type", "event", "state"],
              message["type"] as? String == "mediaDiagnostic",
              let event = message["event"] as? String, events.contains(event),
              let state = message["state"] as? [String: Any],
              Set(state.keys) == ["time", "paused", "ended", "hidden", "readyState", "networkState", "position", "rate", "bufferAhead", "error", "pip", "audioState", "audioType"] else { return false }
        for key in ["paused", "ended", "hidden"] {
            guard let value = state[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        }
        let ranges: [String: ClosedRange<Double>] = [
            "time": 0...1e15, "readyState": 0...4, "networkState": 0...3,
            "position": 0...1e10, "rate": 0...16, "bufferAhead": 0...1e10, "error": 0...4
        ]
        for (key, range) in ranges {
            guard let value = state[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, range.contains(value.doubleValue) else { return false }
        }
        guard let pip = state["pip"] as? String, ["inline", "picture-in-picture", "fullscreen", "unknown"].contains(pip),
              let audioState = state["audioState"] as? String, ["active", "inactive", "interrupted", "unknown"].contains(audioState),
              let audioType = state["audioType"] as? String, ["auto", "playback", "transient", "transient-solo", "ambient", "play-and-record", "unknown"].contains(audioType) else { return false }
        record("web.\(event)", state)
        return true
    }

    static func snapshot(version: String, systemVersion: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "format": 1, "version": version, "systemVersion": systemVersion, "events": entries
        ], options: [.prettyPrinted, .sortedKeys])
    }
}
