import Foundation

/// The shared question date belongs to the server's family calendar. The
/// device timezone only changes the companion clock shown to the reader.
struct QuestionSchedulePresentation: Equatable, Sendable {
    let title: String
    let questionDateLabel: String
    let releaseInScheduleTimeZone: String?
    let releaseInLocalTimeZone: String?

    init(
        question: Question,
        now: Date = .now,
        localTimeZone: TimeZone = .autoupdatingCurrent
    ) {
        let scheduleTimeZone = question.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(identifier: "Asia/Tokyo")!
        let scheduleName = scheduleTimeZone.identifier == "Asia/Tokyo"
            ? "日本時間"
            : scheduleTimeZone.localizedName(for: .generic, locale: Locale(identifier: "ja_JP"))
                ?? scheduleTimeZone.identifier
        let dateParser = Self.formatter("yyyy-MM-dd", in: scheduleTimeZone)
        dateParser.isLenient = false
        let parsedDay = dateParser.date(from: question.publishedOn).flatMap {
            dateParser.string(from: $0) == question.publishedOn ? $0 : nil
        }
        let dayLabel = parsedDay.map {
            Self.formatter("M月d日", in: scheduleTimeZone).string(from: $0)
        }
        questionDateLabel = dayLabel.map { "\($0)の質問（\(scheduleName)）" }
            ?? "家族への質問（\(scheduleName)）"
        let localToday = Self.formatter("yyyy-MM-dd", in: localTimeZone).string(from: now)
        if question.isAvailable == false {
            title = "次の質問をお楽しみに"
        } else if question.publishedOn == localToday {
            title = "本日の質問!"
        } else {
            title = dayLabel.map { "\($0)の質問" } ?? "家族への質問"
        }

        if let release = question.availableAt {
            let format = "M月d日 H:mm"
            releaseInScheduleTimeZone = "\(scheduleName)：\(Self.formatter(format, in: scheduleTimeZone).string(from: release))"
            releaseInLocalTimeZone = localTimeZone.identifier == scheduleTimeZone.identifier
                ? nil
                : "この端末の時間：\(Self.formatter(format, in: localTimeZone).string(from: release))"
        } else {
            releaseInScheduleTimeZone = nil
            releaseInLocalTimeZone = nil
        }
    }

    private static func formatter(_ format: String, in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
