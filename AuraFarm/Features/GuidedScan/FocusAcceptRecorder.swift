import CoreVideo
import Foundation

enum FocusAcceptWho: String {
    case person, app
}

enum FocusAcceptPlace: String {
    /// Setup's focus step.
    case setup
    /// A pause for focus in the run.
    case run
    /// "It's sharp. Calibrate" on the Terraloka panel.
    case calibrate
}

/// One focus acceptance, written as JSON next to its frames: who accepted, what the app's check
/// said, and the numbers behind it. For finding wrong acceptances; nothing reads it back.
struct FocusAcceptRecord: Codable {
    /// One reading of the last 20 s. `t` is seconds from the tap (negative before it).
    struct Row: Codable {
        var t: Double
        var state: String
        var current: Double?
        var peak: Double?
        var level: Double?
        var detail: Double?
        var active: Int?
        var viewClass: String
    }

    var time = ""
    var `where` = ""
    var who = ""
    /// The app's own check had already accepted (`whyNot` is empty).
    var agreed = false
    /// "In focus – empty area": accepted with nothing in view, so the frames show no sharp sample.
    var emptyArea = false
    /// How long the focus step, spot or pause had been going.
    var secondsSinceBegan: Double?
    var objective: String?
    var stageAngleX: Int?
    var stageAngleY: Int?
    var appBuild = ""
    var whyNot: [String] = []

    var state: String?
    var current: Double?
    var peak: Double?
    var lowest: Double?
    var level: Double?
    var dial: Double?
    var monitorState: String?
    var pauseCause: String?
    var focusIndex: Double?
    var focusBaseline: Double?
    var sharpnessShare: Double?
    var isSharp: Bool?

    var detail: Double?
    var detailBest: Double?
    var top: Double?
    var topRatio: Double?
    var noise: Double?
    var used: Int?
    var active: Int?
    var tileFine: [Double?]?
    var tileCoarse: [Double?]?

    var viewClass: String?
    var tracking: String?
    var boxBrightness: Double?
    var boxSharpness: Double?
    var exposureMs: Double?
    var iso: Double?
    /// x, y, width, height in frame pixels.
    var focusSquare: [Double]?
    /// centre x, centre y, radius in frame pixels.
    var circle: [Double]?
    var thresholds: [String: Double] = [:]

    var readings: [Row] = []
    var frames: [String] = []

    /// The numeric properties of a thresholds struct, by name.
    static func numbers(of value: Any) -> [String: Double] {
        var result: [String: Double] = [:]
        for case let (name?, child) in Mirror(reflecting: value).children {
            if let number = child as? Double {
                result[name] = number
            } else if let number = child as? Int {
                result[name] = Double(number)
            }
        }
        return result
    }
}

/// Keeps what the last seconds of focus looked like, and on an accept saves it with three frames
/// from just after. Only the lab switches it on (`isOn`); off, nothing is kept and nothing costs.
///
/// Analysis queue: `offer`, `accept`, `flush`, `clear`. The PNGs and the JSON are written on a
/// queue of its own, so neither the analysis queue nor the camera waits for a file.
final class FocusAcceptRecorder {
    typealias Luma = (data: Data, width: Int, height: Int)

    /// PLACEHOLDER: a frame every half second for the last 10 s, readings for the last 20 s.
    static let ringGapSeconds = 0.5
    static let ringFrames = 20
    static let readingSeconds = 20.0
    /// At most this many records a session (until cleared).
    static let maxRecords = 20
    /// The frames saved after the tap: seconds from it.
    static let afterOffsets = [0.0, 0.5, 1.0]

    enum Outcome: Equatable {
        case off
        case recorded(Int)
        case limitReached
    }

    private final class Pending {
        let number: Int
        let who: FocusAcceptWho
        let place: FocusAcceptPlace
        let tap: Double
        var record: FocusAcceptRecord
        let before: [(seconds: Double, luma: Luma)]
        var after: [(seconds: Double, luma: Luma)] = []

        init(
            number: Int, who: FocusAcceptWho, place: FocusAcceptPlace, tap: Double,
            record: FocusAcceptRecord, before: [(seconds: Double, luma: Luma)]
        ) {
            self.number = number
            self.who = who
            self.place = place
            self.tap = tap
            self.record = record
            self.before = before
        }
    }

    /// Set once, before frames arrive (the lab does it; the real test never does).
    var isOn = false {
        didSet {
            guard !isOn else { return }
            ring = []
            readings = []
            pending = []
        }
    }
    /// A record's files are complete (any queue).
    var onChange: (() -> Void)?

    private(set) var count = 0
    private var ring: [(seconds: Double, luma: Luma)] = []
    private var readings: [(seconds: Double, row: FocusAcceptRecord.Row)] = []
    private var pending: [Pending] = []
    private var lastRingAt = -Double.infinity

