import XCTest
@testable import QuiteNote

final class RecordingSnapTests: XCTestCase {
    func testSnapsWhenDraggingTowardBoundaryFromLeftToRight() {
        let target = V2RecordingSnap.target(
            proposed: 4.84,
            lowerBound: 0,
            upperBound: 8,
            candidates: [5])

        XCTAssertEqual(target, 5)
    }

    func testSnapsWhenDraggingTowardBoundaryFromRightToLeft() {
        let target = V2RecordingSnap.target(
            proposed: 5.16,
            lowerBound: 5,
            upperBound: 10,
            candidates: [5])

        XCTAssertEqual(target, 5)
    }

    func testDoesNotSnapOutsideThreshold() {
        let target = V2RecordingSnap.target(
            proposed: 4.5,
            lowerBound: 0,
            upperBound: 8,
            candidates: [5])

        XCTAssertNil(target)
    }

    func testUsesNarrowSnapWindowToAvoidStickyDragging() {
        XCTAssertNil(V2RecordingSnap.target(
            proposed: 4.81,
            lowerBound: 0,
            upperBound: 8,
            candidates: [5]))

        XCTAssertEqual(V2RecordingSnap.target(
            proposed: 4.83,
            lowerBound: 0,
            upperBound: 8,
            candidates: [5]), 5)
    }

    func testIgnoresCandidatesOutsideLegalTrimRange() {
        let target = V2RecordingSnap.target(
            proposed: 5.1,
            lowerBound: 5,
            upperBound: 8,
            candidates: [2, 5])

        XCTAssertEqual(target, 5)
    }
}
