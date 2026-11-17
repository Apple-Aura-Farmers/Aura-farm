import Foundation

/// The farms on this phone, kept level with the records everyone else sees. Both screens that
/// show farms need this, so it lives with the store rather than in one of them.
extension FarmStore {
    /// Reads the farms back out of the records. Does nothing when the app has no Supabase
    /// details, so a build without them still works on the phone alone.
    func pull() async {
        guard let uploader = FarmUploader() else { return }
        do {
            let records = try await uploader.fetch()
            // The farms table knows nothing about soil, so a farm read back carries none. Its
            // soil comes from its own table, and failing that from what this phone already
            // holds, rather than the pull quietly wiping measurements nobody published.
            let soil = try await SoilMeasurementUploader()?.fetch() ?? [:]
            merge(
                records.map { farm in
                    var farm = farm
                    farm.soil = soil[farm.id] ?? self.farms.first { $0.id == farm.id }?.soil
                    return farm
                })
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Sends a farm and its plots to the records, after the phone has kept them.
    ///
    /// Every screen that changes a farm calls this, so what a helper marks, renames or
    /// reshapes is in the records straight away rather than waiting on them to remember
    /// Publish. The phone keeps the change either way: a bad connection is reported in the
    /// banner, not undone.
    ///
    /// A farm with no plots is held back. The records describe a farm by its land, so there
    /// is nothing to write until the first plot is marked, and it goes up with that plot.
    func publish(_ farm: Farm) async {
        guard !farm.plots.isEmpty, let uploader = FarmUploader() else { return }
        do {
            try await uploader.upload(farm)
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Keeps what the helper measured, on the phone first and in the records after.
    ///
    /// The phone is written to whether or not the sending works, because the measurement is
    /// the helper's own reading and losing it to a bad connection would be the worse half.
    func saveSoil(_ soil: SoilMeasurements?, for farm: Farm) async {
        var changed = farm
        changed.soil = soil
        update(changed)

        guard let uploader = SoilMeasurementUploader() else { return }
        do {
            try await uploader.upload(soil, forFarm: farm.id)
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
