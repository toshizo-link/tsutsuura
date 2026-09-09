import Foundation
import XCTest
@testable import tsutsuura

final class HomeBannerPullStateTests: XCTestCase {
    func testFirstThresholdCrossingSignalsReadinessAndClampsProgress() {
        var state = HomeBannerPullState()
        XCTAssertEqual(HomeBannerPullState.threshold, 64)
        assertIdle(state)

        XCTAssertFalse(state.begin(at: 0))
        XCTAssertTrue(state.isDragging)
        XCTAssertFalse(state.update(distance: 32))
        XCTAssertEqual(state.distance, 32)
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)
        XCTAssertFalse(state.isReady)

        XCTAssertTrue(state.update(distance: 64))
        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.progress, 1)
        XCTAssertFalse(state.update(distance: 128))
        XCTAssertEqual(state.distance, 128)
        XCTAssertEqual(state.progress, 1)
    }

    func testJitterAroundThresholdDoesNotRepeatReadinessHaptic() {
        var state = HomeBannerPullState()
        XCTAssertFalse(state.begin(at: 63))
        XCTAssertTrue(state.update(distance: 64))

        for distance in [CGFloat(65), 63, 64, 62, 70] {
            XCTAssertFalse(state.update(distance: distance), "One drag must produce at most one readiness haptic.")
            XCTAssertEqual(state.isReady, distance >= HomeBannerPullState.threshold)
        }
        XCTAssertTrue(state.finish(at: 70))
        assertIdle(state)
    }

    func testRetreatBeforeReleaseCancelsRevealAndNextDragRearmsHaptic() {
        var state = HomeBannerPullState()
        XCTAssertFalse(state.begin(at: 10))
        XCTAssertTrue(state.update(distance: 80))
        XCTAssertFalse(state.update(distance: 20))
        XCTAssertFalse(state.isReady)
        XCTAssertFalse(state.finish(at: 20), "Crossing the threshold earlier does not commit the reveal.")
        assertIdle(state)

        XCTAssertFalse(state.begin(at: 0))
        XCTAssertTrue(state.update(distance: 64), "A new drag gets its own readiness haptic.")
        XCTAssertTrue(state.finish(at: 64))
        assertIdle(state)
    }

    func testBeginAtThresholdSignalsReadinessWithoutWaitingForAnUpdate() {
        var state = HomeBannerPullState()
        XCTAssertTrue(state.begin(at: 64))
        XCTAssertTrue(state.isDragging)
        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.progress, 1)
        XCTAssertFalse(state.update(distance: 65))
        XCTAssertTrue(state.finish(at: 64))
        assertIdle(state)
    }

    func testFinishUsesCurrentReleaseDistanceAndCanRevealOnlyOnce() {
        var state = HomeBannerPullState()
        XCTAssertTrue(state.begin(at: 80))
        XCTAssertFalse(state.finish(at: 63), "Release below the threshold must cancel even without a final update callback.")
        assertIdle(state)

        XCTAssertFalse(state.begin(at: 20))
        XCTAssertTrue(state.finish(at: 64), "The final release position is authoritative even if no update delivered it.")
        assertIdle(state)
        XCTAssertFalse(state.finish(at: 100), "Repeated end callbacks cannot reveal twice.")
        assertIdle(state)
    }

    func testCancelDisarmsGestureAndIgnoresSubsequentScrollBounce() {
        var state = HomeBannerPullState()
        XCTAssertFalse(state.update(distance: 100))
        XCTAssertFalse(state.finish(at: 100))
        assertIdle(state)

        XCTAssertTrue(state.begin(at: 100))
        state.cancel()
        assertIdle(state)
        XCTAssertFalse(state.update(distance: 120), "Scroll bounce after cancellation is not an active finger drag.")
        XCTAssertFalse(state.finish(at: 120))
        assertIdle(state)
        state.cancel()
        assertIdle(state)

        XCTAssertTrue(state.begin(at: 64), "Cancellation must rearm readiness for the next real gesture.")
    }

    func testNegativeAndNonfiniteDistancesAreNormalizedAtBeginAndUpdate() {
        let invalidDistances: [CGFloat] = [-1, -.greatestFiniteMagnitude, .nan, .infinity, -.infinity]
        for distance in invalidDistances {
            var state = HomeBannerPullState()
            XCTAssertFalse(state.begin(at: distance))
            XCTAssertTrue(state.isDragging)
            XCTAssertEqual(state.distance, 0)
            XCTAssertEqual(state.progress, 0)
            XCTAssertFalse(state.isReady)

            XCTAssertTrue(state.update(distance: 64))
            XCTAssertFalse(state.update(distance: distance))
            XCTAssertEqual(state.distance, 0)
            XCTAssertEqual(state.progress, 0)
            XCTAssertFalse(state.isReady)
            XCTAssertFalse(state.update(distance: 64), "Normalizing an invalid sample must not rearm a haptic within the same drag.")
        }
    }

    func testInvalidReleaseCancelsAndAlwaysResetsState() {
        let invalidDistances: [CGFloat] = [-1, .nan, .infinity, -.infinity]
        for distance in invalidDistances {
            var state = HomeBannerPullState()
            XCTAssertTrue(state.begin(at: 80))
            XCTAssertFalse(state.finish(at: distance))
            assertIdle(state)
            XCTAssertFalse(state.finish(at: 80))
        }
    }

    private func assertIdle(
        _ state: HomeBannerPullState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(state.isDragging, file: file, line: line)
        XCTAssertFalse(state.isReady, file: file, line: line)
        XCTAssertEqual(state.distance, 0, file: file, line: line)
        XCTAssertEqual(state.progress, 0, file: file, line: line)
    }
}
