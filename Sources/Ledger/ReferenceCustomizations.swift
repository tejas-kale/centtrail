import Foundation

extension Ledger {
    // Bootstrap rows never carry mutable user choices. Fresh devices may upload
    // their immutable defaults; this separate synced record keeps edits and
    // removals independent of those later writes. UUIDs are global across both
    // categories and accounts, so the same overlay serves either reference.
    func renameReference(_ id: UUID, to name: String) throws {
        try connection.execute("""
            INSERT INTO reference_customization (id, name) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name
            """, bindings: [.text(stored(id)), .text(name)])
    }

    func removeReference(_ id: UUID) throws {
        try connection.execute("""
            INSERT INTO reference_customization (id, is_removed) VALUES (?, 1)
            ON CONFLICT(id) DO UPDATE SET is_removed = 1
            """, bindings: [.text(stored(id))])
    }
}
