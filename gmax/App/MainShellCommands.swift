//
//  MainShellCommands.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import OSLog
import SwiftUI

struct MainShellCommands: Commands {
	@FocusedObject private var shellModel: ShellModel?
	@FocusedValue(\.selectedWorkspaceSelection) private var selectedWorkspaceSelection
	@FocusedValue(\.openSavedWorkspaceLibraryAction) private var openSavedWorkspaceLibraryAction
	@FocusedValue(\.presentWorkspaceRenameAction) private var presentWorkspaceRenameAction
	@FocusedValue(\.presentWorkspaceDeletionAction) private var presentWorkspaceDeletionAction
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	var body: some Commands {
		SidebarCommands()
		InspectorCommands()
		TextEditingCommands()
		TextFormattingCommands()
		ToolbarCommands()

		CommandGroup(after: .newItem) {
			Button("New Workspace") {
				createWorkspace()
			}
			.keyboardShortcut("n", modifiers: [.command, .shift])
			.disabled(shellModel == nil)
		}

		CommandGroup(after: .newItem) {
			Button("Open Workspace…") {
				openSavedWorkspaceLibraryAction?()
			}
			.keyboardShortcut("o", modifiers: [.command])
			.disabled(openSavedWorkspaceLibraryAction == nil)
		}

		CommandGroup(replacing: .saveItem) {
			Button("Save Workspace") {
				saveSelectedWorkspace()
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceID == nil || shellModel == nil)
		}

		CommandMenu("Workspace") {
			Button("Undo Close Workspace") {
				undoCloseWorkspace()
			}
			.keyboardShortcut("o", modifiers: [.command, .shift])
			.disabled(!(shellModel?.canUndoCloseWorkspace() ?? false))

			Divider()

			Button("Rename Workspace") {
				guard let selectedWorkspaceID else {
					return
				}
				presentWorkspaceRenameAction?(selectedWorkspaceID)
			}
			.disabled(selectedWorkspaceID == nil || presentWorkspaceRenameAction == nil)

			Button("Duplicate Workspace Layout") {
				duplicateSelectedWorkspaceLayout()
			}
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Button("Close Workspace to Library") {
				closeSelectedWorkspaceToLibrary()
			}
			.disabled(!canCloseWorkspace())

			Button("Close Workspace") {
				closeWorkspace()
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(!canCloseWorkspace())

			Button("Delete Workspace", role: .destructive) {
				guard let selectedWorkspaceID else {
					return
				}
				presentWorkspaceDeletionAction?(selectedWorkspaceID)
			}
			.disabled(!canDeleteSelectedWorkspace())

			Divider()

			Button("Previous Workspace") {
				selectPreviousWorkspace()
			}
			.keyboardShortcut("[", modifiers: [.command, .shift])
			.disabled((shellModel?.workspaces.count ?? 0) < 2)

			Button("Next Workspace") {
				selectNextWorkspace()
			}
			.keyboardShortcut("]", modifiers: [.command, .shift])
			.disabled((shellModel?.workspaces.count ?? 0) < 2)
		}

			CommandMenu("Pane") {
				Button("Move Focus Left") {
					movePaneFocus(.left)
				}
			.keyboardShortcut(.leftArrow, modifiers: [.command, .option])

				Button("Move Focus Right") {
					movePaneFocus(.right)
				}
			.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

				Button("Move Focus Up") {
					movePaneFocus(.up)
				}
			.keyboardShortcut(.upArrow, modifiers: [.command, .option])

				Button("Move Focus Down") {
					movePaneFocus(.down)
				}
			.keyboardShortcut(.downArrow, modifiers: [.command, .option])

			Divider()

				Button("Focus Next Pane") {
					movePaneFocus(.next)
				}
			.keyboardShortcut("]", modifiers: [.command, .option])

				Button("Focus Previous Pane") {
					movePaneFocus(.previous)
				}
			.keyboardShortcut("[", modifiers: [.command, .option])

			Section("New Pane") {
					Button("Split Right") {
						splitFocusedPane(.right)
					}
				.keyboardShortcut("d", modifiers: [.command])
				.disabled(!canSplitFocusedPane())

					Button("Split Down") {
						splitFocusedPane(.down)
					}
				.keyboardShortcut("d", modifiers: [.command, .shift])
				.disabled(!canSplitFocusedPane())
			}
		}
	}

	private var selectedWorkspaceID: WorkspaceID? {
		selectedWorkspaceSelection?.wrappedValue
	}

	private func updateSelectedWorkspaceID(_ workspaceID: WorkspaceID?) {
		selectedWorkspaceSelection?.wrappedValue = workspaceID
	}

	private func canDeleteSelectedWorkspace() -> Bool {
		guard let shellModel, let selectedWorkspaceID else {
			return false
		}
		return shellModel.canDeleteWorkspace(selectedWorkspaceID)
	}

	private func canCloseWorkspace() -> Bool {
		selectedWorkspaceID != nil && shellModel != nil
	}

	private func canSplitFocusedPane() -> Bool {
		guard let shellModel, let selectedWorkspaceID else {
			return false
		}
		return shellModel.focusedPane(in: selectedWorkspaceID) != nil
	}

	private func createWorkspace() {
		guard let shellModel else {
			return
		}
		updateSelectedWorkspaceID(shellModel.createWorkspace())
	}

	private func undoCloseWorkspace() {
		guard let shellModel else {
			return
		}
		updateSelectedWorkspaceID(shellModel.undoCloseWorkspace())
	}

	private func duplicateSelectedWorkspaceLayout() {
		guard let shellModel, let selectedWorkspaceID else {
			return
		}
		updateSelectedWorkspaceID(shellModel.duplicateWorkspace(selectedWorkspaceID))
	}

	private func closeSelectedWorkspaceToLibrary() {
		guard let shellModel, let selectedWorkspaceID else {
			return
		}
		updateSelectedWorkspaceID(shellModel.closeWorkspaceToLibrary(selectedWorkspaceID))
	}

	private func selectPreviousWorkspace() {
		guard let shellModel else {
			return
		}

		let workspaces = shellModel.workspaces
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

	private func selectNextWorkspace() {
		guard let shellModel else {
			return
		}

		let workspaces = shellModel.workspaces
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

	private func movePaneFocus(_ direction: PaneFocusDirection) {
		guard let shellModel, let selectedWorkspaceID else {
			return
		}
		shellModel.movePaneFocus(direction, in: selectedWorkspaceID)
	}

	private func splitFocusedPane(_ direction: SplitDirection) {
		guard let shellModel, let selectedWorkspaceID else {
			return
		}
		shellModel.splitFocusedPane(in: selectedWorkspaceID, direction)
	}

	private func saveSelectedWorkspace() {
		guard let shellModel else {
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
		_ = shellModel.saveWorkspaceToLibrary(selectedWorkspaceID)
	}

	private func closeWorkspace() {
		guard let shellModel else {
			return
		}
		guard let selectedWorkspaceID else {
			diagnosticsLogger.notice(
				"Skipped the close-workspace command because the active shell scene has no selected workspace."
			)
			return
		}

		let nextSelectedWorkspaceID = shellModel.closeWorkspace(selectedWorkspaceID)
		diagnosticsLogger.notice(
			"Ran the close-workspace command from the active shell window. Next selected workspace ID: \(nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)"
		)
		updateSelectedWorkspaceID(nextSelectedWorkspaceID)
	}
}
