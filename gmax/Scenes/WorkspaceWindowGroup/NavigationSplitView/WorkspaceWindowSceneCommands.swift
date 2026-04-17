import OSLog
import SwiftUI

extension FocusedValues {
	@Entry var activeWorkspaceFocusTarget: WorkspaceFocusTarget?
	@Entry var selectedWorkspaceSelection: Binding<WorkspaceID?>?
	@Entry var dismissPresentedWorkspaceModal: (() -> Void)?
	@Entry var openSavedWorkspaceLibrary: (() -> Void)?
	@Entry var presentWorkspaceRename: ((WorkspaceID) -> Void)?
	@Entry var presentWorkspaceDeletion: ((WorkspaceID) -> Void)?
	@Entry var moveFocusedPaneFocus: ((PaneFocusDirection) -> Void)?
	@Entry var splitFocusedPane: ((SplitDirection) -> Void)?
	@Entry var closeFocusedPane: (() -> Void)?
}

struct WorkspaceWindowSceneCommands: Commands {
	@Environment(\.dismiss) private var dismiss
	@FocusedObject private var workspaceStore: WorkspaceStore?
	@FocusedValue(\.activeWorkspaceFocusTarget) private var activeWorkspaceFocusTarget
	@FocusedValue(\.selectedWorkspaceSelection) private var selectedWorkspaceSelection
	@FocusedValue(\.dismissPresentedWorkspaceModal) private var dismissPresentedWorkspaceModal
	@FocusedValue(\.openSavedWorkspaceLibrary) private var openSavedWorkspaceLibrary
	@FocusedValue(\.presentWorkspaceRename) private var presentWorkspaceRename
	@FocusedValue(\.presentWorkspaceDeletion) private var presentWorkspaceDeletion
	@FocusedValue(\.moveFocusedPaneFocus) private var moveFocusedPaneFocus
	@FocusedValue(\.splitFocusedPane) private var splitFocusedPane
	@FocusedValue(\.closeFocusedPane) private var closeFocusedPane

	var body: some Commands {
		let workspaces = workspaceStore?.workspaces ?? []
		let selectedWorkspaceID = selectedWorkspaceSelection?.wrappedValue
		let selectedWorkspace = selectedWorkspaceID.flatMap { selectedWorkspaceID in workspaces.first { $0.id == selectedWorkspaceID } }
		let isOnlyWorkspaceInWindow = workspaces.count == 1
		let isSelectedWorkspaceEmpty = selectedWorkspace?.root == nil
		let canSplitFocusedPane = splitFocusedPane != nil
		let canDeleteSelectedWorkspace = selectedWorkspace != nil && workspaces.count > 1
		let canCycleWorkspaces = workspaces.count > 1
		let closeWorkspaceAction: (() -> Void)? = {
			guard let workspaceStore, let selectedWorkspaceID else {
				return nil
			}

			return {
				selectedWorkspaceSelection?.wrappedValue = workspaceStore.closeWorkspace(selectedWorkspaceID)
			}
		}()
		let resolvedCloseCommand: (title: String, action: (() -> Void)?) = if let dismissPresentedWorkspaceModal {
			("Close", dismissPresentedWorkspaceModal)
		} else {
			switch activeWorkspaceFocusTarget {
				case .pane:
					("Close Pane", closeFocusedPane)

				case .sidebar:
					if isOnlyWorkspaceInWindow {
						if isSelectedWorkspaceEmpty {
							("Close Window", dismiss.callAsFunction)
						} else {
							("Close Workspace", closeWorkspaceAction)
						}
					} else {
						("Close Workspace", closeWorkspaceAction)
					}
				
				case .inspector:
					("Close Window", nil)

				case nil:
					if isSelectedWorkspaceEmpty {
						if isOnlyWorkspaceInWindow {
							("Close Window", dismiss.callAsFunction)
						} else {
							("Close Workspace", closeWorkspaceAction)
						}
					} else {
						("Close Window", dismiss.callAsFunction)
					}
			}
		}

		SidebarCommands()
		InspectorCommands()
		TextEditingCommands()
		TextFormattingCommands()
		ToolbarCommands()

		CommandGroup(after: .newItem) {
			Button("New Workspace") {
				if let workspaceStore {
					selectedWorkspaceSelection?.wrappedValue = workspaceStore.createWorkspace()
				}
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])
			.disabled(workspaceStore == nil)
		}

