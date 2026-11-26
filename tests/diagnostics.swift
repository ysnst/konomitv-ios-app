import Foundation

@main
struct DiagnosticsChecks {
    static func main() throws {
        let state: [String: Any] = [
            "time": 1_800_000_000_000.0, "paused": true, "ended": false, "hidden": false,
            "readyState": 2, "networkState": 2, "position": 100.0, "rate": 1.0,
            "bufferAhead": 0.25, "error": 0, "pip": "inline", "audioState": "interrupted", "audioType": "playback"
        ]
        let valid: [String: Any] = ["type": "mediaDiagnostic", "event": "pause", "state": state]
        precondition(PlaybackDiagnostics.recordWebMessage(valid))
        for event in ["background-audio-attempt", "background-audio-started", "background-audio-rejected"] {
            var message = valid
            message["event"] = event
            precondition(PlaybackDiagnostics.recordWebMessage(message))
        }
        // 診断経路をURL・Cookie・自由文のログ出力口として使わせない。
        var invalid = valid
        invalid["url"] = "https://private.invalid/?token=secret"
        precondition(!PlaybackDiagnostics.recordWebMessage(invalid))
        invalid = valid
        invalid["event"] = "private-token"
        precondition(!PlaybackDiagnostics.recordWebMessage(invalid))
        for (key, value) in [("position", Double.nan as Any), ("rate", Double.infinity as Any), ("paused", 1 as Any), ("pip", "private-url" as Any)] {
            var invalidState = state
            invalidState[key] = value
            invalid = valid
            invalid["state"] = invalidState
            precondition(!PlaybackDiagnostics.recordWebMessage(invalid))
        }
        var invalidState = state
        invalidState["cookie"] = "secret"
        invalid = valid
        invalid["state"] = invalidState
        precondition(!PlaybackDiagnostics.recordWebMessage(invalid))
        for index in 0..<350 { PlaybackDiagnostics.record("test", ["index": index]) }
        let data = try PlaybackDiagnostics.snapshot(version: "test", systemVersion: "test")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let events = json["events"] as! [[String: Any]]
        precondition(events.count == 300)
        precondition((events.last?["values"] as? [String: Int])?["index"] == 349)
        precondition(!String(data: data, encoding: .utf8)!.contains("secret"))
        print("PASS diagnostics schema, privacy rejection and bounded retention")
    }
}
