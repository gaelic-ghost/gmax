//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import AppKit
import SwiftUI

@main
struct gmaxApp: App {
	@StateObject private var shellModel = ShellModel()

	var body: some Scene {
		Window("gmax exploration", id: "main-window") {
			NavigationSplitView(columnVisibility: $shellModel.columnVisibility) {
				SidebarPane(model: shellModel)
			} content: {
				ContentPane(model: shellModel)
			} detail: {
				DetailPane(model: shellModel)
			}
		}
		.commands {
			CommandGroup(replacing: .saveItem) {
				Button("Close") {
					switch shellModel.performCloseCommand() {
						case .closeWindow:
							NSApp.keyWindow?.performClose(nil)
						case .closedPane, .emptiedWorkspace, .closedWorkspace, .noAction:
							break
					}
				}
				.keyboardShortcut("w", modifiers: [.command])
			}

			CommandMenu("Pane") {
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
	}
}
