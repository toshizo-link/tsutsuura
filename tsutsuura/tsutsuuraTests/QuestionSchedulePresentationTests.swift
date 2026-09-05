import Foundation
import XCTest
@testable import tsutsuura

final class QuestionSchedulePresentationTests: XCTestCase {
    func testJapanReleaseUsesAnExplicitCalendarDateAndNoDuplicateLocalClock() throws {
        let presentation = makePresentation(zone: "Asia/Tokyo")
        XCTAssertEqual(presentation.title, "次の質問をお楽しみに")
        XCTAssertEqual(presentation.questionDateLabel, "9月5日の質問（日本時間）")
        XCTAssertEqual(presentation.releaseInScheduleTimeZone, "日本時間：9月5日 14:09")
        XCTAssertNil(presentation.releaseInLocalTimeZone)
    }

    func testTorontoShowsBothClocksInsteadOfPromisingDaytimePublication() throws {
        let presentation = makePresentation(zone: "America/Toronto")
        XCTAssertEqual(presentation.releaseInScheduleTimeZone, "日本時間：9月5日 14:09")
        XCTAssertEqual(presentation.releaseInLocalTimeZone, "この端末の時間：9月5日 1:09")
        XCTAssertEqual(presentation.title, "次の質問をお楽しみに")
    }

    func testTorontoPreviousCalendarDayIsIncludedInTheReleaseLabel() throws {
        let presentation = makePresentation(zone: "America/Toronto", release: "2026-09-05T00:15:00Z")
        XCTAssertEqual(presentation.releaseInScheduleTimeZone, "日本時間：9月5日 9:15")
        XCTAssertEqual(presentation.releaseInLocalTimeZone, "この端末の時間：9月4日 20:15")
    }

    func testReleasedJapaneseNextDayIsDatedInsteadOfCallingItTodayInToronto() throws {
        let presentation = makePresentation(
            zone: "America/Toronto", release: "2026-09-05T00:15:00Z",
            now: "2026-09-05T01:00:00Z", available: true
        )
        XCTAssertEqual(presentation.title, "9月5日の質問")
        XCTAssertEqual(presentation.questionDateLabel, "9月5日の質問（日本時間）")
    }

    func testMissingLegacyTimezoneFallsBackToJapanAndServerTimezoneCanBeDecoded() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(Question.self, from: Data(#"{"id":"1","prompt":"","date":"2026-09-05","isAvailable":false,"availableAt":"2026-09-05T05:09:00Z"}"#.utf8))
        XCTAssertNil(legacy.timeZoneIdentifier)
        XCTAssertEqual(
            QuestionSchedulePresentation(question: legacy, localTimeZone: TimeZone(identifier: "America/Toronto")!).releaseInScheduleTimeZone,
            "日本時間：9月5日 14:09"
        )
        let current = try decoder.decode(Question.self, from: Data(#"{"id":"1","prompt":"","date":"2026-09-05","timeZoneIdentifier":"Asia/Tokyo"}"#.utf8))
        XCTAssertEqual(current.timeZoneIdentifier, "Asia/Tokyo")
    }

    func testWinterOffsetAndNewYearDateRolloverAreFormattedFromTheInstant() throws {
        var question = Question(id: "1", prompt: "", publishedOn: "2027-01-01", answer: nil)
        question.availableAt = ISO8601DateFormatter().date(from: "2027-01-01T00:30:00Z")
        question.isAvailable = true
        let presentation = QuestionSchedulePresentation(
            question: question,
            now: ISO8601DateFormatter().date(from: "2027-01-01T01:00:00Z")!,
            localTimeZone: TimeZone(identifier: "America/Toronto")!
        )
        XCTAssertEqual(presentation.title, "1月1日の質問")
        XCTAssertEqual(presentation.releaseInScheduleTimeZone, "日本時間：1月1日 9:30")
        XCTAssertEqual(presentation.releaseInLocalTimeZone, "この端末の時間：12月31日 19:30")
    }

    private func makePresentation(
        zone: String,
        release: String = "2026-09-05T05:09:00Z",
        now: String = "2026-09-04T23:00:00Z",
        available: Bool = false
    ) -> QuestionSchedulePresentation {
        var question = Question(id: "1", prompt: "", publishedOn: "2026-09-05", answer: nil)
        question.availableAt = ISO8601DateFormatter().date(from: release)
        question.isAvailable = available
        question.timeZoneIdentifier = "Asia/Tokyo"
        return QuestionSchedulePresentation(
            question: question,
            now: ISO8601DateFormatter().date(from: now)!,
            localTimeZone: TimeZone(identifier: zone)!
        )
    }
}
