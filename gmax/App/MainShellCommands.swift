//
//  MainShellCommands.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import SwiftUI

struct MainShellCommands: Commands {
	@FocusedValue(\.mainShellSceneContext) private var sceneContext
	@FocusedValue(\.mainShellSceneCommandState) private var commandState

	var body: some Commands {
		CommandGroup(after: .newItem) {
			Button("New Workspace") {
				sceneContext?.createWorkspace()
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])
			.disabled(sceneContext == nil)
		}

		CommandGroup(after: .newItem) {
			Button("Open Workspace…") {
				sceneContext?.openSavedWorkspaceLibrary()
			}
			.keyboardShortcut("o", modifiers: [.command])
			.disabled(sceneContext == nil)
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save Workspace") {
				sceneContext?.saveSelectedWorkspace()
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(!(commandState?.hasSelectedWorkspace ?? false))

			Button("Close") {
				sceneContext?.performContextualClose()
			}
			.keyboardShortcut("w", modifiers: [.command])
		}

		SidebarCommands()

		CommandGroup(after: .sidebar) {
			Button(commandState?.isInspectorVisible == false ? "Show Inspector" : "Hide Inspector") {
				sceneContext?.toggleInspector()
			}
			.keyboardShortcut("b", modifiers: [.command, .shift])
			.disabled(sceneContext == nil)
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				sceneContext?.undoCloseWorkspace()
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(!(commandState?.canUndoCloseWorkspace ?? false))

			Divider()

			Button("Rename Workspace") {
				sceneContext?.presentWorkspaceRename()
			}
			.disabled(!(commandState?.hasSelectedWorkspace ?? false))

			Button("Duplicate Workspace Layout") {
				sceneContext?.duplicateSelectedWorkspaceLayout()
			}
			.disabled(!(commandState?.hasSelectedWorkspace ?? false))

			Button("Close Workspace to Library") {
				sceneContext?.closeSelectedWorkspaceToLibrary()
			}
			.disabled(!(commandState?.canCloseWorkspaceToLibrary ?? false))

			Button("Close Workspace") {
				sceneContext?.performWorkspaceClose()
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(!(commandState?.canCloseWorkspace ?? false))

			Button("Delete Workspace", role: .destructive) {
				sceneContext?.deleteSelectedWorkspace()
			}
			.disabled(!(commandState?.canDeleteSelectedWorkspace ?? false))

			Divider()

			Button("Previous Workspace") {
				sceneContext?.selectPreviousWorkspace()
			}
			.keyboardShortcut("[", modifiers: [.command, .shift])
			.disabled((commandState?.workspaceCount ?? 0) < 2)

			Button("Next Workspace") {
				sceneContext?.selectNextWorkspace()
			}
			.keyboardShortcut("]", modifiers: [.command, .shift])
			.disabled((commandState?.workspaceCount ?? 0) < 2)
		}

		CommandGroup(after: .windowSize) {
			Button("Close Window") {
				sceneContext?.performWindowClose()
			}
			.keyboardShortcut("w", modifiers: [.command, .shift])
		}

		CommandMenu("Pane") {
			Button("New Pane") {
				sceneContext?.createPane()
			}
			.keyboardShortcut("t", modifiers: [.command])

			Divider()

			Button("Move Focus Left") {
				sceneContext?.movePaneFocus(.left)
			}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

			Button("Move Focus Right") {
				sceneContext?.movePaneFocus(.right)
			}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

			Button("Move Focus Up") {
				sceneContext?.movePaneFocus(.up)
			}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])

			Button("Move Focus Down") {
				sceneContext?.movePaneFocus(.down)
			}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])

			Divider()

			Button("Focus Next Pane") {
				sceneContext?.movePaneFocus(.next)
			}
			.keyboardShortcut("]", modifiers: [.command, .option])

			Button("Focus Previous Pane") {
				sceneContext?.movePaneFocus(.previous)
			}
			.keyboardShortcut("[", modifiers: [.command, .option])

			Divider()

			Button("Split Right") {
				sceneContext?.splitFocusedPane(.right)
			}
			.keyboardShortcut("d", modifiers: [.command])

			Button("Split Down") {
				sceneContext?.splitFocusedPane(.down)
			}
			.keyboardShortcut("d", modifiers: [.command, .shift])
		}
	}
}
