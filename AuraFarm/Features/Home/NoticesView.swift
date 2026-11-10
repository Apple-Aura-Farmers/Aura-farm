import SwiftUI

/// What the app noticed about the tests already taken, behind the bell on Home.
struct NoticesView: View {
    var notices: [SweepNotice]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notices.isEmpty {
                    ContentUnavailableView(
                        "Nothing to see to",
                        systemImage: "checkmark.circle",
                        description: Text("Every test you have taken came out whole.")
                    )
                } else {
                    ForEach(notices) { notice in
                        if let sweep = notice.sweep {
                            NavigationLink {
                                SweepDetailView(sweep: sweep)
                            } label: {
                                row(notice)
                            }
                        } else {
                            row(notice)
                        }
                    }
                }
            }
            .navigationTitle("Notices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ notice: SweepNotice) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: notice.systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bell, with what is waiting behind it counted on the badge.
struct NoticesButton: View {
    var notices: [SweepNotice]
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "bell.fill")
        }
        .accessibilityLabel(
            notices.isEmpty ? "Notices" : "Notices, \(notices.count) waiting"
        )
        .overlay(alignment: .topTrailing) {
            if !notices.isEmpty {
                Text(notices.count, format: .number)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
                    // Clear of the bell rather than on it, so neither covers the other.
                    .alignmentGuide(.top) { $0[.bottom] / 2 }
                    .alignmentGuide(.trailing) { $0[.leading] }
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    NoticesView(notices: [
        SweepNotice(
            kind: .storeNearlyFull,
            title: "The store is nearly full",
            detail: "42 MB of 50 MB used.",
            sweep: nil
        )
    ])
}
