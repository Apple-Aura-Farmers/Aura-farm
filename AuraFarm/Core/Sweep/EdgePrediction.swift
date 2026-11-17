import Foundation

/// The numbers the edge prediction decides with. Data, not logic. All PLACEHOLDER: from the
/// Phase 2u brief, not calibrated.
struct EdgePredictionThresholds: Equatable {
    /// No leg spot is placed beyond the predicted edge less this: the last ordinary spot sits here
    /// and the helper carries on to the edge itself.
    var spotEdgeMarginFields = 0.5
    /// The view passing the predicted edge by more than this, with nothing ahead and no edge
    /// confirmed, asks "Edge should be here. Confirm?".
    var overshootFields = 0.8
    /// With three or more points, the one furthest from the fit is dropped when it is more than
    /// this off, and the line is fitted again.
    var outlierFields = 0.8
    /// The prediction is used (for the spot margin and the expected-edge ask) only when the fit's
    /// root-mean-square error is at most this; otherwise the leg runs to the edge with no margin.
    /// PLACEHOLDER: the Phase 3a brief. Source: run C, whose bottom edge points scatter about 0.5
    /// field.
    var predictionTrustFields = 0.4
}

/// A straight edge in guide coordinates: its position along the leg axis (y) is
/// `intercept + slope * x`, x being the column's position across.
struct EdgeFit: Equatable {
    var intercept: Double
    var slope: Double

    func along(at x: Double) -> Double { intercept + slope * x }
}

/// Which edge of the sample a leg ends on: the one at the top (an up leg) or at the bottom.
enum EdgeSide: Equatable {
    case top, bottom
}

/// Every confirmed or marked top and bottom edge point of the run so far, and the straight line
/// through each side's points. Pure. See `SlideRoute` for how the route uses it.
struct EdgePrediction: Equatable {
    var thresholds = EdgePredictionThresholds()
    private(set) var top: [CGPoint] = []
    private(set) var bottom: [CGPoint] = []

    /// Remembers an edge point: the column's x across, the edge's position along the leg.
    mutating func record(_ side: EdgeSide, x: Double, along: Double) {
        let point = CGPoint(x: x, y: along)
        switch side {
        case .top: top.append(point)
        case .bottom: bottom.append(point)
        }
    }

    /// The fitted line for a side and the points it was fitted to; nil with fewer than two points.
    private func fitted(_ side: EdgeSide) -> (line: EdgeFit, points: [CGPoint])? {
        var points = side == .top ? top : bottom
        guard points.count >= 2, var line = Self.leastSquares(points) else { return nil }
        if points.count >= 3 {
            let off = points.map { abs(Double($0.y) - line.along(at: Double($0.x))) }
            if let worst = off.enumerated().max(by: { $0.element < $1.element }),
                worst.element > thresholds.outlierFields
            {
                points.remove(at: worst.offset)
                line = Self.leastSquares(points) ?? line
            }
        }
        return (line, points)
    }

    /// The fitted line for a side; nil with fewer than two points.
    func fit(_ side: EdgeSide) -> EdgeFit? { fitted(side)?.line }

    /// The root-mean-square distance of the fitted points from their line, in fields.
    func rmsError(_ side: EdgeSide) -> Double? {
        guard let (line, points) = fitted(side) else { return nil }
        let squares = points.map { pow(Double($0.y) - line.along(at: Double($0.x)), 2) }
        return (squares.reduce(0, +) / Double(squares.count)).squareRoot()
    }

    /// `along`, only when the fit's error is within `predictionTrustFields`.
    func trustedAlong(_ side: EdgeSide, at x: Double) -> Double? {
        guard let error = rmsError(side), error <= thresholds.predictionTrustFields else { return nil }
        return along(side, at: x)
    }

    /// The predicted edge position along the leg for a column at `x`; nil without a fit.
    func along(_ side: EdgeSide, at x: Double) -> Double? { fit(side)?.along(at: x) }

    /// The mean top-to-bottom distance of the two fits over the columns at `xs`; nil unless both
    /// sides have a fit.
    func meanHeight(atColumns xs: [Double]) -> Double? {
        guard let upper = fit(.top), let lower = fit(.bottom), !xs.isEmpty else { return nil }
        let heights = xs.map { lower.along(at: $0) - upper.along(at: $0) }
        return heights.reduce(0, +) / Double(heights.count)
    }

    /// Least squares through the points; a vertical stack of points (no spread in x) is the flat
    /// line through their mean.
    private static func leastSquares(_ points: [CGPoint]) -> EdgeFit? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        let meanX = points.map { Double($0.x) }.reduce(0, +) / n
        let meanY = points.map { Double($0.y) }.reduce(0, +) / n
        let spread = points.map { pow(Double($0.x) - meanX, 2) }.reduce(0, +)
        guard spread > 1e-9 else { return EdgeFit(intercept: meanY, slope: 0) }
        let cross = points.map { (Double($0.x) - meanX) * (Double($0.y) - meanY) }.reduce(0, +)
        let slope = cross / spread
        return EdgeFit(intercept: meanY - slope * meanX, slope: slope)
    }
}

/// What the route has predicted, for the trail mini-map: the top and bottom lines, and the right
/// edge's x. nil parts are not known yet.
struct PredictedEdges: Equatable {
    var top: EdgeFit?
    var bottom: EdgeFit?
    var rightX: Double?
    /// The x range to draw the lines over: the left edge to the right edge, or one column past the
    /// last one when the right edge is unknown.
    var xRange: ClosedRange<Double>?
}
