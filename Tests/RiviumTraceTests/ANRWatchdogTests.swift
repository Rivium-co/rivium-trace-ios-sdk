import XCTest
@testable import RiviumTrace

/// The ANR watchdog: one report per hang, however long the hang lasts.
final class ANRWatchdogTests: XCTestCase {

    private let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstCheckOfAHangReports() {
        XCTAssertTrue(ANRWatchdogService.isNewHang(lastAnswer: answeredAt, reportedHang: nil))
    }

    func testLaterChecksOfTheSameHangDoNotReport() {
        // A 25 s hang is checked every 2.5 s: only the first check that crosses the timeout reports.
        XCTAssertFalse(ANRWatchdogService.isNewHang(lastAnswer: answeredAt, reportedHang: answeredAt))
    }

    func testAHangAfterTheMainThreadAnsweredReportsAgain() {
        let answeredAgain = answeredAt.addingTimeInterval(30)
        XCTAssertTrue(ANRWatchdogService.isNewHang(lastAnswer: answeredAgain, reportedHang: answeredAt))
    }

    func testALongHangIsReportedOnce() {
        let watchdog = ANRWatchdogService.makeForTesting()
        var reports = 0
        let blocked = expectation(description: "hang reported")
        blocked.assertForOverFulfill = false
        watchdog.start(timeoutMs: 200) { _ in
            reports += 1
            blocked.fulfill()
        }
        // Block the main thread for five timeouts.
        Thread.sleep(forTimeInterval: 1.0)
        wait(for: [blocked], timeout: 2)
        // Let the queued checks run out, then make sure nothing else arrived.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        watchdog.stop()
        XCTAssertEqual(reports, 1)
    }
}
