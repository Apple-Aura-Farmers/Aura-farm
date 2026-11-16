import Foundation

/// Rows of the 16 Nov 2026 free-mode soil run (slide-movement-free-20261116-134233.csv): the
/// frame-to-frame shifts (`shake_*`) and the anchor readings (`anchor_*`) as the old tracker
/// logged them, at 10 a second.
///
/// - stuck: 5.9 to 13.0 s. The X knob was turned; the frame-to-frame shifts add up to 468 px in
///   y, the anchor stayed at 0 +- 12 px, and the position moved only 30 px.
/// - later: 23.2 to 29.0 s. The anchor worked: the frame-to-frame shifts and the position agree
///   within 1 px in the CSV (538 against 539 px in y). `laterHops` are the rows where the CSV
///   logged a hop (a re-anchor).
enum Free20261116Fixture {
    // The stuck window
    static let stuckShakeX: [Double] = [
        0, -1, -2, -3, -2, 0, -1, 0, 0, 0, 0, 0, 1, -1, -2, 0, -1, -1, -1, -1, -1, -1, -2, -3,
        -2, -1, -2, 0, 0, 0, -1, 0, -1, 0, 1, -2, -5, -3, -1, -1, -2, -2, -1, -1, -1, -1, -1,
        0, 0, 0, 0, -1, 0, -3, -5, -2, -1, 0, -1, 1, -2, -1, -2, 1, -1, 0, 0, 0, 0, 0, 0, -2,
    ]
    static let stuckShakeY: [Double] = [
        0, 11, 1, 17, 12, 6, 7, 5, 1, 0, 0, 0, 0, 2, 0, 11, 17, 11, 15, 10, 8, 16, 16, 0, 14,
        7, 12, 5, 5, 3, 0, 0, 0, -1, 0, 3, 11, 3, 12, 11, 16, 14, 13, 9, 9, 7, 5, 2, 0, 0, 0,
        0, 0, 26, 33, 13, 8, 7, 6, 3, 6, 9, 7, 2, 2, 1, 0, 0, 0, 0, 1, 18,
    ]
    static let stuckAnchorX: [Double] = [
        0, 3, 2, 4, 3, 3, 2, 3, 2, 2, 2, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 4, 3, 2, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 3, 0, 0, -1, -1, 8, 7, 6, 4, 4, 3, 3, 3, 2, 3, 2, 3, -1, 6, 4, 4,
        3, 2, 3, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, -1, 0,
    ]
    static let stuckAnchorY: [Double] = [
        -13, -2, -12, 5, -14, -10, 0, -11, -11, -11, -11, -11, -11, -9, -9, 2, -3, -12, 3, -15,
        -10, -12, -10, -17, -21, -14, -14, -11, -13, -18, -17, -18, -17, -18, -19, -8, 6, 5,
        -13, -9, -10, -18, -14, -5, 4, 1, 11, -4, -4, -4, -4, -4, -4, 9, 22, 2, 10, 17, -1, 2,
        8, 17, 24, 26, 28, 28, 28, 28, 28, 28, 29, 16,
    ]
    // The later window
    static let laterShakeX: [Double] = [
        1, -2, -1, -2, -1, -3, -2, -3, 0, 1, -2, 0, 0, 1, 0, 0, -2, -3, -2, -2, -2, -2, -3, -3,
        -2, -3, 0, 1, 0, 0, 0, 0, -1, 1, -3, -3, -3, -2, -3, -2, -3, -1, 1, -3, -2, -1, -2, -2,
        -2, -1, -1, -2, -1, -1, 0, -1, 0, -1, 1,
    ]
    static let laterShakeY: [Double] = [
        1, 4, 15, 7, 6, 12, 17, 15, 2, 6, 6, 0, 1, 0, 0, 0, 7, 16, 19, 16, 19, 18, 21, 18, 12,
        16, 6, 3, 0, 0, 0, 0, -2, 0, 18, 24, 19, 16, 14, 19, 16, 4, 4, 16, 12, 8, 16, 16, 12,
        10, 9, 7, 10, 5, 7, 7, 4, 2, 2,
    ]
    static let laterAnchorX: [Double] = [
        -1, -2, -4, -6, -6, -9, -11, -13, 0, 1, -1, 0, -1, 1, 0, 0, -2, -4, -6, -8, -10, -2,
        -5, -8, -9, -12, 0, 1, 0, 1, 0, 1, -1, 1, -2, -5, -7, -9, -3, -4, -7, -8, -7, 6, 11,
        -1, -3, -5, -7, -7, -8, -10, -10, -1, -2, -3, -4, -4, -4,
    ]
    static let laterAnchorY: [Double] = [
        12, 17, 32, 39, 45, 58, 75, 1, 2, 8, 14, 14, 15, 16, 16, 15, 23, 38, 57, -23, -4, 18,
        38, 56, 68, -4, 6, 9, 9, 9, 9, 9, 7, 8, 26, 50, 69, 86, 14, 33, 48, 52, 56, -51, -40,
        8, 24, 40, 52, 62, 9, 16, 3, 5, 12, 19, 23, 25, 27,
    ]
    static let stuckStart = (x: 0.0, y: -14.0)
    static let laterStart = (x: -1.0, y: 12.0)
    static let laterHops: Set<Int> = [7, 20, 25, 37, 44, 52]
    // csv position change over the later window: -71.0, 539.0
    // csv position change over the stuck window: 0.0, 30.0; sum shake y 468.0
}
