import DisplayPolicy
import Foundation
import XCTest

/// A value that cannot be saved must not wipe what is saved.
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
        StoredJSON.save(["a": 1.5], forKey: key, in: defaults)
        XCTAssertEqual(try saved(), ["a": 1.5])
    }

    func testAValueThatCannotBeEncodedKeepsTheSavedOne() throws {
        StoredJSON.save(["a": 1.5], forKey: key, in: defaults)
        // JSON has no infinite numbers, so the encoding fails.
        StoredJSON.save(["a": 1.5, "b": .infinity], forKey: key, in: defaults)
        XCTAssertEqual(try saved(), ["a": 1.5])
    }
}
