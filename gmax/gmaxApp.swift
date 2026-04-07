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
			.toolbar {
				ToolbarItem(placement: .navigation) {
					Button {
						shellModel.createWorkspace()
					} label: {
						Label("New Workspace", systemImage: "square.stack.badge.plus")
					}
				}

				ToolbarItem(placement: .principal) {
					Button {
						shellModel.createPane()
					} label: {
						Label("New Pane", systemImage: "square.split.2x1")
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

extension View {
	func windowRole(_ role: AppWindowRole) -> some View {
		background(WindowRoleAccessor(role: role))
	}
}
