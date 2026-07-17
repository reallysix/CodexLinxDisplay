import Foundation

struct UsageSnapshot: Equatable, Sendable {
  let remainingPercent: Int
  let resetDate: Date?
  let windowMinutes: Int?
  let availableResetCount: Int
  let planType: String?

  var windowTitle: String {
    guard let windowMinutes else { return "周期剩余" }
    if windowMinutes >= 10_080 { return "本周剩余" }
    if windowMinutes >= 1_440 { return "本日剩余" }
    if windowMinutes == 300 { return "5 小时剩余" }
    return "周期剩余"
  }

  var windowDescription: String {
    guard let windowMinutes else { return "当前周期" }
    if windowMinutes % 1_440 == 0 {
      return "\(windowMinutes / 1_440) 天周期"
    }
    if windowMinutes % 60 == 0 {
      return "\(windowMinutes / 60) 小时周期"
    }
    return "\(windowMinutes) 分钟周期"
  }

  static let sample = UsageSnapshot(
    remainingPercent: 98,
    resetDate: Calendar.current.date(
      from: DateComponents(year: 2026, month: 7, day: 23, hour: 15, minute: 19)),
    windowMinutes: 10_080,
    availableResetCount: 3,
    planType: "plus"
  )
}
