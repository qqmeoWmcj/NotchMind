import Foundation
import SQLite3

public actor DedupeStore {
    private var db: OpaquePointer?
    private var inFlightKeys: Set<String> = []
    private let dbURL: URL

    public init(dbURL: URL) throws {
        self.dbURL = dbURL
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        if sqlite3_open(dbURL.path, &handle) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw NSError(domain: "DedupeStore", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        self.db = handle
        try Self.createTables(db: handle)
    }

    isolated deinit {
        if let db { sqlite3_close(db) }
    }

    private static func createTables(db: OpaquePointer?) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS seen_keys (
            canonical_key TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            entry_id TEXT,
            created_at TEXT NOT NULL
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "create table failed"
            throw NSError(domain: "DedupeStore", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Atomically checks both persistent SQLite records and in-flight keys.
    /// Returns true if the caller acquired the right to process this key.
    public func beginIfNew(canonicalKey: String) -> Bool {
        if inFlightKeys.contains(canonicalKey) { return false }
        if existsInDB(canonicalKey: canonicalKey) { return false }
        inFlightKeys.insert(canonicalKey)
        return true
    }

    public func markCommitted(canonicalKey: String, kind: String, entryID: String) {
        inFlightKeys.remove(canonicalKey)
        let sql = "INSERT OR REPLACE INTO seen_keys (canonical_key, kind, entry_id, created_at) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, canonicalKey, -1, transient)
        sqlite3_bind_text(stmt, 2, kind, -1, transient)
        sqlite3_bind_text(stmt, 3, entryID, -1, transient)
        sqlite3_bind_text(stmt, 4, KnowledgeEntry.nowTimestamp(), -1, transient)
        sqlite3_step(stmt)
    }

    public func releaseInFlight(canonicalKey: String) {
        inFlightKeys.remove(canonicalKey)
    }

    public func hasSeen(canonicalKey: String) -> Bool {
        inFlightKeys.contains(canonicalKey) || existsInDB(canonicalKey: canonicalKey)
    }

    public func deleteByEntryID(_ entryID: String) {
        let sql = "DELETE FROM seen_keys WHERE entry_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, entryID, -1, transient)
        sqlite3_step(stmt)
    }

    public func deleteByCanonicalKey(_ canonicalKey: String) {
        inFlightKeys.remove(canonicalKey)
        let sql = "DELETE FROM seen_keys WHERE canonical_key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, canonicalKey, -1, transient)
        sqlite3_step(stmt)
    }

    private func existsInDB(canonicalKey: String) -> Bool {
        let sql = "SELECT 1 FROM seen_keys WHERE canonical_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, canonicalKey, -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
