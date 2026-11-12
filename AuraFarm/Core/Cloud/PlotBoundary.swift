import Foundation

/// Turns the corners a helper marked on the map into the text `plots.boundary` accepts.
///
/// PostGIS reads a geometry or geography column from well-known text, so the corners go up
/// as `SRID=4326;POLYGON(...)` rather than as numbers. The same text works whichever of the
/// two the column is, which is why it is used in place of GeoJSON.
enum PlotBoundary {
    /// Corners below this cannot make a polygon, and the form already refuses to save one.
    static let fewestCorners = 3

    /// nil when there are too few corners to enclose anything.
    static func wellKnownText(for corners: [GeoPoint]) -> String? {
        guard corners.count >= fewestCorners else { return nil }
        var ring = corners
        // A polygon ring has to come back to where it started. The map keeps the corners
        // open, because a repeated dot would be one the helper could drag away on its own.
        if ring.first != ring.last { ring.append(ring[0]) }
        // Longitude first: well-known text is x then y, and x is the one that goes east.
        let points = ring.map { "\(number($0.longitude)) \(number($0.latitude))" }
        return "SRID=4326;POLYGON((\(points.joined(separator: ", "))))"
    }

    /// Fixed decimals, never exponent form, and never a comma for the decimal point: the
    /// text is parsed by Postgres, not read by anyone here. Eight places is about a
    /// millimetre.
    private static func number(_ value: Double) -> String {
        String(format: "%.8f", locale: nil, value)
    }

    /// The corners of a boundary read back out of the records.
    ///
    /// A boundary does not come back as the text it went up as. PostGIS hands a geometry or
    /// geography column to PostgREST as well-known binary, hex encoded, so reading a plot
    /// means undoing that: the byte order, the type word and its SRID, the rings, and then
    /// the pairs of doubles. Only the outer ring is kept, and the corner that closes it is
    /// dropped, because the map holds its corners open.
    ///
    /// nil for anything that is not a polygon, which is the only shape the phone draws.
    static func corners(fromHexBinary hex: String) -> [GeoPoint]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex),
                next != index,
                let byte = UInt8(hex[index..<next], radix: 16)
            else { return nil }
            bytes.append(byte)
            index = next
        }
        return corners(fromBinary: bytes)
    }

    /// Well-known binary: one byte of byte order, the type, and the rings.
    static func corners(fromBinary bytes: [UInt8]) -> [GeoPoint]? {
        var reader = Reader(bytes: bytes)
        guard let order = reader.byte() else { return nil }
        reader.isLittleEndian = order == 1
        guard let type = reader.uint32() else { return nil }
        // The top bits of the type word flag what follows it; the shape is the bottom ones.
        let hasSRID = type & 0x2000_0000 != 0
        guard type & 0xFF == 3 else { return nil }  // 3 is a polygon.
        if hasSRID, reader.uint32() == nil { return nil }

        guard let rings = reader.uint32(), rings >= 1 else { return nil }
        guard let count = reader.uint32(), count >= UInt32(fewestCorners) else { return nil }

        var ring: [GeoPoint] = []
        ring.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let longitude = reader.double(), let latitude = reader.double() else {
                return nil
            }
            ring.append(GeoPoint(latitude: latitude, longitude: longitude))
        }
        // The rings after the first are holes, which the phone cannot draw and ignores.
        if ring.count > fewestCorners, ring.first == ring.last { ring.removeLast() }
        return ring.count >= fewestCorners ? ring : nil
    }

    /// Reads numbers off the front of a byte array, in the order the bytes say.
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var isLittleEndian = true

        mutating func byte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func uint32() -> UInt32? {
            guard let raw: UInt32 = next() else { return nil }
            return isLittleEndian ? raw : raw.byteSwapped
        }

        mutating func double() -> Double? {
            guard let raw: UInt64 = next() else { return nil }
            return Double(bitPattern: isLittleEndian ? raw : raw.byteSwapped)
        }

        /// The next value's worth of bytes, read smallest first. Reading is arithmetic here
        /// rather than a reinterpreted load, so it does not depend on this machine's own
        /// byte order, only on the one the bytes declare.
        private mutating func next<Value: FixedWidthInteger>() -> Value? {
            let width = MemoryLayout<Value>.size
            guard offset + width <= bytes.count else { return nil }
            defer { offset += width }
            return bytes[offset..<offset + width].reversed().reduce(Value(0)) {
                $0 << 8 | Value($1)
            }
        }
    }
}
