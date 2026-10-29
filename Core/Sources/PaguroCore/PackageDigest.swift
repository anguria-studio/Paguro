import Foundation

/// The lowercase hexadecimal SHA-256 form that Mozilla's API and the library use.
public enum PackageDigest {
    public static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
