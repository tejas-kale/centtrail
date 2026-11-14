import Foundation
import GRDB
import SQLiteData

@Table("account")
struct AccountRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
}

@Table("category")
struct CategoryRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    @Column("counts_as_spending")
    var countsAsSpending: Bool = true
}

@Table("counterparty")
struct CounterpartyRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    @Column("default_category_id")
    var defaultCategoryID: UUID?
}

@Table("entry")
struct EntryRecord: Identifiable, Sendable {
    let id: UUID
    @Column("amount_cents")
    var amountCents: Int = 0
    var kind: String = "expense"
    @Column("counterparty_id")
    var counterpartyID: UUID?
    @Column("account_id")
    var accountID: UUID?
    @Column("destination_account_id")
    var destinationAccountID: UUID?
    @Column("reporting_date")
    var reportingDate: String = ""
    @Column("category_id")
    var categoryID: UUID?
    @Column("category_provenance")
    var categoryProvenance: String = "inherited"
    var note: String?
    @Column("trashed_on")
    var trashedOn: String?
}

@Table("counterparty_alias")
struct CounterpartyAliasRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    @Column("counterparty_id")
    var counterpartyID: UUID
}

@Table("import_row")
struct ImportRowRecord: Identifiable, Sendable {
    let id: UUID
    @Column("entry_id")
    var entryID: UUID?
    @Column("source_timestamp")
    var sourceTimestamp: String = ""
    @Column("amount_cents")
    var amountCents: Int = 0
    var payee: String = ""
    @Column("source_account")
    var sourceAccount: String = ""
}

@Table("proposed_payee_default")
struct ProposedPayeeDefaultRecord: Identifiable, Sendable {
    @Column("counterparty_id", primaryKey: true)
    let counterpartyID: UUID
    @Column("category_id")
    var categoryID: UUID

    var id: UUID { counterpartyID }
}

private final class DatabaseBox: @unchecked Sendable {
    let db: Database
    init(_ db: Database) { self.db = db }
}

private enum ActiveDatabase {
    @TaskLocal static var current: DatabaseBox?
}

final class SQLiteConnection {
    let database: any DatabaseWriter
    let syncEngine: SyncEngine?

