import Foundation
import GRDB
import SQLiteData

@Table("reference_customization")
struct ReferenceCustomizationRecord: Identifiable, Sendable {
    let id: UUID
    var name: String?
    @Column("is_removed")
    var isRemoved: Bool = false
}

@Table("account")
struct AccountRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    var currency: String = "EUR"
    @Column("can_migrate_currency")
    var canMigrateCurrency: Bool = false
}

@Table("category")
struct CategoryRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    @Column("counts_as_spending")
    var countsAsSpending: Bool = true
}

@Table("counterparty")
struct PayeeRecord: Identifiable, Sendable {
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
    var payeeID: UUID?
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
    @Column("needs_review")
    var needsReview: Bool = false
}

@Table("counterparty_alias")
struct PayeeAliasRecord: Identifiable, Sendable {
    let id: UUID
    var name: String = ""
    @Column("counterparty_id")
    var payeeID: UUID
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
    let path: String?

    init(path: String?, syncMode: Ledger.SyncMode, readOnly: Bool = false) throws {
        self.path = path
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.readonly = readOnly
        if readOnly {
            configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA query_only = ON") }
        }

        if let path {
            database = try DatabasePool(path: path, configuration: configuration)
        } else {
            database = try DatabaseQueue(configuration: configuration)
        }

        if readOnly {
            syncEngine = nil
            return
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
                    account_id TEXT REFERENCES account(id) ON DELETE SET NULL,
                    destination_account_id TEXT REFERENCES account(id) ON DELETE SET NULL
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
        migrator.registerMigration("v2_reference_customizations") { db in
            try db.execute(sql: """
                CREATE TABLE reference_customization (
                    id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                    name TEXT, is_removed INTEGER NOT NULL DEFAULT 0
                ) STRICT;
                CREATE VIEW effective_category AS
                    SELECT category.rowid AS rowid, category.id,
                        COALESCE(custom.name, category.name) AS name, category.counts_as_spending,
                        COALESCE(custom.is_removed, 0) AS is_removed
                    FROM category LEFT JOIN reference_customization AS custom ON custom.id = category.id;
                CREATE VIEW effective_account AS
                    SELECT account.rowid AS rowid, account.id,
                        COALESCE(custom.name, account.name) AS name,
                        COALESCE(custom.is_removed, 0) AS is_removed
                    FROM account LEFT JOIN reference_customization AS custom ON custom.id = account.id;
                """)
        }
        migrator.registerMigration("v2_drop_ledger_initialization") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS ledger_initialization")
        }
        migrator.registerMigration("v3_apply_payee_defaults") { db in
            try db.execute(sql: """
                UPDATE counterparty
                SET default_category_id = (
                    SELECT category_id FROM proposed_payee_default
                    WHERE counterparty_id = counterparty.id
                )
                WHERE default_category_id IS NULL
                  AND id IN (SELECT counterparty_id FROM proposed_payee_default);
                UPDATE entry
                SET category_id = (
                    SELECT default_category_id FROM counterparty
                    WHERE counterparty.id = entry.counterparty_id
                )
                WHERE category_provenance = 'inherited'
                  AND counterparty_id IN (SELECT counterparty_id FROM proposed_payee_default);
                DROP TABLE proposed_payee_default;
                """)
        }
        migrator.registerMigration("capture_analysis_spending") { db in
            try db.execute(sql: """
                CREATE VIEW spending AS
                SELECT entry.id, entry.reporting_date, entry.amount_cents,
                    entry.amount_cents / 100.0 AS amount, 'EUR' AS currency,
                    counterparty.name AS payee, category.name AS category,
                    account.name AS account, entry.account_id, entry.category_id,
                    entry.counterparty_id AS payee_id
                FROM entry
                JOIN effective_category AS category ON category.id = entry.category_id
                JOIN effective_account AS account ON account.id = entry.account_id
                LEFT JOIN counterparty ON counterparty.id = entry.counterparty_id
                WHERE entry.kind = 'expense' AND entry.trashed_on IS NULL
                    AND category.counts_as_spending = 1;
                """)
        }
        migrator.registerMigration("v4_review_inbox") { db in
            try db.execute(sql: """
                ALTER TABLE entry ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0;
                """)
        }
        migrator.registerMigration("v4_account_currency") { db in
            try db.execute(sql: """
                ALTER TABLE account ADD COLUMN currency TEXT NOT NULL DEFAULT 'EUR';
                ALTER TABLE account ADD COLUMN can_migrate_currency INTEGER NOT NULL DEFAULT 0;
                UPDATE account SET can_migrate_currency = 1;
                DROP VIEW IF EXISTS spending;
                DROP VIEW IF EXISTS effective_account;
                CREATE VIEW effective_account AS
                    SELECT account.rowid AS rowid, account.id,
                        COALESCE(custom.name, account.name) AS name,
                        account.currency,
                        COALESCE(custom.is_removed, 0) AS is_removed
                    FROM account LEFT JOIN reference_customization AS custom ON custom.id = account.id;
                CREATE VIEW spending AS
                    SELECT entry.id, entry.reporting_date, entry.amount_cents,
                        entry.amount_cents / 100.0 AS amount, account.currency AS currency,
                        counterparty.name AS payee, category.name AS category,
                        account.name AS account, entry.account_id, entry.category_id,
                        entry.counterparty_id AS payee_id
                    FROM entry
                    JOIN effective_category AS category ON category.id = entry.category_id
                    JOIN effective_account AS account ON account.id = entry.account_id
                    LEFT JOIN counterparty ON counterparty.id = entry.counterparty_id
                    WHERE entry.kind = 'expense' AND entry.trashed_on IS NULL
                        AND category.counts_as_spending = 1;
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
            ReferenceCustomizationRecord.self,
            PayeeRecord.self,
            EntryRecord.self,
            PayeeAliasRecord.self,
            ImportRowRecord.self,
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
    static let ledgerTables = ["reference_customization", "account", "category", "counterparty", "entry", "counterparty_alias", "import_row"]

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