    private let queue = DispatchQueue(label: "slidelab.focusaccept", qos: .utility)
    private let lock = NSLock()
    private var written: [URL] = []
    private var directory: URL?

    /// Every PNG and JSON written so far (any queue).
    var files: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    /// Every analysed frame. `wanted`: setup is in the focus step or the run in a focus pause, so
    /// the ring and the readings are kept; otherwise they are freed once nothing is in progress.
    /// `row`: this frame's reading, if it has one.
    func offer(
        _ buffer: CVPixelBuffer, seconds: Double, wanted: Bool, row: FocusAcceptRecord.Row?
    ) {
        guard isOn else { return }
        var copy: Luma?
        func luma() -> Luma? {
            if copy == nil { copy = FrameSnapshotWriter.lumaCopy(of: buffer) }
            return copy
        }
        for item in pending where item.after.count < Self.afterOffsets.count {
            if seconds >= item.tap + Self.afterOffsets[item.after.count], let frame = luma() {
                item.after.append((seconds, frame))
            }
        }
        for item in pending where item.after.count == Self.afterOffsets.count { finish(item) }
        if wanted {
            if let row {
                readings.append((seconds, row))
                readings.removeAll { seconds - $0.seconds > Self.readingSeconds }
            }
            if seconds - lastRingAt >= Self.ringGapSeconds - 1e-9, let frame = luma() {
                lastRingAt = seconds
                ring.append((seconds, frame))
                if ring.count > Self.ringFrames { ring.removeFirst(ring.count - Self.ringFrames) }
            }
        } else if pending.isEmpty {
            ring = []
            readings = []
            lastRingAt = -.infinity
        }
    }

    /// A focus was accepted at `seconds` (the analysis clock). `base` holds the numbers; the
    /// readings, the frames and the time are added here. Never fails the caller: at the limit or
    /// when off, nothing is recorded.
    @discardableResult
    func accept(
        _ base: FocusAcceptRecord, who: FocusAcceptWho, place: FocusAcceptPlace, seconds: Double
    ) -> Outcome {
        guard isOn else { return .off }
        guard count < Self.maxRecords else { return .limitReached }
        count += 1
        var record = base
        record.who = who.rawValue
        record.where = place.rawValue
        record.time = ISO8601DateFormatter().string(from: .now)
        record.readings = readings.filter { seconds - $0.seconds <= Self.readingSeconds }.map {
            var row = $0.row
            row.t = $0.seconds - seconds
            return row
        }
        pending.append(
            Pending(
                number: count, who: who, place: place, tap: seconds, record: record, before: ring))
        return .recorded(count)
    }

    /// The lab closes or the app goes to the background: write what there is.
    func flush() {
        for item in pending { finish(item) }
    }

    /// "Clear focus records": deletes the files and starts the numbering and the limit afresh.
    func clear() {
        pending = []
        count = 0
        queue.async { [self] in
            lock.lock()
            let urls = written
            written = []
            lock.unlock()
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    static func frameName(_ number: Int, _ who: FocusAcceptWho, _ place: FocusAcceptPlace, offset: Double)
        -> String
    {
        let sign = offset < 0 ? "-" : "+"
        return String(
            format: "focus-accept-%02d-%@-%@-t%@%05.2f.png", number, who.rawValue, place.rawValue,
            sign, abs(offset))
    }

    /// Hands the record to the writer queue and drops it from `pending`.
    private func finish(_ item: Pending) {
        pending.removeAll { $0 === item }
        var record = item.record
        let frames =
            item.before.map { ($0.seconds - item.tap, $0.luma) }
            + item.after.map { ($0.seconds - item.tap, $0.luma) }
        let names = frames.map { Self.frameName(item.number, item.who, item.place, offset: $0.0) }
        record.frames = names
        let json = String(format: "focus-accept-%02d.json", item.number)
        queue.async { [self] in
            guard let folder = ensureDirectory() else { return }
            var urls: [URL] = []
            for (name, frame) in zip(names, frames) {
                let url = folder.appending(path: name)
                FrameSnapshotWriter.writePNG(frame.1, to: url)
                urls.append(url)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // A value that is not a number must not lose the whole record.
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            let url = folder.appending(path: json)
            if (try? encoder.encode(record).write(to: url, options: .atomic)) != nil {
                urls.append(url)
            }
            lock.lock()
            written += urls
            lock.unlock()
            onChange?()
        }
    }

    /// Writer queue only.
    private func ensureDirectory() -> URL? {
        if let directory { return directory }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "")
        let folder = FileManager.default.temporaryDirectory.appending(path: "focus-records-\(stamp)")
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
            != nil
        else { return nil }
        directory = folder
        return folder
    }
}
