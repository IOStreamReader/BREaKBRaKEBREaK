import Foundation

struct SavedScore: Codable {
    let nickname: String
    let v0: Double
    let stopTime: Double
    let score: Int
    let threshold: Int
    let date: Date

    var json: [String: Any] {
        ["nickname": nickname, "v0": v0, "stopTime": stopTime,
         "score": score, "threshold": threshold]
    }
}

struct SavedState: Codable {
    var version = 2
    var threshold = 100
    var nickname = ""
    var scores: [SavedScore] = []
}

enum StoreError: LocalizedError {
    case invalidSettings, invalidScore, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "力度阈值必须是 1～100 的整数。"
        case .invalidScore: return "成绩数据无效，无法保存。"
        case .unsupportedVersion: return "本地数据由更高版本的游戏创建，暂时无法读取。"
        }
    }
}

final class LocalStore {
    let url: URL
    private(set) var state = SavedState()

    init(directory: URL) throws {
        url = directory.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
            guard (1...2).contains(state.version) else { throw StoreError.unsupportedVersion }
            guard (1...100).contains(state.threshold) else { throw StoreError.invalidSettings }
            if state.version == 1 {
                // Upgrade the old default without clearing scores or other thresholds.
                var upgraded = state
                if upgraded.threshold == 50 { upgraded.threshold = 100 }
                upgraded.version = 2
                try commit(upgraded)
            }
        }
    }

    var bootstrap: [String: Any] {
        ["threshold": state.threshold, "nickname": state.nickname]
    }

    @discardableResult func setThreshold(_ value: Int) throws -> [String: Any] {
        guard (1...100).contains(value) else { throw StoreError.invalidSettings }
        var next = state
        next.threshold = value
        try commit(next)
        return bootstrap
    }

    func leaderboard(limit: Int = 50) -> [[String: Any]] {
        Array(bestScores().prefix(max(1, min(50, limit)))).map(\.json)
    }

    func save(nickname rawName: String, v0: Double, stopTime: Double) throws -> [String: Any] {
        let nickname = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty, nickname.utf16.count <= 12,
              !nickname.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              v0.isFinite, stopTime.isFinite, v0 >= 100, v0 <= 260.1,
              stopTime > 0, stopTime <= 3600 else { throw StoreError.invalidScore }
        let points = v0 * v0 / stopTime
        guard points.isFinite, points <= Double(Int.max / 2) else { throw StoreError.invalidScore }
        let score = Int(points.rounded())
        var next = state
        next.nickname = nickname
        next.scores.append(SavedScore(nickname: nickname, v0: v0, stopTime: stopTime,
                                     score: score, threshold: state.threshold, date: Date()))
        try commit(next)
        let best = bestScores()
        let position = best.firstIndex { $0.nickname == nickname } ?? 0
        return ["score": score, "best": best[position].score, "rank": position + 1]
    }

    private func bestScores() -> [SavedScore] {
        var best: [String: SavedScore] = [:]
        for row in state.scores {
            if let previous = best[row.nickname], previous.score >= row.score { continue }
            best[row.nickname] = row
        }
        return best.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.nickname < $1.nickname
        }
    }

    private func commit(_ next: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: url, options: .atomic)
        state = next
    }
}
