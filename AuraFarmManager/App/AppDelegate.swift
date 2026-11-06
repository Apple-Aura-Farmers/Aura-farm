import AppKit

/// Receives soil report files opened from Finder, AirDrop or the Dock.
///
/// A file opened while the app is still launching arrives before the window exists, so it is
/// held until the window hands over its handler.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: (([URL]) -> Void)? {
        didSet { deliverPendingFiles() }
    }

    private var pendingFiles: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFiles.append(contentsOf: urls)
        deliverPendingFiles()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func deliverPendingFiles() {
        guard let openHandler, !pendingFiles.isEmpty else { return }
        let urls = pendingFiles
        pendingFiles.removeAll()
        openHandler(urls)
    }
}
