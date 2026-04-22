import Foundation

enum WorkspaceFocusTarget: Hashable {
    case sidebar
    case pane(PaneID)
    case inspector
}
