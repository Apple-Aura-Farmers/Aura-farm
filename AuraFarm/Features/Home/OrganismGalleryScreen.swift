import AuraFarmKit
import ImageIO
import SwiftUI

/// The picture of each organism a test counted, with its name, under one heading per name.
struct OrganismGalleryScreen: View {
    /// The pictures that go by one name, in the order they were counted.
    struct NameGroup: Identifiable, Equatable {
        var name: String
        var pictures: [OrganismPicture]
        var id: String { name }
    }

    private let groups: [NameGroup]

    @Environment(\.dismiss) private var dismiss

    init(pictures: [OrganismPicture]) {
        groups = Self.groups(of: pictures)
    }

    /// The result screen offers this page only when there is something on it.
    static func isOffered(for pictures: [OrganismPicture]) -> Bool { !pictures.isEmpty }

    /// The name the result's detail list gives this class. A class `SoilLifeGroup` cannot place
    /// keeps its label as it is.
    static func name(for label: String) -> String {
        SoilLifeGroup.summarize([label: 1])
            .first { $0.key != .other }?.value.first?.organisms.first?.name ?? label
    }

    /// Most pictures first; a tie goes by name.
    static func groups(of pictures: [OrganismPicture]) -> [NameGroup] {
        Dictionary(grouping: pictures) { name(for: $0.image.taxon) }
            .map { NameGroup(name: $0.key, pictures: $0.value) }
            .sorted {
                $0.pictures.count != $1.pictures.count
                    ? $0.pictures.count > $1.pictures.count : $0.name < $1.name
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Organisms found")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 64)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 2),
                    alignment: .leading, spacing: 16
                ) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.pictures, id: \.file) { picture in
                                OrganismTile(name: group.name, file: picture.file)
                            }
                        } header: {
                            Text("\(group.name) · \(group.pictures.count)")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .padding(.top, 14)
        .auraBackground()
        .navigationBarBackButtonHidden()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward").font(.title3).frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(.leading, 22)
            .accessibilityLabel("Back")
        }
    }
}

/// One square picture and its name. The file is read off the main thread, no larger than it is
/// shown, and let go when the tile scrolls away.
private struct OrganismTile: View {
    let name: String
    let file: URL

    @Environment(\.displayScale) private var displayScale
    @State private var side: CGFloat = 0
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 6) {
            Color.primary.opacity(0.08)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: displayScale).resizable().scaledToFill()
                    } else if failed {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = $0 }
                .accessibilityElement()
                .accessibilityLabel(name)
                .accessibilityAddTraits(.isImage)
            Text(name)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)  // the picture already says it
        }
        .task(id: side) {
            guard side > 0 else { return }
            let file = file
            let pixels = Int((side * displayScale).rounded(.up))
            let loaded = await Task.detached(priority: .userInitiated) {
                Self.thumbnail(at: file, maxPixels: pixels)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
        .onDisappear { image = nil }
    }

    /// Decoded here, not when first drawn.
    nonisolated private static func thumbnail(at url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ] as CFDictionary)
    }
}

#Preview {
    // No files behind them: each shows the grey square a missing picture gets.
    let labels = ["nematode", "amoeba", "nematode", "an_unknown_class", "nematode", "amoeba"]
    NavigationStack {
        OrganismGalleryScreen(
            pictures: labels.enumerated().map { index, label in
                OrganismPicture(
                    image: SoilReport.OrganismImage(taxon: label, path: "preview/\(index).jpg"),
                    file: URL(filePath: "/preview/\(index).jpg"))
            })
    }
    .preferredColorScheme(.dark)
}
