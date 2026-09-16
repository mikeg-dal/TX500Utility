import XCTest
@testable import TX500Kit

final class BackupLibraryTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupLibraryTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleBackup(_ fill: UInt8) throws -> SettingsBackup {
        try SettingsBackup(bytes: [UInt8](repeating: fill, count: TX500Protocol.Settings.byteCount))
    }

    func testSaveAndImportAppearWithSource() throws {
        let library = try BackupLibrary(directory: directory)
        try library.save(sampleBackup(1))

        let external = directory.deletingLastPathComponent().appendingPathComponent("My Old Radio.set")
        try sampleBackup(2).fileData.write(to: external)
        defer { try? FileManager.default.removeItem(at: external) }
        try library.importFile(from: external)

        let entries = library.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.source)), [.radio, .imported])
        let imported = try XCTUnwrap(entries.first { $0.source == .imported })
        XCTAssertEqual(imported.displayName, "My_Old_Radio")
        XCTAssertEqual(try library.load(imported), try sampleBackup(2))
    }

    func testImportRejectsWrongSize() throws {
        let library = try BackupLibrary(directory: directory)
        let bad = directory.appendingPathComponent("bad.bin")
        try Data([1, 2, 3]).write(to: bad)
        XCTAssertThrowsError(try library.importFile(from: bad))
    }

    func testSameSecondSavesDoNotOverwrite() throws {
        let library = try BackupLibrary(directory: directory)
        let now = Date()
        try library.save(sampleBackup(1), date: now)
        try library.save(sampleBackup(2), date: now)
        XCTAssertEqual(library.entries().count, 2)
    }

    func testDeleteRemovesEntry() throws {
        let library = try BackupLibrary(directory: directory)
        try library.save(sampleBackup(1))
        let entry = try XCTUnwrap(library.entries().first)
        try library.delete(entry)
        XCTAssertTrue(library.entries().isEmpty)
    }
}
