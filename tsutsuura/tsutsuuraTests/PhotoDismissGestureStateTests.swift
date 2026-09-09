import Foundation
import XCTest
@testable import tsutsuura

final class PhotoDismissGestureStateTests: XCTestCase {
    func testOnlyClearlyDownwardStartsCanBecomeDismissal() {
        for rejected in [CGSize(width: 20, height: 4), CGSize(width: -20, height: 4),
                         CGSize(width: 0, height: -20), CGSize(width: 20, height: 20), .zero] {
            var state = PhotoDismissGestureState()
            XCTAssertFalse(PhotoDismissGestureState.acceptsInitialTranslation(rejected))
            state.begin(translation: rejected)
            state.update(translation: CGSize(width: 0, height: 200))
            XCTAssertFalse(state.isDragging)
            XCTAssertEqual(state.distance, 0)
            XCTAssertFalse(state.finish(translation: CGSize(width: 0, height: 200)))
        }
        XCTAssertTrue(PhotoDismissGestureState.acceptsInitialTranslation(CGSize(width: 8, height: 20)))
    }

    func testPhotoTracksDownwardDragAndReleasesAtActualDistance() {
        var state = PhotoDismissGestureState()
        state.begin(translation: CGSize(width: 3, height: 15))
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.distance, 15)
        state.update(translation: CGSize(width: 8, height: 180))
        XCTAssertEqual(state.distance, 180)
        XCTAssertFalse(state.finish(translation: CGSize(width: 8, height: 119)), "Retreating before release cancels dismissal.")
        XCTAssertFalse(state.isDragging)
        XCTAssertEqual(state.distance, 0)

        state.begin(translation: CGSize(width: 0, height: 15))
        XCTAssertTrue(state.finish(translation: CGSize(width: 0, height: 120)))
        XCTAssertFalse(state.finish(translation: CGSize(width: 0, height: 200)), "Only one completion is allowed per drag.")
    }

    func testShortDragsAndUpwardRetreatNeverDismiss() {
        for release in [CGFloat(20), 60, 119, 0, -200] {
            var state = PhotoDismissGestureState()
            state.begin(translation: CGSize(width: 0, height: 12))
            XCTAssertFalse(state.finish(translation: CGSize(width: 0, height: release)))
            XCTAssertEqual(state.distance, 0)
            XCTAssertFalse(state.isDragging)
        }
    }

    func testCancellationIgnoresLateUpdatesAndNextDragCanDismiss() {
        var state = PhotoDismissGestureState()
        state.begin(translation: CGSize(width: 0, height: 20))
        state.cancel()
        state.update(translation: CGSize(width: 0, height: 200))
        XCTAssertFalse(state.finish(translation: CGSize(width: 0, height: 200)))
        XCTAssertEqual(state.distance, 0)
        state.begin(translation: CGSize(width: 0, height: 20))
        XCTAssertTrue(state.finish(translation: CGSize(width: 0, height: 200)))
    }

    func testInvalidCoordinatesCannotProduceDismissal() {
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertFalse(PhotoDismissGestureState.acceptsInitialTranslation(CGSize(width: invalid, height: 20)))
            XCTAssertFalse(PhotoDismissGestureState.acceptsInitialTranslation(CGSize(width: 0, height: invalid)))
            var state = PhotoDismissGestureState()
            state.begin(translation: CGSize(width: 0, height: 20))
            state.update(translation: CGSize(width: 0, height: invalid))
            XCTAssertEqual(state.distance, 0)
            XCTAssertFalse(state.finish(translation: CGSize(width: 0, height: invalid)))
        }
    }
}
