//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import AppKit
import OSLog
import SwiftUI

enum AppWindowRole: String {
	case mainShell
	case settings

	var identifier: NSUserInterfaceItemIdentifier {
		NSUserInterfaceItemIdentifier(rawValue)
	}
}

@main
struct gmaxApp: App {
	@StateObject private var shellModel: ShellModel
	@State private var selectedWorkspaceID: WorkspaceID?
	@State private var isBypassingLastPaneCloseConfirmation = false
	@State private var isSavedWorkspaceLibraryPresented = false
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	init() {
		WorkspacePersistenceDefaults.registerDefaults()
		let shellModel = ShellModel()
		_shellModel = StateObject(wrappedValue: shellModel)
		_selectedWorkspaceID = State(initialValue: shellModel.normalizedWorkspaceSelection(nil))
	}

	var body: some Scene {
			Window("gmax exploration", id: "main-window") {
				MainShellSceneView(
					shellModel: shellModel,
					selectedWorkspaceID: $selectedWorkspaceID,
					isBypassingLastPaneCloseConfirmation: $isBypassingLastPaneCloseConfirmation,
					isSavedWorkspaceLibraryPresented: $isSavedWorkspaceLibraryPresented
				)
		}
		.defaultSize(width: 1_440, height: 900)
		.commands {
			CommandGroup(replacing: .newItem) {
				Button("New Workspace") {
					selectedWorkspaceID = shellModel.createWorkspace()
				}
				.keyboardShortcut("n", modifiers: [.command])
			}

			CommandGroup(after: .newItem) {
				Button("Open Workspace…") {
					isSavedWorkspaceLibraryPresented = true
				}
				.keyboardShortcut("o", modifiers: [.command])
			}

			CommandGroup(replacing: .saveItem) {
				Button("Save Workspace") {
					saveSelectedWorkspace()
				}
				.keyboardShortcut("s", modifiers: [.command])
				.disabled(selectedWorkspaceID == nil)

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
					selectedWorkspaceID = shellModel.undoCloseWorkspace()
				}
				.keyboardShortcut("o", modifiers: [.command, .shift])
				.disabled(!shellModel.canUndoCloseWorkspace())

				Divider()

				Button("Rename Workspace") {
					guard let workspace = selectedWorkspace else {
						return
					}
					presentWorkspaceRename(for: workspace)
				}
				.disabled(selectedWorkspace == nil)

				Button("Duplicate Workspace Layout") {
					guard let workspaceID = selectedWorkspaceID else {
						return
					}
					selectedWorkspaceID = shellModel.duplicateWorkspace(workspaceID)
				}
				.disabled(selectedWorkspaceID == nil)

				Button("Close Workspace to Library") {
					guard let workspaceID = selectedWorkspaceID else {
						return
					}
					selectedWorkspaceID = shellModel.closeWorkspaceToLibrary(workspaceID).nextSelectedWorkspaceID
				}
				.disabled(!canCloseWorkspaceToLibrary)

				Button("Close Workspace") {
					performWorkspaceClose()
				}
				.keyboardShortcut("w", modifiers: [.command, .option])
				.disabled(!canCloseWorkspace)

				Button("Delete Workspace", role: .destructive) {
					guard let workspaceID = selectedWorkspaceID else {
						return
					}
					shellModel.deleteWorkspace(workspaceID)
					selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
				}
				.disabled(!canDeleteSelectedWorkspace)

				Divider()

				Button("Previous Workspace") {
					selectedWorkspaceID = shellModel.selectPreviousWorkspace()
				}
				.keyboardShortcut("[", modifiers: [.command, .shift])
				.disabled(shellModel.workspaces.count < 2)

				Button("Next Workspace") {
					selectedWorkspaceID = shellModel.selectNextWorkspace()
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
					if let workspaceID = selectedWorkspaceID {
						selectedWorkspaceID = shellModel.createPane(in: workspaceID)
					} else {
						selectedWorkspaceID = shellModel.createWorkspace()
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
					if let workspaceID = selectedWorkspaceID {
						shellModel.splitFocusedPane(in: workspaceID, .right)
					}
				}
				.keyboardShortcut("d", modifiers: [.command])

				Button("Split Down") {
					if let workspaceID = selectedWorkspaceID {
						shellModel.splitFocusedPane(in: workspaceID, .down)
					}
				}
				.keyboardShortcut("d", modifiers: [.command, .shift])
			}
		}
		Settings {
			SettingsUtilityWindow(model: shellModel)
				.windowRole(.settings)
		}
	}

