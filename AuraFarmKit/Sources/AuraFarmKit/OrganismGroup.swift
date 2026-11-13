import Foundation

/// The organism groups the soil detector knows, with the names a farmer would use.
///
/// A detector label that is not listed here is shown as it is, so a label added by a newer
/// model still reads.
public enum OrganismGroup: String, CaseIterable, Sendable {
    case arcellinida = "Arcellinida"
    case digononta = "Digononta"
    case monogononta = "Monogononta"
    case nematoda = "Nematoda"
    /// The spelling the detector in the app uses. The weights before it said `Nematoda`, and
    /// results saved then are still read, so both spellings stay.
    case nematode = "Nematode"
    case hypotrichida = "Hypotrichida"
    case euglenoid = "Euglenoid"
    case volvox = "Volvox"

    /// The everyday name, for example "Nematodes".
    public var commonName: String {
        switch self {
        case .arcellinida: return "Testate amoebae"
        case .digononta: return "Bdelloid rotifers"
        case .monogononta: return "Monogonont rotifers"
        case .nematoda, .nematode: return "Nematodes"
        case .hypotrichida: return "Hypotrich ciliates"
        case .euglenoid: return "Euglenoids"
        case .volvox: return "Volvox colonies"
        }
    }

    /// The everyday name for a detector label, or the label itself when it is not known.
    public static func commonName(forTaxon taxon: String) -> String {
        OrganismGroup(rawValue: taxon)?.commonName ?? taxon
    }
}
