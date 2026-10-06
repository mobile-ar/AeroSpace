import Darwin
import Foundation

struct AppProcess: Equatable, Sendable {
    let pid: pid_t
    var executableURL: URL? = nil
    var startTime: UInt64 = 0

    var isTerminated: Bool {
        // Only fallback-resolved processes need checks beyond NSRunningApplication.isTerminated.
        guard executableURL != nil else { return false }
        if let current = getAppProcess(pid) { return current != self }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}

func resolveAppProcess(
    pid: pid_t,
    executableURL: URL?,
    processes: () -> [AppProcess] = getAppProcesses,
) -> AppProcess? {
    if pid > 0 { return AppProcess(pid: pid) }
    guard let executableURL, executableURL.isFileURL else { return nil }
    let executable = executableURL.resolvingSymlinksInPath().standardizedFileURL
    // AppKit can report -1 for trampoline apps. Match the running executable, not CFBundleExecutable.
    let matches = processes().filter {
        $0.pid > 0 && $0.executableURL?.resolvingSymlinksInPath().standardizedFileURL == executable
    }
    return matches.count == 1 ? matches[0] : nil
}

private func getAppProcesses() -> [AppProcess] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    let actualCount = pids.withUnsafeMutableBytes { buffer in
        unsafe proc_listallpids(buffer.baseAddress, Int32(buffer.count))
    }
    // A full buffer may omit another matching process, so don't resolve an ambiguous snapshot.
    guard actualCount > 0 && actualCount < pids.count else { return [] }
    return pids.prefix(Int(actualCount)).compactMap(getAppProcess)
}

func getAppProcess(_ pid: pid_t) -> AppProcess? {
    guard pid > 0 else { return nil }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = path.withUnsafeMutableBytes { buffer in
        unsafe proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
    }
    guard length > 0 else { return nil }
    let executable = path.withUnsafeBufferPointer { buffer in
        unsafe String(cString: buffer.baseAddress!)
    }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard unsafe proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return AppProcess(
        pid: pid,
        executableURL: URL(fileURLWithPath: executable).resolvingSymlinksInPath().standardizedFileURL,
        startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
    )
}
