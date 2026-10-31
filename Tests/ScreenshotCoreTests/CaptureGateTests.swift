import XCTest

@testable import ScreenshotCore

final class CaptureGateTests: XCTestCase {
  func testBusySessionAndLateCaptureResults() {
    var gate = CaptureGate()
    let first = gate.begin()!
    XCTAssertNil(gate.begin(), "A repeated hotkey must not create another session")
    gate.cancel()
    let second = gate.begin()!
    XCTAssertFalse(gate.accepts(first), "Old callbacks must not reopen overlays")
    XCTAssertTrue(gate.accepts(second))
    gate.cancel()
    XCTAssertFalse(gate.accepts(second))
  }
}