    init(path: String?, syncMode: Ledger.SyncMode) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        if let path {
            database = try DatabasePool(path: path, configuration: configuration)
        } else {
            database = try DatabaseQueue(configuration: configuration)
        }

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_synced_schema") { db in
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "category" (
                    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    "name" TEXT NOT NULL DEFAULT '',
                    "counts_as_spending" INTEGER NOT NULL DEFAULT 1
                ) STRICT
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "counterparty" (
                    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    "name" TEXT NOT NULL DEFAULT '',
                    "default_category_id" TEXT REFERENCES "category"("id") ON DELETE SET NULL
                ) STRICT
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "entry" (
                    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    "amount_cents" INTEGER NOT NULL DEFAULT 0,
                    "kind" TEXT NOT NULL DEFAULT 'expense',
                    "counterparty_id" TEXT NOT NULL REFERENCES "counterparty"("id") ON DELETE CASCADE,
                    "reporting_date" TEXT NOT NULL DEFAULT '',
                    "category_id" TEXT NOT NULL REFERENCES "category"("id") ON DELETE CASCADE,
                    "category_provenance" TEXT NOT NULL DEFAULT 'inherited',
                    "note" TEXT,
                    "trashed_on" TEXT
                ) STRICT
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "counterparty_alias" (
                    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    "name" TEXT NOT NULL DEFAULT '',
                    "counterparty_id" TEXT NOT NULL REFERENCES "counterparty"("id") ON DELETE CASCADE
                ) STRICT
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "import_row" (
                    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    "entry_id" TEXT REFERENCES "entry"("id") ON DELETE SET NULL,
                    "source_timestamp" TEXT NOT NULL DEFAULT '',
                    "amount_cents" INTEGER NOT NULL DEFAULT 0,
                    "payee" TEXT NOT NULL DEFAULT '',
                    "source_account" TEXT NOT NULL DEFAULT ''
                ) STRICT
                """
            )
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS "proposed_payee_default" (
                    "counterparty_id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE REFERENCES "counterparty"("id") ON DELETE CASCADE,
                    "category_id" TEXT NOT NULL REFERENCES "category"("id") ON DELETE CASCADE
                ) STRICT
                """
            )
        }
        migrator.registerMigration("v2_accounts") { db in
            try db.execute(sql: """
                CREATE TABLE account (
                    id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    name TEXT NOT NULL DEFAULT ''
                ) STRICT;
                CREATE TABLE ledger_initialization (key TEXT PRIMARY KEY NOT NULL) STRICT;
                """)
        }
        migrator.registerMigration("v2_entry_accounts") { db in
            try db.execute(sql: """
                CREATE TABLE entry_accounts (
                    id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    amount_cents INTEGER NOT NULL DEFAULT 0,
                    kind TEXT NOT NULL DEFAULT 'expense',
                    counterparty_id TEXT REFERENCES counterparty(id) ON DELETE SET NULL,
                    reporting_date TEXT NOT NULL DEFAULT '',
                    category_id TEXT REFERENCES category(id) ON DELETE SET NULL,
                    category_provenance TEXT NOT NULL DEFAULT 'inherited',
                    note TEXT,
                    trashed_on TEXT,
                    account_id TEXT REFERENCES account(id) ON DELETE RESTRICT,
                    destination_account_id TEXT REFERENCES account(id) ON DELETE RESTRICT
                ) STRICT;
                INSERT INTO entry_accounts (id, amount_cents, kind, counterparty_id, reporting_date, category_id, category_provenance, note, trashed_on)
                    SELECT id, amount_cents, kind, counterparty_id, reporting_date, category_id, category_provenance, note, trashed_on FROM entry;
                """)
            // Preserve import identities while rebuilding the transaction table.
            try db.execute(sql: "CREATE TEMP TABLE saved_import_rows AS SELECT * FROM import_row")
            try db.execute(sql: "DROP TABLE import_row; DROP TABLE entry; ALTER TABLE entry_accounts RENAME TO entry")
            try db.execute(sql: """
                CREATE TABLE import_row (
                    id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    entry_id TEXT REFERENCES entry(id) ON DELETE SET NULL,
                    source_timestamp TEXT NOT NULL DEFAULT '', amount_cents INTEGER NOT NULL DEFAULT 0,
                    payee TEXT NOT NULL DEFAULT '', source_account TEXT NOT NULL DEFAULT ''
                ) STRICT;
                INSERT INTO import_row SELECT * FROM saved_import_rows;
                DROP TABLE saved_import_rows;
                """)
        }
        try migrator.migrate(database)

        switch syncMode {
        case .disabled:
            syncEngine = nil
        case .enabled(let containerIdentifier):
            syncEngine = try Self.makeSyncEngine(for: database, containerIdentifier: containerIdentifier)
        }
    }

    private static func makeSyncEngine(
        for database: any DatabaseWriter,
        containerIdentifier: String
    ) throws -> SyncEngine {
        try SyncEngine(
            for: database,
            tables: CategoryRecord.self,
            AccountRecord.self,
            CounterpartyRecord.self,
            EntryRecord.self,
            CounterpartyAliasRecord.self,
            ImportRowRecord.self,
            ProposedPayeeDefaultRecord.self,
            containerIdentifier: containerIdentifier
        )
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let arguments = StatementArguments(bindings.map(\.databaseValue))
        if let db = ActiveDatabase.current?.db {
            try db.execute(sql: sql, arguments: arguments)
        } else {
            try database.write { db in
                try db.execute(sql: sql, arguments: arguments)
            }
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let arguments = StatementArguments(bindings.map(\.databaseValue))
        if let db = ActiveDatabase.current?.db {
            return try Self.fetchRows(db, sql: sql, arguments: arguments)
        }
        return try database.read { db in
            try Self.fetchRows(db, sql: sql, arguments: arguments)
        }
    }

    func inTransaction<T>(_ body: () throws -> T) throws -> T {
        if ActiveDatabase.current != nil {
            return try body()
        }
        return try database.write { db in
            try ActiveDatabase.$current.withValue(DatabaseBox(db)) {
                try body()
            }
        }
    }

    private static func fetchRows(_ db: Database, sql: String, arguments: StatementArguments) throws -> [[SQLiteValue]] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        return rows.map { row -> [SQLiteValue] in
            row.databaseValues.map(SQLiteValue.init)
        }
    }
}

enum SQLiteValue: Equatable {
    case text(String)
    case integer(Int64)
    case null

    init(_ databaseValue: DatabaseValue) {
        switch databaseValue.storage {
        case .null:
            self = .null
        case .int64(let number):
            self = .integer(number)
        case .string(let text):
            self = .text(text)
        case .double(let number):
            self = .integer(Int64(number))
        case .blob:
            self = .null
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .text(let value): value.databaseValue
        case .integer(let number): number.databaseValue
        case .null: .null
        }
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}

/// Keeps a change observer alive. Observing stops on `cancel()` or when the
/// observation is released.
public final class LedgerObservation {
    private var cancellable: AnyDatabaseCancellable?

    init(_ cancellable: AnyDatabaseCancellable) {
        self.cancellable = cancellable
    }

    public func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }

    deinit {
        cancellable?.cancel()
    }
}

extension SQLiteConnection {
    static let ledgerTables = ["account", "category", "counterparty", "entry", "counterparty_alias", "import_row", "proposed_payee_default"]

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> LedgerObservation {
        let regions = Self.ledgerTables.map { GRDB.Table($0) as any DatabaseRegionConvertible }
        let observation = DatabaseRegionObservation(tracking: regions)
        let cancellable = observation.start(
            in: database,
            onError: { _ in },
            onChange: { _ in onChange() }
        )
        return LedgerObservation(cancellable)
    }
}
