import CryptoKit
import Foundation

/// Category names as supplied for v1. Bureaucracy keeps the trailing space
/// from the source list; seeding trims surrounding whitespace.
enum OwnerCategories {
    static let sourceNames = [
        "Anagha",
        "Bureaucracy ",
        "Electronics",
        "Entertainment",
        "Flight",
        "Friend",
        "Hotel",
        "Household Requirements",
        "Ishwa",
        "Kindergeld",
        "Kita",
        "Medicine",
        "Reading",
        "Rent",
        "Restaurant",
        "Salary",
        "Savings",
        "Self Care",
        "Shopping",
        "Software",
        "Study",
        "Supermarket",
        "Taxi",
        "Train",
        "Utilities",
        "Vacation",
    ]

    /// Generates a deterministic RFC-4122 UUID for a canonical category name so
    /// fresh installs across devices seed the exact same primary keys without
    /// creating duplicate rows on CloudKit sync.
    static func deterministicID(for canonicalName: String) -> UUID {
        let digest = SHA256.hash(data: Data("com.tejaskale.centtrail.category:\(canonicalName)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
