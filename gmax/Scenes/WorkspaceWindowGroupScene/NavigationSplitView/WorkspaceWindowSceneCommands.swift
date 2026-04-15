import OSLog
import SwiftUI

extension FocusedValues {
	@Entry var selectedWorkspaceSelection: Binding<WorkspaceID?>?
	@Entry var openSavedWorkspaceLibrary: (() -> Void)?
	@Entry var presentWorkspaceRename: ((WorkspaceID) -> Void)?
	@Entry var presentWorkspaceDeletion: ((WorkspaceID) -> Void)?
	@Entry var closeFocusedPane: (() -> Void)?
	@Entry var closeEmptyWorkspace: (() -> Void)?
}

struct WorkspaceWindowSceneCommands: Commands {
	@Environment(\.dismiss) private var dismiss
	@FocusedObject private var shellModel: ShellModel?
	@FocusedValue(\.selectedWorkspaceSelection) private var selectedWorkspaceSelection
	@FocusedValue(\.openSavedWorkspaceLibrary) private var openSavedWorkspaceLibrary
	@FocusedValue(\.presentWorkspaceRename) private var presentWorkspaceRename
	@FocusedValue(\.presentWorkspaceDeletion) private var presentWorkspaceDeletion
	@FocusedValue(\.closeFocusedPane) private var closeFocusedPane
	@FocusedValue(\.closeEmptyWorkspace) private var closeEmptyWorkspace

	var body: some Commands {
		let workspaces = shellModel?.workspaces ?? []
		let selectedWorkspaceID = selectedWorkspaceSelection?.wrappedValue
		let selectedWorkspace = selectedWorkspaceID.flatMap { selectedWorkspaceID in workspaces.first { $0.id == selectedWorkspaceID } }
		let canSplitFocusedPane = selectedWorkspace?.focusedPaneID.flatMap {
			selectedWorkspace?.root?.findPane(id: $0)
		} != nil
		let canDeleteSelectedWorkspace = selectedWorkspace != nil && workspaces.count > 1
		let canCycleWorkspaces = workspaces.count > 1

		SidebarCommands()
		InspectorCommands()
		TextEditingCommands()
		TextFormattingCommands()
		ToolbarCommands()

		CommandGroup(after: .newItem) {
			Button("New Workspace") {
				if let shellModel {
					selectedWorkspaceSelection?.wrappedValue = shellModel.createWorkspace()
				}
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])
			.disabled(shellModel == nil)
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
				guard let shellModel else {
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
				_ = shellModel.saveWorkspaceToLibrary(selectedWorkspaceID)
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceSelection?.wrappedValue == nil || shellModel == nil)

			Divider()

			Button(closeFocusedPane != nil ? "Close Pane" : closeEmptyWorkspace != nil ? "Close Workspace" : "Close Window") {
				if let closeFocusedPane {
					closeFocusedPane()
				} else if let closeEmptyWorkspace {
					closeEmptyWorkspace()
				} else {
					dismiss()
				}
			}
			.keyboardShortcut("w", modifiers: [.command])
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				if let shellModel {
					selectedWorkspaceSelection?.wrappedValue = shellModel.undoCloseWorkspace()
				}
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled((shellModel?.recentlyClosedWorkspaceCount ?? 0) == 0)

			Divider()

			Button("Rename Workspace") {
				if let selectedWorkspaceID {
					presentWorkspaceRename?(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || presentWorkspaceRename == nil)

			Button("Duplicate Workspace Layout") {
				if let shellModel, let selectedWorkspaceID {
					selectedWorkspaceSelection?.wrappedValue = shellModel.duplicateWorkspace(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Button("Close Workspace to Library") {
				if let shellModel, let selectedWorkspaceID {
					selectedWorkspaceSelection?.wrappedValue = shellModel.closeWorkspaceToLibrary(selectedWorkspaceID)
				}
			}
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Button("Close Workspace") {
				guard let shellModel else {
					return
				}
				guard let selectedWorkspaceID else {
					Logger.diagnostics.notice(
						"Skipped the close-workspace command because the active shell scene has no selected workspace."
					)
					return
				}
				selectedWorkspaceSelection?.wrappedValue = shellModel.closeWorkspace(selectedWorkspaceID)
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

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
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.left, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

			Button("Move Focus Right") {
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.right, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

			Button("Move Focus Up") {
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.up, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])

			Button("Move Focus Down") {
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.down, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])

			Divider()

			Button("Focus Next Pane") {
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.next, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut("]", modifiers: [.command, .option])

			Button("Focus Previous Pane") {
				if let shellModel, let selectedWorkspaceID {
					shellModel.movePaneFocus(.previous, in: selectedWorkspaceID)
				}
			}
			.keyboardShortcut("[", modifiers: [.command, .option])

			Section("New Pane") {
				Button("Split Right") {
					if let shellModel, let selectedWorkspaceID {
						shellModel.splitFocusedPane(in: selectedWorkspaceID, .right)
					}
				}
				.keyboardShortcut("d", modifiers: [.command])
				.disabled(!canSplitFocusedPane)

				Button("Split Down") {
					if let shellModel, let selectedWorkspaceID {
						shellModel.splitFocusedPane(in: selectedWorkspaceID, .down)
					}
				}
				.keyboardShortcut("d", modifiers: [.command, .shift])
				.disabled(!canSplitFocusedPane)
			}
		}
	}
}
