import Foundation

@main struct StoreTests {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try LocalStore(directory: base)
        precondition(store.state.threshold == 100)
        try store.setThreshold(1)
        try store.setThreshold(100)
        try store.setThreshold(73)
        let first = try store.save(nickname: " 玩家 ", v0: 150, stopTime: 8)
        precondition(first["score"] as? Int == 2813)
        let lower = try store.save(nickname: "玩家", v0: 150, stopTime: 10)
        precondition(lower["best"] as? Int == 2813)
        _ = try store.save(nickname: "第一名", v0: 200, stopTime: 5)
        let loaded = try LocalStore(directory: base)
        precondition(loaded.state.threshold == 73)
        precondition(loaded.state.nickname == "第一名")
        precondition(loaded.state.scores.count == 3)
        let rows = loaded.leaderboard()
        precondition(rows.count == 2 && rows[0]["nickname"] as? String == "第一名")
        precondition(rows[1]["score"] as? Int == 2813)
        precondition(rows[1]["threshold"] as? Int == 73)
        for invalid in [0, 101, -1] {
            do { try loaded.setThreshold(invalid); fatalError("Accepted invalid threshold") }
            catch StoreError.invalidSettings {}
        }
        for (name, speed, time) in [("", 150.0, 5.0), ("ok", .nan, 5.0),
            ("ok", 150.0, 0.0), ("ok", 150.0, .infinity), ("ok", 99.0, 5.0),
            ("ok", 261.0, 5.0), ("1234567890123", 150.0, 5.0)] {
            do { _ = try loaded.save(nickname: name, v0: speed, stopTime: time); fatalError("Accepted invalid score") }
            catch StoreError.invalidScore {}
        }
        let blocked = base.appendingPathComponent("file-not-directory")
        try Data("blocked".utf8).write(to: blocked)
        let failing = try LocalStore(directory: blocked)
        do { try failing.setThreshold(80); fatalError("Write should fail") } catch {}
        precondition(failing.state.threshold == 100, "Failed writes must not update memory")
        for oldThreshold in [50, 73] {
            let legacy = base.appendingPathComponent("legacy-\(oldThreshold)")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            var old = loaded.state
            old.version = 1
            old.threshold = oldThreshold
            try JSONEncoder().encode(old).write(to: legacy.appendingPathComponent("state.json"))
            let upgraded = try LocalStore(directory: legacy)
            precondition(upgraded.state.threshold == (oldThreshold == 50 ? 100 : 73))
            precondition(upgraded.state.scores.count == 3 && upgraded.state.nickname == "第一名")
            precondition(upgraded.state.version == 2)
            try upgraded.setThreshold(50)
            let restored = try LocalStore(directory: legacy)
            precondition(restored.state.threshold == 50, "New explicitly chosen 50% persists")
        }
        print("PASS: local scores, reload persistence, best-score ranking, settings boundaries and failed writes.")
    }
}
