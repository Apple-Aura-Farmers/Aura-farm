import AuraFarmKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The inbox, or every soil test, newest first.
///
/// Tests land in the inbox when a helper saves a sweep without picking a field. The program
/// manager files them from here, and can also pull in sweeps saved on this phone before the
/// records existed, or report files from another phone.
struct SoilTestListView: View {
    enum Scope {
        /// Tests not yet filed under a field.
        case inbox
        case all
    }

    let scope: Scope

    @Query(sort: \SoilTest.recordedAt, order: .reverse) private var allTests: [SoilTest]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.canEditRecords) private var canEdit
    @State private var isImportingFiles = false
    @State private var summary: ImportSummary?

    var body: some View {
        Group {
            if visibleTests.isEmpty {
                ContentUnavailableView {
                    Label(scope == .inbox ? "Inbox Is Empty" : "No Soil Tests Yet", systemImage: "tray")
                } description: {
                    Text(emptyDescription)
                }
            } else {
                List {
                    ForEach(visibleTests) { test in
                        NavigationLink(value: test) {
                            SoilTestRow(test: test, showsPlace: scope == .all)
                        }
                        .swipeActions {
                            if canEdit {
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(test)
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(scope == .inbox ? "Inbox" : "All Tests")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            importSweepsOnThisPhone()
                        } label: {
                            Label("Add Sweeps from This Phone", systemImage: "iphone")
                        }
                        Button {
                            isImportingFiles = true
                        } label: {
                            Label("Import Report Files", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add Tests", systemImage: "plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.auraSoilReport],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                summary = SoilReportImporter(context: modelContext).importFiles(at: urls)
            case .failure(let error):
                let failure = ImportSummary.Failure(fileName: "Import", reason: error.localizedDescription)
                summary = ImportSummary(failures: [failure])
            }
        }
        .alert(summary?.title ?? "", isPresented: isShowingSummary, presenting: summary) { _ in
            Button("OK") {}
        } message: { summary in
            Text(summary.message)
        }
    }

    private var visibleTests: [SoilTest] {
        switch scope {
        case .inbox: return allTests.filter { $0.field == nil }
        case .all: return allTests
        }
    }

    private var emptyDescription: String {
        switch scope {
        case .inbox:
            return "Tests a helper saves without picking a field wait here to be filed under one."
        case .all:
            return "Tests appear here once a helper saves one from its result screen."
        }
    }

    private func importSweepsOnThisPhone() {
        summary = SoilReportImporter(context: modelContext).importSweeps(SweepLibrary.sweeps())
    }

    private var isShowingSummary: Binding<Bool> {
        Binding(
            get: { summary != nil },
            set: { isShowing in
                if !isShowing { summary = nil }
            }
        )
    }
}
