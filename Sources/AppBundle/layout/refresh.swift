import AppKit
import Common

@MainActor
private var activeRefreshTask: Task<(), any Error>? = nil

@MainActor
func runRefreshSession(
    _ event: RefreshSessionEvent,
    screenIsDefinitelyUnlocked: Bool // todo rename
) {
    if screenIsDefinitelyUnlocked { resetClosedWindowsCache() }
    activeRefreshTask?.cancel()
    activeRefreshTask = Task { try await runRefreshSessionBlocking(event) }
}

@MainActor
func runRefreshSessionBlocking(_ event: RefreshSessionEvent) async throws {
    try await $refreshSessionEventForDebug.withValue(event) {
        try await gc()
        gcMonitors()
        try await detectNewAppsAndWindows()

        let nativeFocused = try await getNativeFocusedWindow()
        if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
        updateFocusCache(nativeFocused)

        updateTrayText()
        try await normalizeLayoutReason()
        try await layoutWorkspaces()
    }
}

@MainActor
func runSession<T>(
    _ event: RefreshSessionEvent,
    body: @MainActor () async throws -> T
) async throws -> T {
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    return try await $refreshSessionEventForDebug.withValue(event) {
        resetClosedWindowsCache()

        let nativeFocused = try await getNativeFocusedWindow()
        if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
        updateFocusCache(nativeFocused)
        let focusBefore = focus.windowOrNil

        try await refreshModel()
        let result = try await body()
        try await refreshModel()

        let focusAfter = focus.windowOrNil

        if focusBefore != focusAfter {
            focusAfter?.nativeFocus() // syncFocusToMacOs
        }

        updateTrayText()
        try await normalizeLayoutReason()
        try await layoutWorkspaces()
        runRefreshSession(event, screenIsDefinitelyUnlocked: false)
        return result
    }
}

@MainActor
func refreshModel() async throws {
    Workspace.garbageCollectUnusedWorkspaces()
    try await checkOnFocusChangedCallbacks()
    normalizeContainers()
}

@MainActor
private func gc() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    MacApp.gcTerminatedApps()

    let frontmostAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    var aliveIds: Set<UInt32> = []
    for (_, app) in MacApp.allAppsMap {
        aliveIds.formUnion(try await app.gcDeadWindowsAndGetAliveIds(frontmostAppBundleId: frontmostAppBundleId))
    }
    for window in MacWindow.allWindows {
        if !aliveIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false, unregisterAxWindow: false)
        }
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

func refreshObs(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    let notif = notif as String
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        runRefreshSession(.ax(notif), screenIsDefinitelyUnlocked: false)
    }
}

enum OptimalHideCorner {
    case bottomLeftCorner, bottomRightCorner
}

@MainActor
private func layoutWorkspaces() async throws {
    let monitors = monitors
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        let xOff = monitor.width * 0.1
        let yOff = monitor.height * 0.1
        // brc = bottomRightCorner
        let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

        // blc = bottomLeftCorner
        let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

        let corner: OptimalHideCorner =
            monitors.contains(where: { m in m.rect.contains(brc1) || m.rect.contains(brc2) || m.rect.contains(brc3) }) &&
            monitors.allSatisfy { m in !m.rect.contains(blc1) && !m.rect.contains(blc2) && !m.rect.contains(blc3) }
            ? .bottomLeftCorner
            : .bottomRightCorner
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = corner
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        for window in workspace.allLeafWindowsRecursive {
            try await (window as! MacWindow).hideInCorner(corner) // todo as!
        }
    }
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}

@MainActor
private func detectNewAppsAndWindows() async throws {
    for app in try await detectNewApps() { // todo parallelize
        for id in try await app.detectNewWindowsAndGetIds() {
            _ = try await MacWindow.getOrRegister(windowId: id, macApp: app as! MacApp)
        }
    }
}
