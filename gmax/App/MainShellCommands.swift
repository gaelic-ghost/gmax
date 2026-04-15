//
//  MainShellCommands.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import OSLog
import SwiftUI

struct MainShellCommands: Commands {
	@FocusedValue(\.mainShellSceneContext) private var sceneContext
	@FocusedValue(\.selectedWorkspaceSelection) private var selectedWorkspaceSelection
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	var body: some Commands {
		SidebarCommands()
		InspectorCommands()
		TextEditingCommands()
		TextFormattingCommands()
		ToolbarCommands()

		CommandGroup(after: .newItem) {
			Button("New Workspace") {
				createWorkspace(in: sceneContext)
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])
			.disabled(sceneContext == nil)
		}

		CommandGroup(after: .newItem) {
			Button("Open Workspace…") {
				sceneContext?.isSavedWorkspaceLibraryPresented = true
			}
			.keyboardShortcut("o", modifiers: [.command])
			.disabled(sceneContext == nil)
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save Workspace") {
				saveSelectedWorkspace(in: sceneContext)
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceID == nil)
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				undoCloseWorkspace(in: sceneContext)
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(!(sceneContext?.shellModel.canUndoCloseWorkspace() ?? false))

			Divider()

			Button("Rename Workspace") {
				guard let sceneContext, let selectedWorkspaceID else {
					return
				}
				presentWorkspaceRename(for: selectedWorkspaceID, in: sceneContext)
			}
			.disabled(selectedWorkspaceID == nil)

			Button("Duplicate Workspace Layout") {
				duplicateSelectedWorkspaceLayout(in: sceneContext)
			}
			.disabled(selectedWorkspaceID == nil)

			Button("Close Workspace to Library") {
				closeSelectedWorkspaceToLibrary(in: sceneContext)
			}
			.disabled(!canCloseWorkspace(in: sceneContext))

			Button("Close Workspace") {
				closeWorkspace(in: sceneContext)
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(!canCloseWorkspace(in: sceneContext))

			Button("Delete Workspace", role: .destructive) {
				guard let sceneContext, let selectedWorkspaceID else {
					return
				}
				presentWorkspaceDeletionConfirmation(for: selectedWorkspaceID, in: sceneContext)
			}
			.disabled(!canDeleteSelectedWorkspace(in: sceneContext))

			Divider()

			Button("Previous Workspace") {
				selectPreviousWorkspace(in: sceneContext)
			}
			.keyboardShortcut("[", modifiers: [.command, .shift])
			.disabled((sceneContext?.shellModel.workspaces.count ?? 0) < 2)

			Button("Next Workspace") {
				selectNextWorkspace(in: sceneContext)
			}
			.keyboardShortcut("]", modifiers: [.command, .shift])
			.disabled((sceneContext?.shellModel.workspaces.count ?? 0) < 2)
		}

