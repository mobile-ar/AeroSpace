@testable import AppBundle
import Darwin
import Foundation
import XCTest

final class AppProcessTest: XCTestCase {
    private let executableURL = URL(fileURLWithPath: "/Applications/AppProcessTest.app/Contents/MacOS/real-executable")

    func testPositivePIDSkipsEnumeration() {
        var enumerationCount = 0
        let urls: [URL?] = [nil, executableURL, URL(string: "https://example.com/real-executable")!]
        for url in urls {
            let actual = resolveAppProcess(pid: 42, executableURL: url, processes: {
                enumerationCount += 1
                return [AppProcess(pid: 99, executableURL: self.executableURL, startTime: 123)]
            })
            assertEquals(actual, AppProcess(pid: 42))
        }
        assertEquals(enumerationCount, 0)
    }

    func testNonpositivePIDRequiresFileURLWithoutEnumeration() {
        var enumerationCount = 0
        let urls: [URL?] = [nil, URL(string: "https://example.com/real-executable")!]
        for pid in [pid_t(-1), 0] {
            for url in urls {
                assertNil(resolveAppProcess(pid: pid, executableURL: url, processes: {
                    enumerationCount += 1
                    return [AppProcess(pid: 42, executableURL: self.executableURL)]
                }))
            }
        }
        assertEquals(enumerationCount, 0)
    }

    func testTrampolinePIDResolvesUniqueExecutableRecord() {
        let expected = AppProcess(pid: 42, executableURL: executableURL, startTime: 123)
        let trampoline = AppProcess(
            pid: 99,
            executableURL: URL(fileURLWithPath: "/Applications/AppProcessTest.app/Contents/MacOS/trampoline"),
            startTime: 456,
        )
        assertEquals(
            resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [trampoline, expected] }),
            expected,
        )
    }

    func testNoMatchingExecutable() {
        assertNil(resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [] }))
        assertNil(resolveAppProcess(pid: 0, executableURL: executableURL, processes: {
            [AppProcess(pid: 42)]
        }))
    }

    func testMultipleMatchingExecutablesAreAmbiguous() {
        let first = AppProcess(pid: 42, executableURL: executableURL, startTime: 123)
        let second = AppProcess(pid: 99, executableURL: executableURL, startTime: 456)
        assertNil(resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [first, second] }))
    }

    func testInvalidCandidatePIDsAreExcluded() {
        let invalid = [
            AppProcess(pid: -1, executableURL: executableURL, startTime: 123),
            AppProcess(pid: 0, executableURL: executableURL, startTime: 456),
        ]
        assertNil(resolveAppProcess(pid: -1, executableURL: executableURL, processes: { invalid }))
        let expected = AppProcess(pid: 42, executableURL: executableURL, startTime: 789)
        assertEquals(
            resolveAppProcess(pid: 0, executableURL: executableURL, processes: { invalid + [expected] }),
            expected,
        )
    }

    func testSameBasenameAndNestedHelperPathsDoNotMatch() {
        let unrelatedURLs = [
            URL(fileURLWithPath: "/Applications/OtherApp.app/Contents/MacOS/real-executable"),
            URL(fileURLWithPath: "/Applications/AppProcessTest.app/Contents/Helpers/Helper.app/Contents/MacOS/real-executable"),
            executableURL.appendingPathComponent("helper"),
        ]
        let expected = AppProcess(pid: 42, executableURL: executableURL, startTime: 123)
        for url in unrelatedURLs {
            let unrelated = AppProcess(pid: 99, executableURL: url, startTime: 456)
            assertNil(resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [unrelated] }))
            assertEquals(
                resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [unrelated, expected] }),
                expected,
            )
        }
    }

    func testCanonicalPathNormalization() {
        let unnormalizedURL = URL(fileURLWithPath: "/Applications/AppProcessTest.app/Contents/MacOS/../MacOS/./real-executable")
        for (requestedURL, candidateURL) in [
            (unnormalizedURL, executableURL),
            (executableURL, unnormalizedURL),
            (unnormalizedURL, unnormalizedURL),
        ] {
            let expected = AppProcess(pid: 42, executableURL: candidateURL, startTime: 123)
            assertEquals(
                resolveAppProcess(pid: -1, executableURL: requestedURL, processes: { [expected] }),
                expected,
            )
        }
    }

    func testLiveProcessIdentity() throws {
        let process = try XCTUnwrap(getAppProcess(getpid()))
        assertEquals(process.pid, getpid())
        assertFalse(process.isTerminated)
        assertNil(getAppProcess(-1))
        assertNil(getAppProcess(0))
    }

    func testChangedProcessIdentityIsTerminated() throws {
        var process = try XCTUnwrap(getAppProcess(getpid()))
        process.startTime += 1
        assertTrue(process.isTerminated)
    }

    func testExitedProcessIsTerminated() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["1"]
        try child.run()
        let process = try XCTUnwrap(getAppProcess(child.processIdentifier))
        child.waitUntilExit()
        assertTrue(process.isTerminated)
    }

    func testStartTimeDistinguishesReusedPID() {
        let original = AppProcess(pid: 42, executableURL: executableURL, startTime: 123)
        let reused = AppProcess(pid: 42, executableURL: executableURL, startTime: 456)
        assertEquals(original, AppProcess(pid: 42, executableURL: executableURL, startTime: 123))
        assertEquals(original == reused, false)
        assertEquals(
            resolveAppProcess(pid: -1, executableURL: executableURL, processes: { [reused] }),
            reused,
        )
    }
}
