//
//  LandOutlineEditorView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Where a helper marks out a farmer's land. The map opens on the phone's position (or on the
/// existing outline when editing); each tap drops a dot, and the dots joined in the order they
/// were placed are the edge of the land. A dot can also be dropped exactly where the helper is
/// standing, for walking the edge.
///
/// Nothing is kept until the helper taps **Confirm outline**. Leaving any other way throws the
/// changes away, after asking if anything was changed.
struct LandOutlineEditorView: View {
    /// Land already mapped, drawn on the map so the new outline can be kept clear of it.
    let neighbours: [Neighbour]
    /// What the button that keeps the outline says. "Next" where a form for the farmer and
    /// the plot's name follows, which is marking a plot from the map with no farm picked yet;
    /// "Save" where the farm is already known and confirming is the last step.
    var confirmTitle: String = "Next"
    let onConfirm: ([GeoPoint]) -> Void
    /// Called when the helper leaves without confirming, so whoever opened the editor can put
    /// back whatever was on screen before it.
    var onCancel: (() -> Void)?

    @State private var corners: [GeoPoint]
    @State private var position: MapCameraPosition
    @State private var location = LocationProvider()
    @State private var confirmDiscard = false
    /// Whether this phone has ever marked a corner. The coach mark is for the first time only.
    @AppStorage("hasMarkedAPlotCorner") private var hasMarkedACorner = false
    /// The corner being dragged, and where it sat on screen when the drag began.
    @State private var drag: (index: Int, start: CGPoint)?
    @Environment(\.dismiss) private var dismiss

    private let startingCorners: [GeoPoint]

