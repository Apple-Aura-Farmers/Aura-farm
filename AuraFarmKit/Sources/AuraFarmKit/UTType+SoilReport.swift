#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers

    extension UTType {
        /// An Aura Farm soil report file (`.aurafarm`). Declared in the app's Info.plist, so
        /// a report shared from one phone can be imported on another.
        public static let auraSoilReport = UTType(
            exportedAs: SoilReport.typeIdentifier,
            conformingTo: .json
        )
    }
#endif
