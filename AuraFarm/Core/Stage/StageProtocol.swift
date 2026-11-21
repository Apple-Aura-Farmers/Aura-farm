import Foundation

enum StageAxis {
    case x, y

    var letter: String { self == .x ? "X" : "Y" }
}

enum StageMode { case auto, manual }

enum StageRunState { case idle, moving, paused }

struct StagePoint: Equatable {
    var x: Int
    var y: Int
}

enum StageCommandError: Error, Equatable, LocalizedError {
    case angleOutOfRange
    case emptyPath
    case tooLong

    var errorDescription: String? {
        switch self {
        case .angleOutOfRange: "Angle must be 0-180."
        case .emptyPath: "Path has no points."
        case .tooLong: "Command is longer than \(StageCommand.maxLength) characters."
        }
    }
}

enum StageCommand: Equatable {
    case status
    case mode(StageMode)
    case jog(StageAxis, Int)
    case goTo(StageAxis, Int)
    case path([StagePoint])
    case start, traverse, stop, resume, home, end

    /// The device reads at most 255 characters; stay clear of it.
    static let maxLength = 240

    var text: String {
        switch self {
        case .status: "STATUS"
        case .mode(let m): m == .auto ? "MODE AUTO" : "MODE MANUAL"
        case .jog(let a, let n): "JOG \(a.letter) \(n)"
        case .goTo(let a, let n): "GOTO \(a.letter) \(n)"
        case .path(let pts): "PATH " + pts.map { "\($0.x),\($0.y)" }.joined(separator: ";")
        case .start: "START"
        case .traverse: "TRAVERSE"
        case .stop: "STOP"
        case .resume: "RESUME"
        case .home: "HOME"
        case .end: "END"
        }
    }

    func validated() throws -> String {
        switch self {
        case .goTo(_, let n) where !(0...180).contains(n):
            throw StageCommandError.angleOutOfRange
        case .path(let pts):
            if pts.isEmpty { throw StageCommandError.emptyPath }
            if pts.contains(where: { !(0...180).contains($0.x) || !(0...180).contains($0.y) }) {
                throw StageCommandError.angleOutOfRange
            }
        default: break
        }
        let t = text
        if t.count > Self.maxLength { throw StageCommandError.tooLong }
        return t
    }

    static func pathFits(_ points: [StagePoint]) -> Bool {
        StageCommand.path(points).text.count <= maxLength
    }
}

enum StagePresetPath: CaseIterable {
    case corners, grid3x3, centreCross

    var title: String {
        switch self {
        case .corners: "Corners"
        case .grid3x3: "3×3 grid"
        case .centreCross: "Centre cross"
        }
    }

    var points: [StagePoint] {
        let raw: [(Int, Int)]
        switch self {
        case .corners: raw = [(30, 30), (150, 30), (150, 150), (30, 150)]
        case .grid3x3:
            raw = [
                (30, 30), (90, 30), (150, 30), (150, 90), (90, 90), (30, 90), (30, 150), (90, 150),
                (150, 150),
            ]
        case .centreCross: raw = [(90, 30), (90, 150), (90, 90), (30, 90), (150, 90)]
        }
        return raw.map { StagePoint(x: $0.0, y: $0.1) }
    }
}

enum StageReply: Equatable {
    case ok(String)
    case error(String)
    case position(x: Int, y: Int)
    case done(x: Int, y: Int)
    case hello(mode: StageMode, state: StageRunState, x: Int, y: Int)
    case resumed(x: Int, y: Int, queued: Int)
    case status(mode: StageMode, state: StageRunState, x: Int, y: Int, queued: Int)
    case unknown(String)

    static func parse(_ line: String) -> StageReply {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = t.split(separator: " ").map(String.init)
        guard let first = words.first else { return .unknown(line) }

        if first == "OK" { return .ok(words.dropFirst().joined(separator: " ")) }
        if first == "ERR" { return .error(words.dropFirst().joined(separator: " ")) }

        let f = fields(words.dropFirst())
        switch first {
        case "POS":
            if let x = f["X"], let y = f["Y"], words.count == 3 { return .position(x: x, y: y) }
        case "DONE":
            if let x = f["X"], let y = f["Y"], words.count == 3 { return .done(x: x, y: y) }
        case "RESUMED":
            if let x = f["X"], let y = f["Y"], let q = f["Q"], words.count == 4 {
                return .resumed(x: x, y: y, queued: q)
            }
        case "HELLO":
            if words.count == 5, let m = mode(words[1]), let s = state(words[2]),
                let x = f["X"], let y = f["Y"]
            {
                return .hello(mode: m, state: s, x: x, y: y)
            }
        default:
            if words.count == 5, let m = mode(words[0]), let s = state(words[1]),
                let x = f["X"], let y = f["Y"], let q = f["Q"]
            {
                return .status(mode: m, state: s, x: x, y: y, queued: q)
            }
        }
        return .unknown(line)
    }

    private static func fields(_ words: ArraySlice<String>) -> [String: Int] {
        var out: [String: Int] = [:]
        for w in words {
            let kv = w.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, let n = Int(kv[1]) { out[kv[0]] = n }
        }
        return out
    }

    private static func mode(_ s: String) -> StageMode? {
        s == "AUTO" ? .auto : s == "MANUAL" ? .manual : nil
    }

    private static func state(_ s: String) -> StageRunState? {
        s == "IDLE" ? .idle : s == "MOVING" ? .moving : s == "PAUSED" ? .paused : nil
    }
}
