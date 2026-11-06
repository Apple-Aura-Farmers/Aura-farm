#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers

    extension UTType {
        /// An Aura Farm soil report file (`.aurafarm`). Declared in both apps' Info.plist,
        /// so AirDrop and Finder hand it to the farm manager.
        public static let auraSoilReport = UTType(
            exportedAs: SoilReport.typeIdentifier,
            conformingTo: .json
        )
    }
#endif