	private func performContextualClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice("The contextual close command targeted the Settings window, so the app is closing that window directly.")
			NSApp.keyWindow?.performClose(nil)
			return
		}

		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		let outcome = shellModel.performCloseCommand()
		diagnosticsLogger.notice("Ran the contextual close command from the main shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)")
		selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		switch outcome.result {
			case .closeWindow:
				diagnosticsLogger.notice("The contextual close command resolved to closing the active window.")
				NSApp.keyWindow?.performClose(nil)
			case .closedPane, .closedWorkspace, .noAction:
				break
		}
	}

	private func performWorkspaceClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice("The close-workspace command was invoked while the Settings window was active, so the app is closing that window instead.")
			NSApp.keyWindow?.performClose(nil)
			return
		}

		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		let outcome = shellModel.closeSelectedWorkspace()
		diagnosticsLogger.notice("Ran the close-workspace command from the main shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)")
		selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		switch outcome.result {
			case .closeWindow:
				diagnosticsLogger.notice("The close-workspace command resolved to closing the active window.")
				NSApp.keyWindow?.performClose(nil)
			case .closedWorkspace, .closedPane, .noAction:
				break
		}
	}

	private func performWindowClose() {
		diagnosticsLogger.notice("Requested that the active app window close immediately.")
		NSApp.keyWindow?.performClose(nil)
	}

	private var selectedWorkspace: Workspace? {
		guard let selectedWorkspaceID else {
			return nil
		}
		return shellModel.workspace(for: selectedWorkspaceID)
	}

	private var canDeleteSelectedWorkspace: Bool {
		guard let selectedWorkspaceID else {
			return false
		}
		return shellModel.canDeleteWorkspace(selectedWorkspaceID)
	}

	private var canCloseWorkspace: Bool {
		selectedWorkspaceID != nil && shellModel.workspaces.count > 1
	}

	private var canCloseWorkspaceToLibrary: Bool {
		canCloseWorkspace
	}

	private func saveSelectedWorkspace() {
		guard let workspaceID = selectedWorkspaceID else {
			diagnosticsLogger.error("The app received a save-workspace command, but there is no selected workspace to save.")
			return
		}
		diagnosticsLogger.notice("Requested that the selected workspace be saved to the workspace library. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
		_ = shellModel.saveWorkspaceToLibrary(workspaceID)
	}

	private func presentWorkspaceRename(for workspace: Workspace) {
		diagnosticsLogger.notice("Requested that the workspace rename sheet open for the selected workspace. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
		NotificationCenter.default.post(
			name: .presentWorkspaceRenameSheet,
			object: workspace.id
		)
	}
}

extension Notification.Name {
	static let presentWorkspaceRenameSheet = Notification.Name("gmax.presentWorkspaceRenameSheet")
}

private struct MainShellSceneView: View {
	@ObservedObject var shellModel: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?
	@Binding var isBypassingLastPaneCloseConfirmation: Bool
	@Binding var isSavedWorkspaceLibraryPresented: Bool
	@SceneStorage("mainShell.selectedWorkspaceID") private var restoredSelectedWorkspaceID: String?
	@SceneStorage("mainShell.isInspectorVisible") private var restoredInspectorVisible = true
	@State private var hasAppliedSceneState = false
	private let appLogger = Logger.gmax(.app)

	private let sidebarColumnWidth: CGFloat = 220
	private let contentColumnIdealWidth: CGFloat = 920
	private let detailColumnMinimumWidth: CGFloat = 220
	private let detailColumnIdealWidth: CGFloat = 260
	private let detailColumnMaximumWidth: CGFloat = 340

	var body: some View {
		NavigationSplitView(columnVisibility: $shellModel.columnVisibility) {
			SidebarPane(model: shellModel, selection: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(sidebarColumnWidth)
		} content: {
			ContentPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(min: 640, ideal: contentColumnIdealWidth)
		} detail: {
			if shellModel.isInspectorVisible {
				DetailPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
						.navigationSplitViewColumnWidth(
						min: detailColumnMinimumWidth,
						ideal: detailColumnIdealWidth,
						max: detailColumnMaximumWidth
					)
			} else {
				Color.clear
					.navigationSplitViewColumnWidth(0)
			}
		}
		.windowRole(.mainShell)
		.windowCloseConfirmation(
			requiresConfirmation: shellModel.requiresLastPaneCloseConfirmation,
			isBypassingConfirmation: $isBypassingLastPaneCloseConfirmation
		)
			.sheet(isPresented: $isSavedWorkspaceLibraryPresented) {
				SavedWorkspaceLibrarySheet(
					model: shellModel,
					selectedWorkspaceID: $selectedWorkspaceID,
					isPresented: $isSavedWorkspaceLibraryPresented
				)
			}
		.toolbar {
				ToolbarItem(placement: .navigation) {
					Button {
						selectedWorkspaceID = shellModel.createWorkspace()
					} label: {
					Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
				}
			}

			ToolbarItem(placement: .automatic) {
				Button {
					isSavedWorkspaceLibraryPresented = true
				} label: {
					Label("Open Saved Workspaces", systemImage: "folder")
				}
				.help("Open saved workspaces (\u{2318}O)")
			}

			ToolbarItem(placement: .automatic) {
				Button {
					if let workspaceID = selectedWorkspaceID {
						selectedWorkspaceID = shellModel.createPane(in: workspaceID)
					} else {
						selectedWorkspaceID = shellModel.createWorkspace()
					}
				} label: {
					Label("New Pane", systemImage: "uiwindow.split.2x1")
				}
			}

			ToolbarItem(placement: .automatic) {
				Button {
					shellModel.toggleInspector()
				} label: {
					Label(
						shellModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
						systemImage: "sidebar.right"
					)
				}
			}
		}
		.task {
			applySceneStateIfNeeded()
		}
			.onChange(of: selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
				restoredSelectedWorkspaceID = newValue
				shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
			}
			.onChange(of: shellModel.workspaces.map(\.id.rawValue)) { _, _ in
				let normalizedSelection = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
				if normalizedSelection != selectedWorkspaceID {
					selectedWorkspaceID = normalizedSelection
				}
				shellModel.setCurrentWorkspaceID(normalizedSelection)
			}
			.onChange(of: shellModel.isInspectorVisible) { _, newValue in
				restoredInspectorVisible = newValue
			}
	}

	private func applySceneStateIfNeeded() {
		guard !hasAppliedSceneState else {
			return
		}

		hasAppliedSceneState = true
		shellModel.setInspectorVisible(restoredInspectorVisible)

		let restoredSelection = restoredSelectedWorkspaceID
			.flatMap(UUID.init(uuidString:))
			.map { WorkspaceID(rawValue: $0) }
		let normalizedSelection = shellModel.normalizedWorkspaceSelection(restoredSelection ?? selectedWorkspaceID)
		appLogger.notice("Applied per-scene shell state restoration. Restored workspace selection: \(restoredSelection?.rawValue.uuidString ?? "(none)", privacy: .public). Normalized workspace selection: \(normalizedSelection?.rawValue.uuidString ?? "(none)", privacy: .public). Restored inspector visibility: \(restoredInspectorVisible ? "visible" : "hidden", privacy: .public)")
		selectedWorkspaceID = normalizedSelection
		shellModel.setCurrentWorkspaceID(normalizedSelection)
	}
}

struct WindowRoleAccessor: NSViewRepresentable {
	let role: AppWindowRole

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: .zero)
		view.isHidden = true
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		DispatchQueue.main.async {
			nsView.window?.identifier = role.identifier
		}
	}
}

