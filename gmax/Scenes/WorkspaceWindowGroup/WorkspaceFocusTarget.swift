import Foundation

enum WorkspaceFocusTarget: Hashable {
    case sidebar
    case emptyWorkspace(WorkspaceID)
    case pane(PaneID)
    case inspector
}
