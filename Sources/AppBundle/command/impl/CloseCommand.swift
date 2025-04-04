import AppKit
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        try await allowOnlyCancellationError {
            guard let target = args.resolveTargetOrReportError(env, io) else { return false }
            guard let window = target.windowOrNil else {
                return io.err("Empty workspace")
            }
            // Access ax directly. Not cool :(
            if try await args.quitIfLastWindow.andAsyncMainActor(try await window.macAppUnsafe.getAxWindowsCount() == 1) {
                if window.macAppUnsafe.nsApp.terminate() {
                    window.asMacWindow().garbageCollect(skipClosedWindowsCache: true)
                    return true
                } else {
                    return io.err("Failed to quit '\(window.app.name ?? "Unknown app")'")
                }
            } else {
                window.closeAxWindow()
                return true
            }
        }
    }
}
