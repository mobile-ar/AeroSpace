/// Syntax:
/// layout (main|h_accordion|v_accordion|h_list|v_list|floating|tiling)...
struct LayoutCommand: Command {
    let toggleBetween: [Layout]
    enum Layout: String {
        //case main // todo drop?
        case h_accordion, v_accordion, h_list, v_list
        case floating, tiling
    }

    init?(toggleBetween: [Layout]) {
        if toggleBetween.isEmpty || toggleBetween.toSet().count != toggleBetween.count {
            return nil
        }
        self.toggleBetween = toggleBetween
    }

    func run() async {
        precondition(Thread.current.isMainThread)
        guard let window = focusedWindow ?? Workspace.focused.mruWindows.mostRecent else { return }
        let targetLayout = toggleBetween.firstIndex(of: window.verboseLayout)
            .flatMap { toggleBetween.getOrNil(atIndex: $0 + 1) } ?? toggleBetween.first
        if let parent = window.parent as? TilingContainer {
            parent.layout = targetLayout?.simpleLayout ?? errorT("TODO")
            parent.orientation = targetLayout?.orientation ?? errorT("TODO")
            refresh()
        } else {
            precondition(window.parent is Workspace)
            // todo
        }
    }
}

private extension LayoutCommand.Layout {
    var simpleLayout: Layout? {
        switch self {
        case .h_accordion, .v_accordion:
            return .Accordion
        case .h_list, .v_list:
            return .List
        case .floating, .tiling:
            return nil
        }
    }

    var orientation: Orientation? {
        switch self {
        case .h_accordion, .h_list:
            return .H
        case .v_accordion, .v_list:
            return .V
        case .floating, .tiling:
            return nil
        }
    }
}

private extension MacWindow {
    var verboseLayout: LayoutCommand.Layout {
        if let parent = parent as? TilingContainer {
            switch parent.layout {
            case .List:
                return parent.orientation == .H ? .h_list : .v_list
            case .Accordion:
                return parent.orientation == .H ? .h_accordion : .v_accordion
            }
        } else {
            return .floating
        }
    }
}