import Foundation

/// Both hand-built app bundles carry the same Localizable.strings tables.
/// Keep lookups in the executable's bundle, including the login-item player.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
}