struct WindowCloseConfirmationAccessor: NSViewRepresentable {
	let requiresConfirmation: Bool
	@Binding var isBypassingConfirmation: Bool

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	func makeNSView(context: Context) -> NSView {
		let view = NSView(frame: .zero)
		view.isHidden = true
		return view
	}

	func updateNSView(_ nsView: NSView, context: Context) {
		context.coordinator.parent = self
		DispatchQueue.main.async {
			guard let window = nsView.window else {
				return
			}
			if context.coordinator.window !== window {
				context.coordinator.window = window
				window.delegate = context.coordinator
			}
		}
	}

	final class Coordinator: NSObject, NSWindowDelegate {
		var parent: WindowCloseConfirmationAccessor
		weak var window: NSWindow?
		private var isPresentingConfirmation = false

		init(parent: WindowCloseConfirmationAccessor) {
			self.parent = parent
		}

		func windowShouldClose(_ sender: NSWindow) -> Bool {
			if parent.isBypassingConfirmation {
				parent.isBypassingConfirmation = false
				return true
			}

			guard parent.requiresConfirmation else {
				return true
			}

			guard !isPresentingConfirmation else {
				return false
			}

			isPresentingConfirmation = true

			let alert = NSAlert()
			alert.alertStyle = .warning
			alert.messageText = "Quit gmax?"
			alert.informativeText = "Closing the last pane will also close gmax. Are you sure you want to continue?"
			alert.addButton(withTitle: "Quit")
			alert.addButton(withTitle: "Cancel")
			alert.beginSheetModal(for: sender) { [weak self] response in
				guard let self else {
					return
				}
				self.isPresentingConfirmation = false
				guard response == .alertFirstButtonReturn else {
					return
				}
				self.parent.isBypassingConfirmation = true
				sender.performClose(nil)
			}
			return false
		}
	}
}

extension View {
	func windowRole(_ role: AppWindowRole) -> some View {
		background(WindowRoleAccessor(role: role))
	}

	func windowCloseConfirmation(
		requiresConfirmation: Bool,
		isBypassingConfirmation: Binding<Bool>
	) -> some View {
		background(
			WindowCloseConfirmationAccessor(
				requiresConfirmation: requiresConfirmation,
				isBypassingConfirmation: isBypassingConfirmation
			)
		)
	}
}
