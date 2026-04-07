//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import AppKit
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
	@StateObject private var shellModel = ShellModel()
	@State private var isBypassingLastPaneCloseConfirmation = false

	private let defaultWindowSize = CGSize(width: 1_440, height: 900)
	private let sidebarColumnWidth: CGFloat = 220
	private let contentColumnIdealWidth: CGFloat = 920
	private let detailColumnMinimumWidth: CGFloat = 220
	private let detailColumnIdealWidth: CGFloat = 260
	private let detailColumnMaximumWidth: CGFloat = 340

	var body: some Scene {
		Window("gmax exploration", id: "main-window") {
			NavigationSplitView(columnVisibility: $shellModel.columnVisibility) {
				SidebarPane(model: shellModel)
					.navigationSplitViewColumnWidth(sidebarColumnWidth)
			} content: {
				ContentPane(model: shellModel)
					.navigationSplitViewColumnWidth(min: 640, ideal: contentColumnIdealWidth)
			} detail: {
				if shellModel.isInspectorVisible {
					DetailPane(model: shellModel)
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
					model: shellModel,
					isBypassingConfirmation: $isBypassingLastPaneCloseConfirmation
				)
				.toolbar {
				ToolbarItem(placement: .navigation) {
					Button {
						shellModel.createWorkspace()
					} label: {
						Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
					}
				}

					ToolbarItem(placement: .automatic) {
					Button {
						shellModel.createPane()
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
		}
		.defaultSize(defaultWindowSize)
		.commands {
			CommandGroup(replacing: .newItem) {
				Button("New Workspace") {
					shellModel.createWorkspace()
				}
				.keyboardShortcut("n", modifiers: [.command])
			}

			CommandGroup(replacing: .saveItem) {
				Button("Close") {
					if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
						NSApp.keyWindow?.performClose(nil)
						return
					}

						switch shellModel.performCloseCommand() {
							case .closeWindow:
								NSApp.keyWindow?.performClose(nil)
							case .closedPane, .closedWorkspace, .noAction:
								break
						}
					}
				.keyboardShortcut("w", modifiers: [.command])
			}

			CommandGroup(after: .windowSize) {
				Button(shellModel.columnVisibility == .all ? "Hide Sidebar" : "Show Sidebar") {
					shellModel.toggleSidebar()
				}
				.keyboardShortcut("b", modifiers: [.command])

				Button(shellModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
					shellModel.toggleInspector()
				}
				.keyboardShortcut("b", modifiers: [.command, .shift])

				Divider()

				Button("Previous Workspace") {
					shellModel.selectPreviousWorkspace()
				}
				.keyboardShortcut("[", modifiers: [.command, .shift])

				Button("Next Workspace") {
					shellModel.selectNextWorkspace()
				}
				.keyboardShortcut("]", modifiers: [.command, .shift])
			}

			CommandMenu("Pane") {
				Button("New Pane") {
					shellModel.createPane()
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
					shellModel.splitFocusedPane(.right)
				}
				.keyboardShortcut("d", modifiers: [.command])

				Button("Split Down") {
					shellModel.splitFocusedPane(.down)
				}
				.keyboardShortcut("d", modifiers: [.command, .shift])

				Divider()

				Button("Close Pane") {
					_ = shellModel.performCloseCommand()
				}
			}
		}
		Settings {
			SettingsUtilityWindow()
				.windowRole(.settings)
		}
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
	@ObservedObject var model: ShellModel
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

			guard parent.model.requiresLastPaneCloseConfirmation else {
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
		model: ShellModel,
		isBypassingConfirmation: Binding<Bool>
	) -> some View {
		background(
			WindowCloseConfirmationAccessor(
				model: model,
				isBypassingConfirmation: isBypassingConfirmation
			)
		)
	}
}
