import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@MainActor // macOS 13
@main
struct AeroSpaceApp: App {
    @MainActor // macOS 13
    @StateObject var viewModel = TrayMenuModel.shared
    @StateObject var appearance = Appearance.shared

    init() {
        initAppBundle()
    }

    @MainActor // macOS 13
    var body: some Scene {
        MenuBar(viewModel: viewModel, appearance: appearance)
    }
}
