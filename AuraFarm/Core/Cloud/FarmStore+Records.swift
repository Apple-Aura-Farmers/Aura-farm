import Foundation

/// The farms on this phone, kept level with the records everyone else sees. Both screens that
/// show farms need this, so it lives with the store rather than in one of them.
extension FarmStore {
    /// Reads the farms back out of the records. Does nothing when the app has no Supabase
    /// details, so a build without them still works on the phone alone.
    func pull() async {
        guard let uploader = FarmUploader() else { return }
        do {
            merge(try await uploader.fetch())
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Takes a farm out of the records first, and off this phone only once that has gone
    /// through: a farm deleted here but left there would come back with the next pull.
    func remove(_ farm: Farm) async {
        if let uploader = FarmUploader() {
            do {
                try await uploader.delete(farm)
            } catch {
                report(error.localizedDescription)
                return
            }
        }
        delete(farm)
        report(nil)
    }
}
