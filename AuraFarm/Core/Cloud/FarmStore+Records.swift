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
            // The plots table knows nothing about soil, so a plot read back carries none. Its
            // measurements come from their own table, and failing that from what this phone
            // already holds, rather than the pull quietly wiping measurements nobody published.
            let soil = try await SoilMeasurementUploader()?.fetch() ?? [:]
            let held = Dictionary(
                self.farms.flatMap(\.plots).map { ($0.id, $0.soilLog) },
                uniquingKeysWith: { first, _ in first })
            merge(
                records.map { farm in
                    var farm = farm
                    for index in farm.plots.indices {
                        let id = farm.plots[index].id
                        farm.plots[index].soilLog = soil[id] ?? held[id] ?? []
                    }
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
    /// Sends queue behind each other instead of racing. A send carries the whole farm, and
    /// finishes by taking away the plot rows it did not carry, so a slow send of the farm as
    /// it was one plot ago would otherwise land last and delete the plot marked after it.
    /// Waiting means the last send to finish is always the last change made. The cost is that
    /// a slow send holds up the ones behind it, which is the better way round: they are
    /// seconds apart, and the alternative is land going missing from the records.
    @MainActor
    func publish(_ farm: Farm) {
        let earlier = publishing
        publishing = Task {
            await earlier?.value
            await send(farm)
        }
    }

    /// One send. A farm with no plots is held back: the records describe a farm by its land,
    /// so there is nothing to write until the first plot is marked, and it goes up with it.
    private func send(_ farm: Farm) async {
        guard !farm.plots.isEmpty, let uploader = FarmUploader() else { return }
        do {
            try await uploader.upload(farm)
            report(nil)
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Keeps one measurement on a plot, replacing the one with the same id, on the phone first and
    /// in the records after. One with nothing in it is not kept, and takes the old one away.
    ///
    /// The phone is written to whether or not the sending works, because the measurement is
    /// the helper's own reading and losing it to a bad connection would be the worse half.
    func saveSoil(_ soil: SoilMeasurements, for plot: Plot, in farm: Farm) async {
        await changeSoilLog(of: plot, in: farm, sending: soil.isUnrecorded ? nil : soil, removing: soil.id) {
            $0.removeAll { $0.id == soil.id }
            if !soil.isUnrecorded { $0.append(soil) }
        }
    }

    /// Takes one measurement off a plot.
    func deleteSoil(_ id: UUID, for plot: Plot, in farm: Farm) async {
        await changeSoilLog(of: plot, in: farm, sending: nil, removing: id) {
            $0.removeAll { $0.id == id }
        }
    }

    /// Records that a scientist has been asked to look at a plot. The asking lives on the newest
    /// measurement, so a plot with none gets an empty one to hold it.
    func alertScientist(for plot: Plot, in farm: Farm) async {
        var newest = plot.soilLog.max { $0.measuredAt < $1.measuredAt } ?? SoilMeasurements()
        newest.scientistAlertedAt = Date()
        await saveSoil(newest, for: plot, in: farm)
    }

    private func changeSoilLog(
        of plot: Plot, in farm: Farm, sending soil: SoilMeasurements?, removing id: UUID,
        _ change: (inout [SoilMeasurements]) -> Void
    ) async {
        var changed = farm
        guard let index = changed.plots.firstIndex(where: { $0.id == plot.id }) else { return }
        change(&changed.plots[index].soilLog)
        update(changed)

        guard let uploader = SoilMeasurementUploader() else { return }
        do {
            if let soil {
                try await uploader.upload(soil, forPlot: plot.id, inFarm: farm.id)
                // The soil itself is registered here, so a counted test sent later has a
                // sample to be filed against rather than failing for want of one. Both sides
                // name it after the farmer, which is what `SampleDetails.use(_:of:)` puts on
                // a sweep, so the operator's send finds this row instead of making its own.
                if let registrar = SampleRegistrar() {
                    try await registrar.sampleID(
                        forCode: farm.farmerName, plotID: plot.id,
                        place: plot.locationDescription, at: soil.measuredAt)
                }
            } else {
                try await uploader.delete(id)
            }
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