			CommandMenu("Pane") {
				Button("Move Focus Left") {
					movePaneFocus(.left, in: sceneContext)
				}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

				Button("Move Focus Right") {
					movePaneFocus(.right, in: sceneContext)
				}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

				Button("Move Focus Up") {
					movePaneFocus(.up, in: sceneContext)
				}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])

				Button("Move Focus Down") {
					movePaneFocus(.down, in: sceneContext)
				}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])

			Divider()

				Button("Focus Next Pane") {
					movePaneFocus(.next, in: sceneContext)
				}
			.keyboardShortcut("]", modifiers: [.command, .option])

				Button("Focus Previous Pane") {
					movePaneFocus(.previous, in: sceneContext)
				}
			.keyboardShortcut("[", modifiers: [.command, .option])

			Section("New Pane") {
					Button("Split Right") {
						splitFocusedPane(.right, in: sceneContext)
					}
				.keyboardShortcut("d", modifiers: [.command])
				.disabled(!canSplitFocusedPane(in: sceneContext))

					Button("Split Down") {
						splitFocusedPane(.down, in: sceneContext)
					}
				.keyboardShortcut("d", modifiers: [.command, .shift])
				.disabled(!canSplitFocusedPane(in: sceneContext))
			}
		}
	}

	private var selectedWorkspaceID: WorkspaceID? {
		selectedWorkspaceSelection?.wrappedValue
	}

	private func updateSelectedWorkspaceID(_ workspaceID: WorkspaceID?) {
		selectedWorkspaceSelection?.wrappedValue = workspaceID
	}

	private func canDeleteSelectedWorkspace(in sceneContext: MainShellSceneContext?) -> Bool {
		guard let sceneContext, let selectedWorkspaceID else {
			return false
		}
		return sceneContext.shellModel.canDeleteWorkspace(selectedWorkspaceID)
	}

	private func canCloseWorkspace(in sceneContext: MainShellSceneContext?) -> Bool {
		guard sceneContext != nil else {
			return false
		}
		return selectedWorkspaceID != nil
	}

	private func canSplitFocusedPane(in sceneContext: MainShellSceneContext?) -> Bool {
		guard let sceneContext, let selectedWorkspaceID else {
			return false
		}
		return sceneContext.shellModel.focusedPane(in: selectedWorkspaceID) != nil
	}

	private func createWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}
		updateSelectedWorkspaceID(sceneContext.shellModel.createWorkspace())
	}

	private func presentWorkspaceRename(for workspaceID: WorkspaceID, in sceneContext: MainShellSceneContext) {
		guard let workspace = sceneContext.shellModel.workspace(for: workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting the workspace rename sheet because the requested workspace no longer exists in the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		sceneContext.workspaceRenameTitleDraft = workspace.title
		sceneContext.workspacePendingRenameID = workspace.id
		updateSelectedWorkspaceID(workspace.id)
		diagnosticsLogger.notice(
			"Presented the workspace rename sheet for the active shell window. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)"
		)
	}

	private func presentWorkspaceDeletionConfirmation(for workspaceID: WorkspaceID, in sceneContext: MainShellSceneContext) {
		guard sceneContext.shellModel.canDeleteWorkspace(workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		sceneContext.workspacePendingDeletionID = workspaceID
		diagnosticsLogger.notice(
			"Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
		)
	}

	private func undoCloseWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}
		updateSelectedWorkspaceID(sceneContext.shellModel.undoCloseWorkspace())
	}

	private func duplicateSelectedWorkspaceLayout(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext, let selectedWorkspaceID else {
			return
		}
		updateSelectedWorkspaceID(sceneContext.shellModel.duplicateWorkspace(selectedWorkspaceID))
	}

	private func closeSelectedWorkspaceToLibrary(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext, let selectedWorkspaceID else {
			return
		}
		updateSelectedWorkspaceID(sceneContext.shellModel.closeWorkspaceToLibrary(selectedWorkspaceID))
	}

	private func selectPreviousWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}

		let workspaces = sceneContext.shellModel.workspaces
		guard !workspaces.isEmpty else {
			updateSelectedWorkspaceID(nil)
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
			updateSelectedWorkspaceID(workspaces.last?.id)
			return
		}

		let previousIndex = (currentIndex - 1 + workspaces.count) % workspaces.count
		updateSelectedWorkspaceID(workspaces[previousIndex].id)
	}

	private func selectNextWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}

		let workspaces = sceneContext.shellModel.workspaces
		guard !workspaces.isEmpty else {
			updateSelectedWorkspaceID(nil)
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
			updateSelectedWorkspaceID(workspaces.first?.id)
			return
		}

		let nextIndex = (currentIndex + 1) % workspaces.count
		updateSelectedWorkspaceID(workspaces[nextIndex].id)
	}

	private func movePaneFocus(_ direction: PaneFocusDirection, in sceneContext: MainShellSceneContext?) {
		guard let sceneContext, let selectedWorkspaceID else {
			return
		}
		sceneContext.shellModel.movePaneFocus(direction, in: selectedWorkspaceID)
	}

	private func splitFocusedPane(_ direction: SplitDirection, in sceneContext: MainShellSceneContext?) {
		guard let sceneContext, let selectedWorkspaceID else {
			return
		}
		sceneContext.shellModel.splitFocusedPane(in: selectedWorkspaceID, direction)
	}

	private func saveSelectedWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}
		guard let selectedWorkspaceID else {
			diagnosticsLogger.error(
				"The app received a save-workspace command for the active shell window, but that window has no selected workspace to save."
			)
			return
		}

		diagnosticsLogger.notice(
			"Requested that the selected workspace be saved to the workspace library from the active shell window. Workspace ID: \(selectedWorkspaceID.rawValue.uuidString, privacy: .public)"
		)
		_ = sceneContext.shellModel.saveWorkspaceToLibrary(selectedWorkspaceID)
	}

	private func closeWorkspace(in sceneContext: MainShellSceneContext?) {
		guard let sceneContext else {
			return
		}
		guard let selectedWorkspaceID else {
			diagnosticsLogger.notice(
				"Skipped the close-workspace command because the active shell scene has no selected workspace."
			)
			return
		}

		let nextSelectedWorkspaceID = sceneContext.shellModel.closeWorkspace(selectedWorkspaceID)
		diagnosticsLogger.notice(
			"Ran the close-workspace command from the active shell window. Next selected workspace ID: \(nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)"
		)
		updateSelectedWorkspaceID(nextSelectedWorkspaceID)
	}
}
