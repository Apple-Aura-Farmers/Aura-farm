import Foundation

/// The organism groups the soil detector knows, with the names a farmer would use.
///
/// Reports carry the detector's class label as text, so a label added by a newer model still
/// reads: it is shown as it is until it is added here.
public enum OrganismGroup: String, CaseIterable, Sendable {
    case arcellinida = "Arcellinida"
    case digononta = "Digononta"
    case monogononta = "Monogononta"
    case nematoda = "Nematoda"
    case hypotrichida = "Hypotrichida"

    /// The everyday name, for example "Nematodes".
    public var commonName: String {
        switch self {
        case .arcellinida: return "Testate amoebae"
        case .digononta: return "Bdelloid rotifers"
        case .monogononta: return "Monogonont rotifers"
        case .nematoda: return "Nematodes"
        case .hypotrichida: return "Hypotrich ciliates"
        }
    }

    /// The everyday name for a detector label, or the label itself when it is not known.
    public static func commonName(forTaxon taxon: String) -> String {
        OrganismGroup(rawValue: taxon)?.commonName ?? taxon
    }
}
