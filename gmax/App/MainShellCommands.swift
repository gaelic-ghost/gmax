//
//  MainShellCommands.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import SwiftUI

struct MainShellCommands: Commands {
	let shellModel: ShellModel
	let selectedWorkspaceID: Binding<WorkspaceID?>
	let isSavedWorkspaceLibraryPresented: Binding<Bool>
	let selectedWorkspace: Workspace?
	let canDeleteSelectedWorkspace: Bool
	let canCloseWorkspace: Bool
	let canCloseWorkspaceToLibrary: Bool
	let saveSelectedWorkspace: () -> Void
	let performContextualClose: () -> Void
	let performWorkspaceClose: () -> Void
	let performWindowClose: () -> Void
	let presentWorkspaceRename: (Workspace) -> Void

	var body: some Commands {
		CommandGroup(replacing: .newItem) {
			Button("New Workspace") {
				selectedWorkspaceID.wrappedValue = shellModel.createWorkspace()
			}
			.keyboardShortcut("n", modifiers: [.command])
		}

		CommandGroup(after: .newItem) {
			Button("Open Workspace…") {
				isSavedWorkspaceLibraryPresented.wrappedValue = true
			}
			.keyboardShortcut("o", modifiers: [.command])
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save Workspace") {
				saveSelectedWorkspace()
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceID.wrappedValue == nil)

			Button("Close") {
				performContextualClose()
			}
			.keyboardShortcut("w", modifiers: [.command])
		}

		SidebarCommands()

		CommandGroup(after: .sidebar) {
			Button(shellModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
				shellModel.toggleInspector()
			}
			.keyboardShortcut("b", modifiers: [.command, .shift])
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				selectedWorkspaceID.wrappedValue = shellModel.undoCloseWorkspace()
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(!shellModel.canUndoCloseWorkspace())

			Divider()

			Button("Rename Workspace") {
				guard let selectedWorkspace else {
					return
				}
				presentWorkspaceRename(selectedWorkspace)
			}
			.disabled(selectedWorkspace == nil)

			Button("Duplicate Workspace Layout") {
				guard let workspaceID = selectedWorkspaceID.wrappedValue else {
					return
				}
				selectedWorkspaceID.wrappedValue = shellModel.duplicateWorkspace(workspaceID)
			}
			.disabled(selectedWorkspaceID.wrappedValue == nil)

			Button("Close Workspace to Library") {
				guard let workspaceID = selectedWorkspaceID.wrappedValue else {
					return
				}
				selectedWorkspaceID.wrappedValue = shellModel.closeWorkspaceToLibrary(workspaceID).nextSelectedWorkspaceID
			}
			.disabled(!canCloseWorkspaceToLibrary)

			Button("Close Workspace") {
				performWorkspaceClose()
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(!canCloseWorkspace)

			Button("Delete Workspace", role: .destructive) {
				guard let workspaceID = selectedWorkspaceID.wrappedValue else {
					return
				}
				shellModel.deleteWorkspace(workspaceID)
				selectedWorkspaceID.wrappedValue = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID.wrappedValue)
			}
			.disabled(!canDeleteSelectedWorkspace)

			Divider()

			Button("Previous Workspace") {
				selectedWorkspaceID.wrappedValue = shellModel.selectPreviousWorkspace()
			}
			.keyboardShortcut("[", modifiers: [.command, .shift])
			.disabled(shellModel.workspaces.count < 2)

			Button("Next Workspace") {
				selectedWorkspaceID.wrappedValue = shellModel.selectNextWorkspace()
			}
			.keyboardShortcut("]", modifiers: [.command, .shift])
			.disabled(shellModel.workspaces.count < 2)
		}

		CommandGroup(after: .windowSize) {
			Button("Close Window") {
				performWindowClose()
			}
			.keyboardShortcut("w", modifiers: [.command, .shift])
		}

		CommandMenu("Pane") {
			Button("New Pane") {
				if let workspaceID = selectedWorkspaceID.wrappedValue {
					selectedWorkspaceID.wrappedValue = shellModel.createPane(in: workspaceID)
				} else {
					selectedWorkspaceID.wrappedValue = shellModel.createWorkspace()
				}
			}
			.keyboardShortcut("t", modifiers: [.command])

			Divider()

			Button("Move Focus Left") {
				shellModel.movePaneFocus(.left)
			}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

			Button("Move Focus Right") {
				shellModel.movePaneFocus(.right)
			}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

			Button("Move Focus Up") {
				shellModel.movePaneFocus(.up)
			}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])

			Button("Move Focus Down") {
				shellModel.movePaneFocus(.down)
			}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])

			Divider()

			Button("Focus Next Pane") {
				shellModel.movePaneFocus(.next)
			}
			.keyboardShortcut("]", modifiers: [.command, .option])

			Button("Focus Previous Pane") {
				shellModel.movePaneFocus(.previous)
			}
			.keyboardShortcut("[", modifiers: [.command, .option])

			Divider()

			Button("Split Right") {
				if let workspaceID = selectedWorkspaceID.wrappedValue {
					shellModel.splitFocusedPane(in: workspaceID, .right)
				}
			}
			.keyboardShortcut("d", modifiers: [.command])

			Button("Split Down") {
				if let workspaceID = selectedWorkspaceID.wrappedValue {
					shellModel.splitFocusedPane(in: workspaceID, .down)
				}
			}
			.keyboardShortcut("d", modifiers: [.command, .shift])
		}
	}
}
