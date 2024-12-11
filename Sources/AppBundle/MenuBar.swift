import Common
import Foundation
import SwiftUI

public func menuBar(viewModel: TrayMenuModel) -> some Scene {
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        Divider()
        if viewModel.isEnabled {
            Text("Workspaces:")
            ForEach(viewModel.workspaces, id: \.name) { workspace in
                Button {
                    refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
                } label: {
                    Toggle(isOn: .constant(workspace.isFocused)) {
                        Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
                    }
                }
            }
            Divider()
        }
        Button(viewModel.isEnabled ? "Disable" : "Enable") {
            refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) {
                _ = EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle)).run(.defaultEnv, .emptyStdin)
            }
        }.keyboardShortcut("E", modifiers: .command)
        let editor = getTextEditorToOpenConfig()
        Button("Open config in '\(editor.lastPathComponent)'") {
            let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
            switch findCustomConfigUrl() {
                case .file(let url):
                    url.open(with: editor)
                case .noCustomConfigExists:
                    _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                    fallbackConfig.open(with: editor)
                case .ambiguousConfigError:
                    fallbackConfig.open(with: editor)
            }
        }.keyboardShortcut("O", modifiers: .command)
        if viewModel.isEnabled {
            Button("Reload config") {
                refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) { _ = reloadConfig() }
            }.keyboardShortcut("R", modifiers: .command)
        }
        Button("Quit \(aeroSpaceAppName)") {
            terminationHandler.beforeTermination()
            terminateApp()
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        if viewModel.isEnabled {
            menuLabel(viewModel: viewModel)
                .id("\(viewModel.workspaces.hashValue)\(viewModel.trayItems.hashValue)")
        } else {
            Text("⏸️")
        }
    }
}

struct menuLabel: View {
    var viewModel: TrayMenuModel
    
    var body: some View {
        let renderer = ImageRenderer(content: imageContent)
        if let cgImage = renderer.cgImage {
            Image(cgImage, scale: 2, label: Text(""))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // In case image can't be rendered fallback to default text
            Text(viewModel.trayText)
        }
    }
    
    // I used a height that's twice as large as what I want and then use a scale of 2 to make the images look smoother
    private var imageContent: some View {
        HStack(spacing: 4) {
            switch config.menuBarStyle {
            case .text:
                Text(viewModel.trayText)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundStyle(Color.white)
            case .image, .full:
                ForEach(viewModel.trayItems, id:\.name) { item in
                    Image(systemName: item.systemImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color.white)
                        .id(item.name)
                }
                
                if config.menuBarStyle == .full {
                    let otherWorkspaces = Workspace.all.filter { workspace in
                        !workspace.isEffectivelyEmpty && !viewModel.trayItems.contains(where: { item in item.name == workspace.name })
                    }
                    if !otherWorkspaces.isEmpty {
                        Text("|")
                            .foregroundStyle(Color.gray)
                            .font(.system(.largeTitle, design: .monospaced))
                            .padding(.bottom, 2)
                        
                        ForEach(otherWorkspaces, id:\.name) { item in
                            Text(item.name)
                                .foregroundStyle(Color.gray)
                                .font(.system(.largeTitle, design: .monospaced))
                                .id(item.name)
                                .padding(.trailing, 2)
                        }
                    }
                }
            }
        }
        .frame(height: 40)
    }
}

enum MenuBarStyle: String {
    case text = "text"
    case image = "image"
    case full = "image-with-background-workspaces"
}

extension String {
    func parseMenuBarStyle() -> MenuBarStyle? {
        if let parsed = MenuBarStyle(rawValue: self) {
            return parsed
        } else {
            return nil
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
