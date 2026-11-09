import AuraFarmKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The main window: farms and the inbox in the sidebar, soil tests in the middle, the chosen
/// test on the right.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SoilReportImportCoordinator.self) private var importCoordinator

    @State private var sidebarSelection: SidebarItem? = .inbox
    @State private var selectedTestID: PersistentIdentifier?
    @State private var isImporting = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import Soil Reports", systemImage: "square.and.arrow.down")
                }
                .help("Import .aurafarm reports sent from the iPhone")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.auraSoilReport],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importCoordinator.importFiles(at: urls)
            case .failure(let error):
                importCoordinator.reportFailure(error)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let reports = urls.filter { $0.pathExtension.lowercased() == SoilReport.fileExtension }
            guard !reports.isEmpty else { return false }
            importCoordinator.importFiles(at: reports)
            return true
        }
        .focusedSceneValue(\.importSoilReports, showImporter)
        .onChange(of: sidebarSelection) {
            selectedTestID = nil
        }
        .onChange(of: importCoordinator.importCount) {
            // New tests land in the inbox, so that is where to look for them.
            if (importCoordinator.latestSummary?.imported ?? 0) > 0 {
                sidebarSelection = .inbox
            }
        }
        .alert(
            importCoordinator.latestSummary?.title ?? "",
            isPresented: isShowingSummary,
            presenting: importCoordinator.latestSummary
        ) { _ in
            Button("OK") {}
        } message: { summary in
            Text(summary.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sidebarSelection {
        case .inbox:
            SoilTestListView(scope: .inbox, selection: $selectedTestID)
        case .allTests:
            SoilTestListView(scope: .all, selection: $selectedTestID)
        case .farm(let farm):
            FarmDetailView(farm: farm, selection: $selectedTestID) { field in
                sidebarSelection = .field(field)
            }
        case .field(let field):
            FieldDetailView(field: field, selection: $selectedTestID)
        case nil:
            ContentUnavailableView("Choose the Inbox or a Farm", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedTestID, let test: SoilTest = modelContext.registeredModel(for: selectedTestID) {
            SoilTestDetailView(test: test)
                .id(selectedTestID)
        } else {
            ContentUnavailableView(
                "No Soil Test Selected",
                systemImage: "testtube.2",
                description: Text("Choose a soil test to see what was counted.")
            )
        }
    }

    private func showImporter() {
        isImporting = true
    }

    private var isShowingSummary: Binding<Bool> {
        Binding(
            get: { importCoordinator.latestSummary != nil },
            set: { isShowing in
                if !isShowing { importCoordinator.latestSummary = nil }
            }
        )
    }
}
