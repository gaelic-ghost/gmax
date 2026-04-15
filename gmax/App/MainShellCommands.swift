//
//  MainShellCommands.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

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

struct MainShellCommands: Commands {
	@Environment(\.dismiss) private var dismiss
	@FocusedObject private var shellModel: ShellModel?
	@FocusedValue(\.selectedWorkspaceSelection) private var selectedWorkspaceSelection
	@FocusedValue(\.openSavedWorkspaceLibrary) private var openSavedWorkspaceLibrary
	@FocusedValue(\.presentWorkspaceRename) private var presentWorkspaceRename
	@FocusedValue(\.presentWorkspaceDeletion) private var presentWorkspaceDeletion
	@FocusedValue(\.closeFocusedPane) private var closeFocusedPane
	@FocusedValue(\.closeEmptyWorkspace) private var closeEmptyWorkspace
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	var body: some Commands {
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
				saveSelectedWorkspace()
			}
			.keyboardShortcut("s", modifiers: [.command])
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Divider()

			Button(closeCommandTitle) {
				closeActiveContext()
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
			.disabled(!(shellModel?.canUndoCloseWorkspace() ?? false))

			Divider()

				Button("Rename Workspace") {
					guard let selectedWorkspaceID else {
						return
					}
					presentWorkspaceRename?(selectedWorkspaceID)
				}
				.disabled(selectedWorkspaceID == nil || presentWorkspaceRename == nil)

			Button("Duplicate Workspace Layout") {
				guard let shellModel, let selectedWorkspaceID else {
					return
				}
				selectedWorkspaceSelection?.wrappedValue = shellModel.duplicateWorkspace(selectedWorkspaceID)
			}
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Button("Close Workspace to Library") {
				guard let shellModel, let selectedWorkspaceID else {
					return
				}
				selectedWorkspaceSelection?.wrappedValue = shellModel.closeWorkspaceToLibrary(selectedWorkspaceID)
			}
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

			Button("Close Workspace") {
				closeWorkspace()
			}
			.keyboardShortcut("w", modifiers: [.command, .option])
			.disabled(selectedWorkspaceID == nil || shellModel == nil)

				Button("Delete Workspace", role: .destructive) {
					guard let selectedWorkspaceID else {
						return
					}
					presentWorkspaceDeletion?(selectedWorkspaceID)
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

	private func canDeleteSelectedWorkspace() -> Bool {
		guard let shellModel, let selectedWorkspaceID else {
			return false
		}
		return shellModel.canDeleteWorkspace(selectedWorkspaceID)
	}

	private func canSplitFocusedPane() -> Bool {
		guard let shellModel, let selectedWorkspaceID else {
			return false
		}
		guard
			let workspace = shellModel.workspaces.first(where: { $0.id == selectedWorkspaceID }),
			let focusedPaneID = workspace.focusedPaneID
		else {
			return false
		}
		return workspace.root?.findPane(id: focusedPaneID) != nil
	}

	private func selectPreviousWorkspace() {
		let workspaces = shellModel?.workspaces ?? []
		guard !workspaces.isEmpty else {
			selectedWorkspaceSelection?.wrappedValue = nil
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
			selectedWorkspaceSelection?.wrappedValue = workspaces.last?.id
			return
		}

		let previousIndex = (currentIndex - 1 + workspaces.count) % workspaces.count
		selectedWorkspaceSelection?.wrappedValue = workspaces[previousIndex].id
	}

	private func selectNextWorkspace() {
		let workspaces = shellModel?.workspaces ?? []
		guard !workspaces.isEmpty else {
			selectedWorkspaceSelection?.wrappedValue = nil
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
			selectedWorkspaceSelection?.wrappedValue = workspaces.first?.id
			return
		}

		let nextIndex = (currentIndex + 1) % workspaces.count
		selectedWorkspaceSelection?.wrappedValue = workspaces[nextIndex].id
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

	private var closeCommandTitle: String {
		if closeFocusedPane != nil {
			return "Close Pane"
		}
		if closeEmptyWorkspace != nil {
			return "Close Workspace"
		}
		return "Close Window"
	}

	private func closeActiveContext() {
		if let closeFocusedPane {
			closeFocusedPane()
			return
		}
		if let closeEmptyWorkspace {
			closeEmptyWorkspace()
			return
		}
		dismiss()
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
		selectedWorkspaceSelection?.wrappedValue = nextSelectedWorkspaceID
	}
}