		CommandGroup(after: .newItem) {
			Button("Open Workspace…") {
				openSavedWorkspaceLibrary?()
			}
			.keyboardShortcut("o", modifiers: [.command])
			.disabled(openSavedWorkspaceLibrary == nil)
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save Workspace") {
				guard let workspaceStore else {
					return
				}
				guard let selectedWorkspaceID else {
					Logger.diagnostics.error(
						"The app received a save-workspace command for the active shell window, but that window has no selected workspace to save."
					)
					return
				}
				Logger.diagnostics.notice(
					"Requested that the selected workspace be saved to the workspace library from the active shell window. Workspace ID: \(selectedWorkspaceID.rawValue.uuidString, privacy: .public)"
				)
				_ = workspaceStore.saveWorkspaceToLibrary(selectedWorkspaceID)
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceSelection?.wrappedValue == nil || workspaceStore == nil)

			Divider()

			Button(resolvedCloseCommand.title) {
				resolvedCloseCommand.action?()
			}
			.keyboardShortcut("w", modifiers: [.command])
			.disabled(resolvedCloseCommand.action == nil)
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				if let workspaceStore {
					selectedWorkspaceSelection?.wrappedValue = workspaceStore.undoCloseWorkspace()
				}
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled((workspaceStore?.recentlyClosedWorkspaceCount ?? 0) == 0)

			Divider()

			Button("Rename Workspace") {
				if let selectedWorkspaceID {
					presentWorkspaceRename?(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || presentWorkspaceRename == nil)

			Button("Duplicate Workspace Layout") {
				if let workspaceStore, let selectedWorkspaceID {
					selectedWorkspaceSelection?.wrappedValue = workspaceStore.duplicateWorkspace(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || workspaceStore == nil)

			Button("Close Workspace to Library") {
				if let workspaceStore, let selectedWorkspaceID {
					selectedWorkspaceSelection?.wrappedValue = workspaceStore.closeWorkspaceToLibrary(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || workspaceStore == nil)

			Button("Close Workspace") {
				guard let workspaceStore else {
					return
				}
				guard let selectedWorkspaceID else {
					Logger.diagnostics.notice(
						"Skipped the close-workspace command because the active shell scene has no selected workspace."
					)
					return
				}
				selectedWorkspaceSelection?.wrappedValue = workspaceStore.closeWorkspace(selectedWorkspaceID)
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(selectedWorkspaceID == nil || workspaceStore == nil)

			Button("Delete Workspace", role: .destructive) {
				if let selectedWorkspaceID {
					presentWorkspaceDeletion?(selectedWorkspaceID)
				}
			}
			.disabled(!canDeleteSelectedWorkspace)

			Divider()

			Button("Previous Workspace") {
				guard !workspaces.isEmpty else {
					selectedWorkspaceSelection?.wrappedValue = nil
					return
				}
				guard
					let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID })
				else {
					selectedWorkspaceSelection?.wrappedValue = workspaces.last?.id
					return
				}
				selectedWorkspaceSelection?.wrappedValue = workspaces[(currentIndex - 1 + workspaces.count) % workspaces.count].id
			}
			.keyboardShortcut("[", modifiers: [.command, .shift])
			.disabled(!canCycleWorkspaces)

			Button("Next Workspace") {
				guard !workspaces.isEmpty else {
					selectedWorkspaceSelection?.wrappedValue = nil
					return
				}
				guard
					let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID })
				else {
					selectedWorkspaceSelection?.wrappedValue = workspaces.first?.id
					return
				}
				selectedWorkspaceSelection?.wrappedValue = workspaces[(currentIndex + 1) % workspaces.count].id
			}
			.keyboardShortcut("]", modifiers: [.command, .shift])
			.disabled(!canCycleWorkspaces)
		}

		CommandMenu("Pane") {
			Button("Move Focus Left") {
				moveFocusedPaneFocus?(.left)
			}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Button("Move Focus Right") {
				moveFocusedPaneFocus?(.right)
			}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Button("Move Focus Up") {
				moveFocusedPaneFocus?(.up)
			}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Button("Move Focus Down") {
				moveFocusedPaneFocus?(.down)
			}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Divider()

			Button("Focus Next Pane") {
				moveFocusedPaneFocus?(.next)
			}
			.keyboardShortcut("]", modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Button("Focus Previous Pane") {
				moveFocusedPaneFocus?(.previous)
			}
			.keyboardShortcut("[", modifiers: [.command, .option])
			.disabled(moveFocusedPaneFocus == nil)

			Section("New Pane") {
				Button("Split Right") {
					splitFocusedPane?(.right)
				}
				.keyboardShortcut("d", modifiers: [.command])
				.disabled(!canSplitFocusedPane)

				Button("Split Down") {
					splitFocusedPane?(.down)
				}
				.keyboardShortcut("d", modifiers: [.command, .shift])
				.disabled(!canSplitFocusedPane)
			}
		}
	}
}