    init(
        corners: [GeoPoint], neighbours: [Neighbour], confirmTitle: String = "Next",
        onConfirm: @escaping ([GeoPoint]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.startingCorners = corners
        self.neighbours = neighbours
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _corners = State(initialValue: corners)
        // Editing opens on the existing land; a new outline opens on where the phone is.
        if let region = LandGeometry.region(fitting: corners) {
            _position = State(initialValue: .region(region))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: drag == nil ? .all : []) {
                UserAnnotation()

                ForEach(neighbours) { neighbour in
                    MapPolygon(coordinates: neighbour.corners.map(\.coordinate))
                        .foregroundStyle(.blue.opacity(0.25))
                        .stroke(.cyan, lineWidth: 2)
                    if let middle = LandGeometry.centre(of: neighbour.corners) {
                        Annotation(
                            neighbour.label, coordinate: middle.coordinate, anchor: .center
                        ) {
                            Text(neighbour.label)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                        .annotationTitles(.hidden)
                    }
                }

                if corners.count >= 3 {
                    MapPolygon(coordinates: corners.map(\.coordinate))
                        .foregroundStyle(.green.opacity(0.3))
                        .stroke(.white, lineWidth: 2)
                } else if corners.count == 2 {
                    MapPolyline(coordinates: corners.map(\.coordinate))
                        .stroke(.white, lineWidth: 2)
                }
                ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                    Annotation(
                        "Corner \(index + 1)", coordinate: corner.coordinate, anchor: .center
                    ) {
                        let isDragging = drag?.index == index
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 23, height: 23)
                            .background(Self.dot, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .scaleEffect(isDragging ? 1.35 : 1)
                            .animation(.spring(duration: 0.2), value: isDragging)
                            // A bigger area to grab than the dot itself, for a thumb.
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        moveCorner(index, by: value.translation, using: proxy)
                                    }
                                    .onEnded { _ in drag = nil }
                            )
                            .accessibilityLabel("Corner \(index + 1)")
                            .accessibilityHint("Drag to move this corner")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.hybrid)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                // A tap on an existing dot is for that dot, not a new corner beside it.
                let onADot = corners.contains { corner in
                    guard let spot = proxy.convert(corner.coordinate, to: .local) else {
                        return false
                    }
                    return hypot(spot.x - point.x, spot.y - point.y) < 22
                }
                if !onADot, let coordinate = proxy.convert(point, from: .local) {
                    corners.append(GeoPoint(coordinate))
                    hasMarkedACorner = true
                }
            }
        }
        // Nothing to look at until the first tap, so the land is put out of focus behind what
        // the coach mark is asking for.
        .blur(radius: showsCoachMark ? 14 : 0)
        .overlay { coachMark }
        .animation(.snappy, value: showsCoachMark)
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle(corners.isEmpty ? "" : "New Plot")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // The land takes the whole screen while it is being marked.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if corners == startingCorners {
                        leave()
                    } else {
                        confirmDiscard = true
                    }
                } label: {
                    Image(systemName: corners.isEmpty ? "xmark" : "chevron.left")
                }
                .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Grey until there is an area to name, then the blue of a real way on.
                //
                // Drawn here rather than left to `.borderedProminent`: the bar has no
                // background of its own over the map, so the system reads no appearance off
                // it and gave the label the same dark in light mode and in dark. White on
                // the accent is what a filled button carries in either one.
                Button {
                    onConfirm(corners)
                    dismiss()
                } label: {
                    Text(confirmTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            canConfirm ? Color.accentColor : Color.secondary.opacity(0.5),
                            in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
            }
        }
        .confirmationDialog(
            "Discard your changes to the outline?", isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { leave() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
    }

    /// Leaving without keeping the outline. The handler goes first and the pop second, the way
    /// confirming does, so what it brings back is already there as the editor slides away.
    private func leave() {
        onCancel?()
        dismiss()
    }

    // MARK: The first time

    /// Only before the very first corner this phone has ever marked.
    private var showsCoachMark: Bool { corners.isEmpty && !hasMarkedACorner }

    @ViewBuilder
    private var coachMark: some View {
        if showsCoachMark {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.25)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tap Anywhere")
                            .font(.headline)
                        Text("Try tapping to start plotting the boundary points of the farm")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .frame(width: 210, alignment: .leading)
                    .position(x: 24 + 105, y: proxy.size.height * 0.47)

                    target
                        .position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.5)
                }
            }
            .ignoresSafeArea()
            // The tap underneath is the point of it.
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// The ringed dot the mockup puts on the map: what a corner will look like.
    private var target: some View {
        Circle()
            .fill(Self.dot)
            .frame(width: 23, height: 23)
            .overlay(Circle().stroke(.white, lineWidth: 1).frame(width: 31, height: 31))
            .overlay(Circle().stroke(.white, lineWidth: 1).frame(width: 38, height: 38))
            .phaseAnimator([false, true]) { rings, grown in
                rings.scaleEffect(grown ? 1.08 : 0.92)
            } animation: { _ in
                .easeInOut(duration: 1).repeatForever()
            }
    }

    // MARK: Dragging corners

    /// Moves a corner to follow the finger. The corner's screen position is noted when the drag
    /// starts and the finger's movement added to it, so the dot keeps its distance from the
    /// finger instead of jumping to sit under it.
    private func moveCorner(_ index: Int, by translation: CGSize, using proxy: MapProxy) {
        guard corners.indices.contains(index) else { return }
        if drag?.index != index {
            guard let start = proxy.convert(corners[index].coordinate, to: .global) else {
                return
            }
            drag = (index, start)
        }
        guard let start = drag?.start,
            let coordinate = proxy.convert(
                CGPoint(x: start.x + translation.width, y: start.y + translation.height),
                from: .global)
        else { return }
        corners[index] = GeoPoint(coordinate)
    }

    // MARK: Controls

    /// What the land adds up to, anything wrong with it, and the one way to start again. They
    /// float over the map rather than sitting on a panel, so the land stays the screen.
    @ViewBuilder
    private var controls: some View {
        if !showsCoachMark {
            VStack(spacing: 10) {
                Text(status)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(crossesItself ? Color.orange : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)

                if !overlapping.isEmpty {
                    note(overlapWarning, .orange)
                }

                if location.isDenied {
                    note("Location is off, so the map will not open where you are.", .secondary)
                }

                Button("Clear All", role: .destructive) {
                    corners.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Self.clearAll)
                .disabled(corners.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
    }

    private func note(_ text: String, _ colour: some ShapeStyle) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(colour)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    // MARK: The design's own colours

    /// A corner, and the only way to start again. Taken from the design.
    private static let dot = Color(red: 1, green: 0.573, blue: 0.459)
    private static let clearAll = Color(red: 1, green: 0.22, blue: 0.235)

    private var crossesItself: Bool { LandGeometry.crossesItself(corners) }

    private var canConfirm: Bool { corners.count >= 3 && !crossesItself }

    private var overlapping: [Neighbour] {
        neighbours.filter { LandGeometry.overlap(corners, $0.corners) }
    }

    private var overlapWarning: String {
        let names = overlapping.map(\.label).formatted(.list(type: .and))
        return "This outline overlaps \(names)'s land. Move the dots so it stays on this "
            + "farmer's own land, or confirm anyway if the overlap is only GPS error."
    }

    private var status: String {
        if corners.isEmpty {
            return "Tap the map to drop a dot on each corner, going round the edge in order."
        }
        if corners.count < 3 {
            return "\(corners.count) of at least 3 corners. Keep tapping the corners."
        }
        if crossesItself {
            return "The edges cross each other. Undo, then place the dots in order round the edge."
        }
        let area = LandGeometry.areaSquareMetres(of: corners) ?? 0
        return "\(corners.count) corners · \(LandGeometry.areaDescription(squareMetres: area))"
    }
}

#Preview {
    NavigationStack {
        LandOutlineEditorView(
            corners: [],
            neighbours: [
                Neighbour(
                    id: UUID(),
                    label: "Subak Jatiluwih",
                    corners: [
                        GeoPoint(latitude: -8.4095, longitude: 115.1889),
                        GeoPoint(latitude: -8.4095, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1889),
                    ])
            ],
            onConfirm: { _ in })
    }
}
