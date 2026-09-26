import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
  private var storageDirectory: URL!

  override func setUpWithError() throws {
    storageDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: storageDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: storageDirectory)
  }

  func testSameDayReadWriteAccumulatesBytes() throws {
    XCTAssertEqual(
      try BudgetFileStore.access(day: "2026-09-25", spending: 100, in: storageDirectory),
      100
    )
    XCTAssertEqual(
      try BudgetFileStore.access(day: "2026-09-25", spending: 50, in: storageDirectory),
      150
    )
    XCTAssertEqual(try BudgetFileStore.read(day: "2026-09-25", in: storageDirectory), 150)
  }

  func testDifferentDayStartsAtZero() throws {
    _ = try BudgetFileStore.access(day: "2026-09-24", spending: 100, in: storageDirectory)
    XCTAssertEqual(try BudgetFileStore.access(day: "2026-09-25", in: storageDirectory), 0)
  }

  func testNegativeBytesCannotReduceBudget() throws {
    _ = try BudgetFileStore.access(day: "2026-09-25", spending: 100, in: storageDirectory)
    XCTAssertEqual(
      try BudgetFileStore.access(day: "2026-09-25", spending: -20, in: storageDirectory),
      100
    )
  }

  func testDirectoryAndFileAreExcludedFromBackup() throws {
    _ = try BudgetFileStore.access(day: "2026-09-25", spending: 1, in: storageDirectory)
    let file = storageDirectory.appendingPathComponent(BudgetFileStore.fileName)
    XCTAssertEqual(
      try storageDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup,
      true
    )
    XCTAssertEqual(
      try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true
    )
  }
}
