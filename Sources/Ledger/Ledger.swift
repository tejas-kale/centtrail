import Foundation

public struct LedgerError: Error, Equatable {
    public let message: String
}

public struct Category: Hashable, Sendable, Identifiable {
    public let id: ID
    public let name: String

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(id: ID, name: String) {
        self.id = id
        self.name = name
    }
}

public final class Ledger {
    private let connection: SQLiteConnection

    public static func openInMemory() throws -> Ledger {
        try Ledger(path: ":memory:")
    }

    init(path: String) throws {
        connection = try SQLiteConnection(path: path)
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS category (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL UNIQUE
            )
            """
        )
        try seedCategories()
    }

    public func categories() throws -> [Category] {
        let rows = try connection.query("SELECT id, name FROM category ORDER BY rowid")
        return try rows.map { row in
            guard row.count == 2, let idText = row[0].text, let name = row[1].text, let id = UUID(uuidString: idText) else {
                throw LedgerError(message: "The ledger returned a category it could not read.")
            }
            return Category(id: Category.ID(rawValue: id), name: name)
        }
    }

    private func seedCategories() throws {
        for sourceName in OwnerCategories.sourceNames {
            let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            try connection.execute(
                "INSERT INTO category (id, name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING",
                bindings: [.text(UUID().uuidString.lowercased()), .text(name)]
            )
        }
    }
}
