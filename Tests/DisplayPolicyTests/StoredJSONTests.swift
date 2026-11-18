import DisplayPolicy
import Foundation
import XCTest

/// A value that cannot be saved, or saved data that cannot be read, must not wipe what is saved.
final class StoredJSONTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let key = "values"

    override func setUp() {
        suite = "StoredJSONTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func saved() throws -> [String: Double]? {
        try defaults.data(forKey: key).map { try JSONDecoder().decode([String: Double].self, from: $0) }
    }

    func testAValueIsSaved() throws {
        XCTAssertTrue(StoredJSON.save(["a": 1.5], forKey: key, in: defaults))
        XCTAssertEqual(try saved(), ["a": 1.5])
    }

    func testAValueThatCannotBeEncodedKeepsTheSavedOne() throws {
        StoredJSON.save(["a": 1.5], forKey: key, in: defaults)
        // JSON has no infinite numbers, so the encoding fails.
        XCTAssertFalse(StoredJSON.save(["a": 1.5, "b": .infinity], forKey: key, in: defaults))
        XCTAssertEqual(try saved(), ["a": 1.5])
    }

    // MARK: Loading

    private struct Item: Codable, Equatable {
        var name: String
        var value: Double
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func data(_ json: String) -> Data { Data(json.utf8) }

    /// The keys of the backups of `key`.
    private func backupKeys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(key + ".") }.sorted()
    }

    func testNothingSavedIsNothingLoaded() {
        let (value, backupKey) = StoredJSON.load([Item].self, forKey: key, in: defaults, date: date)
        XCTAssertNil(value)
        XCTAssertNil(backupKey)
        XCTAssertEqual(backupKeys(), [])
    }

    func testReadableDataStaysWhereItIs() {
        let saved = data(#"[{"name": "a", "value": 1}]"#)
        defaults.set(saved, forKey: key)
        let (value, backupKey) = StoredJSON.load([Item].self, forKey: key, in: defaults, date: date)
        XCTAssertEqual(value, [Item(name: "a", value: 1)])
        XCTAssertNil(backupKey)
        XCTAssertEqual(defaults.data(forKey: key), saved)
        XCTAssertEqual(backupKeys(), [])
    }

    func testDataThatCannotBeReadIsKeptUnderABackupKey() throws {
        // For example from a newer version of the app, with another format.
        let saved = data(#"[{"name": "a", "value": {"level": 1}}]"#)
        defaults.set(saved, forKey: key)
        let (value, backupKey) = StoredJSON.load([Item].self, forKey: key, in: defaults, date: date)
        XCTAssertNil(value)
        let backup = try XCTUnwrap(backupKey)
        XCTAssertNotEqual(backup, key)
        XCTAssertEqual(defaults.data(forKey: backup), saved)
    }

    func testDataThatCannotBeReadIsBackedUpOnlyOnce() throws {
        // It leaves the main key, so the next launch neither reads it again nor makes another backup.
        let saved = data(#"[{"name": "a", "value": {"level": 1}}]"#)
        defaults.set(saved, forKey: key)
        let backup = try XCTUnwrap(StoredJSON.load([Item].self, forKey: key, in: defaults, date: date).backupKey)
        let (value, backupKey) = StoredJSON.load([Item].self, forKey: key, in: defaults, date: date)
        XCTAssertNil(value)
        XCTAssertNil(backupKey)
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(backupKeys(), [backup])
        XCTAssertEqual(defaults.data(forKey: backup), saved)
    }

    func testALaterSaveKeepsTheBackup() throws {
        let saved = data(#"[{"name": "a", "value": {"level": 1}}]"#)
        defaults.set(saved, forKey: key)
        let backup = try XCTUnwrap(StoredJSON.load([Item].self, forKey: key, in: defaults, date: date).backupKey)
        StoredJSON.save([Item(name: "b", value: 2)], forKey: key, in: defaults)
        XCTAssertEqual(defaults.data(forKey: backup), saved)
        XCTAssertEqual(StoredJSON.load([Item].self, forKey: key, in: defaults, date: date).value, [Item(name: "b", value: 2)])
    }

    func testTwoBackupsAtTheSameTimeAreBothKept() throws {
        let first = data("first")
        defaults.set(first, forKey: key)
        let firstBackup = try XCTUnwrap(StoredJSON.load([Item].self, forKey: key, in: defaults, date: date).backupKey)
        let second = data("second")
        defaults.set(second, forKey: key)
        let secondBackup = try XCTUnwrap(StoredJSON.load([Item].self, forKey: key, in: defaults, date: date).backupKey)
        XCTAssertNotEqual(firstBackup, secondBackup)
        XCTAssertEqual(defaults.data(forKey: firstBackup), first)
        XCTAssertEqual(defaults.data(forKey: secondBackup), second)
    }

    func testPresetsThatCannotBeReadSurviveTheNextSave() throws {
        // Presets in a format this version cannot read: the next save must not write over them.
        let saved = data(#"[{"name": "Desk", "displays": {"version": 2, "list": []}}]"#)
        defaults.set(saved, forKey: key)
        let (presets, backupKey) = StoredJSON.load([Preset].self, forKey: key, in: defaults, date: date)
        XCTAssertNil(presets)
        let backup = try XCTUnwrap(backupKey)
        StoredJSON.save([Preset(name: "Laptop only", displays: [])], forKey: key, in: defaults)
        XCTAssertEqual(defaults.data(forKey: backup), saved)
    }

    // MARK: Loading entries

    func testAnEntryThatCannotBeReadKeepsTheOthers() throws {
        let saved = data(#"{"a": {"name": "a", "value": 1}, "b": {"name": "b"}, "c": {"name": "c", "value": 3}}"#)
        defaults.set(saved, forKey: key)
        let (entries, backupKey) = StoredJSON.loadEntries(Item.self, forKey: key, in: defaults, date: date)
        XCTAssertEqual(entries, ["a": Item(name: "a", value: 1), "c": Item(name: "c", value: 3)])
        // All of it, the entry that cannot be read too.
        let backup = try XCTUnwrap(backupKey)
        XCTAssertEqual(defaults.data(forKey: backup), saved)
    }

    func testAfterABadEntryTheNextLoadMakesNoNewBackup() throws {
        defaults.set(data(#"{"a": {"name": "a", "value": 1}, "b": {"name": "b"}}"#), forKey: key)
        _ = try XCTUnwrap(StoredJSON.loadEntries(Item.self, forKey: key, in: defaults, date: date).backupKey)
        let (entries, backupKey) = StoredJSON.loadEntries(Item.self, forKey: key, in: defaults, date: date)
        XCTAssertEqual(entries, ["a": Item(name: "a", value: 1)])
        XCTAssertNil(backupKey)
        XCTAssertEqual(backupKeys().count, 1)
    }

    func testEntriesThatCannotBeReadAtAllAreKeptUnderABackupKey() throws {
        let saved = data(#"[1, 2, 3]"#)
        defaults.set(saved, forKey: key)
        let (entries, backupKey) = StoredJSON.loadEntries(Item.self, forKey: key, in: defaults, date: date)
        XCTAssertEqual(entries, [:])
        let backup = try XCTUnwrap(backupKey)
        StoredJSON.save(["d": Item(name: "d", value: 4)], forKey: key, in: defaults)
        XCTAssertEqual(defaults.data(forKey: backup), saved)
    }

    func testReadableEntriesStayWhereTheyAre() {
        let saved = data(#"{"a": {"name": "a", "value": 1}}"#)
        defaults.set(saved, forKey: key)
        let (entries, backupKey) = StoredJSON.loadEntries(Item.self, forKey: key, in: defaults, date: date)
        XCTAssertEqual(entries, ["a": Item(name: "a", value: 1)])
        XCTAssertNil(backupKey)
        XCTAssertEqual(defaults.data(forKey: key), saved)
    }

    // MARK: Calibration record

    func testACalibrationRecordThatCannotBeReadIsKeptUnderABackupKey() throws {
        let saved = data("not a record")
        defaults.set(saved, forKey: key)
        let (record, backupKey) = StoredJSON.load(CalibrationRecord.self, forKey: key, in: defaults, date: date)
        XCTAssertNil(record)
        XCTAssertEqual(defaults.data(forKey: try XCTUnwrap(backupKey)), saved)
    }
}
