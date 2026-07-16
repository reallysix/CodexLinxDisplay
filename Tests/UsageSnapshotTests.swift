import XCTest

@testable import CodexLinxDisplay

final class UsageSnapshotTests: XCTestCase {
  func testWeeklyLabelsAreChinese() {
    let snapshot = UsageSnapshot(
      remainingPercent: 98,
      resetDate: nil,
      windowMinutes: 10_080,
      availableResetCount: 3,
      planType: "plus"
    )

    XCTAssertEqual(snapshot.windowTitle, "本周剩余")
    XCTAssertEqual(snapshot.windowDescription, "7 天周期")
  }

  func testFiveHourLabelsAreChinese() {
    let snapshot = UsageSnapshot(
      remainingPercent: 50,
      resetDate: nil,
      windowMinutes: 300,
      availableResetCount: 0,
      planType: nil
    )

    XCTAssertEqual(snapshot.windowTitle, "5 小时剩余")
    XCTAssertEqual(snapshot.windowDescription, "5 小时周期")
  }
}
