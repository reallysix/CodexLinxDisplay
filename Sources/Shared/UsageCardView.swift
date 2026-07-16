import SwiftUI

enum UsageCardLayout {
  static let width: CGFloat = 142
  static let height: CGFloat = 428
  static let defaultSafeArea: CGFloat = 56
  static let minimumSafeArea: CGFloat = 44
  static let maximumSafeArea: CGFloat = 80
}

struct UsageCardView: View {
  let snapshot: UsageSnapshot?
  let safeAreaHeight: CGFloat

  private let background = Color(red: 8 / 255, green: 11 / 255, blue: 18 / 255)
  private let cardBackground = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
  private let insetBackground = Color(red: 11 / 255, green: 18 / 255, blue: 32 / 255)
  private let border = Color(red: 38 / 255, green: 52 / 255, blue: 74 / 255)
  private let accent = Color(red: 85 / 255, green: 230 / 255, blue: 184 / 255)
  private let primaryText = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
  private let secondaryText = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
  private let tertiaryText = Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)

  var body: some View {
    ZStack(alignment: .top) {
      background

      card
        .frame(width: 124, height: max(320, UsageCardLayout.height - safeAreaHeight - 10))
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(border, lineWidth: 1)
        }
        .padding(.top, safeAreaHeight + 1)
    }
    .frame(width: UsageCardLayout.width, height: UsageCardLayout.height)
    .clipped()
  }

  private var card: some View {
    VStack(spacing: 0) {
      header
        .frame(height: 38)

      Rectangle()
        .fill(border)
        .frame(height: 1)
        .padding(.horizontal, 9)

      usageSection
        .frame(height: 112)

      resetCard
        .frame(width: 106, height: 70)
        .padding(.top, 12)

      Spacer(minLength: 16)

      autoResetSection
        .padding(.bottom, 16)
    }
  }

  private var header: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(accent)
        .frame(width: 8, height: 8)

      Text("CODEX")
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(primaryText)

      Spacer(minLength: 2)

      Text(snapshot == nil ? "等待" : "实时")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(snapshot == nil ? tertiaryText : accent)
    }
    .padding(.horizontal, 9)
  }

  private var usageSection: some View {
    VStack(spacing: 0) {
      Text(snapshot?.windowTitle ?? "等待同步")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(secondaryText)
        .padding(.top, 11)

      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(snapshot.map { "\($0.remainingPercent)" } ?? "--")
          .font(.system(size: 41, weight: .bold, design: .rounded))
          .foregroundStyle(primaryText)

        Text("%")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(accent)
      }
      .frame(height: 50)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(border)
          Capsule()
            .fill(accent)
            .frame(width: proxy.size.width * CGFloat(snapshot?.remainingPercent ?? 0) / 100)
        }
      }
      .frame(width: 106, height: 8)

      Text(snapshot?.windowDescription ?? "尚无数据")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(tertiaryText)
        .padding(.top, 7)
    }
  }

  private var resetCard: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(insetBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(border, lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 4) {
        Text("可用重置")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(secondaryText)

        HStack(alignment: .firstTextBaseline) {
          Text(snapshot.map { "\($0.availableResetCount)" } ?? "--")
            .font(.system(size: 31, weight: .bold, design: .rounded))
            .foregroundStyle(primaryText)

          Spacer()

          Text("次")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(accent)
        }
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 9)
    }
  }

  private var autoResetSection: some View {
    VStack(spacing: 5) {
      Text("自动重置")
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(tertiaryText)

      Text(resetDateText)
        .font(.system(size: 19, weight: .bold, design: .rounded))
        .foregroundStyle(primaryText)

      Text(resetTimeText)
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(accent)
    }
  }

  private var resetDateText: String {
    guard let date = snapshot?.resetDate else { return "--月--日" }
    return Self.dateFormatter.string(from: date)
  }

  private var resetTimeText: String {
    guard let date = snapshot?.resetDate else { return "--:--" }
    return Self.timeFormatter.string(from: date)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}
