//
//  DetailPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct DetailPane: View {
	@ObservedObject var model: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?

	var body: some View {
		let workspace = selectedWorkspaceID.flatMap { workspaceID in
			model.workspaces.first { $0.id == workspaceID }
		}
		if let workspace,
		   let focusedPaneID = workspace.focusedPaneID,
		   let pane = workspace.root?.findPane(id: focusedPaneID),
		   let session = model.sessions.session(for: pane.sessionID) {
			ActivePaneDetails(
				workspaceTitle: workspace.title,
				pane: pane,
				session: session
			)
		} else if let workspace {
			WorkspaceDetails(
				workspaceTitle: workspace.title,
				paneCount: workspace.root?.leaves().count ?? 0
			)
		} else {
			ContentUnavailableView {
				Label("No Workspace Selected", systemImage: "rectangle.on.rectangle")
			} description: {
				Text("Choose a workspace and focus a pane to inspect its live shell session here.")
			}
		}
	}
}

private struct ActivePaneDetails: View {
	let workspaceTitle: String
	let pane: PaneLeaf
	@ObservedObject var session: TerminalSession

	var body: some View {
		let state = switch session.state {
			case .idle: "Idle"
			case .running: "Running"
			case .exited(let exitCode): exitCode.map { "Exited (\($0))" } ?? "Exited"
		}
		VStack(alignment: .leading, spacing: 16) {
			Text("Active Pane")
				.font(.title2.weight(.semibold))

			Group {
				DetailValue(
					"Workspace",
					workspaceTitle,
					valueIdentifier: "detailPane.workspaceTitleValue"
				)
				DetailValue("Title", session.title)
				DetailValue("State", state)
				DetailValue("Current Directory", session.currentDirectory ?? "Unavailable")
				DetailValue("Pane ID", pane.id.rawValue.uuidString)
				DetailValue("Session ID", pane.sessionID.rawValue.uuidString)
			}

			Spacer()
		}
		.padding()
		.accessibilityIdentifier("detailPane.activePane")
	}
}

private struct WorkspaceDetails: View {
	let workspaceTitle: String
	let paneCount: Int

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Workspace")
				.font(.title2.weight(.semibold))

			Group {
				DetailValue(
					"Workspace",
					workspaceTitle,
					valueIdentifier: "detailPane.workspaceTitleValue"
				)
				DetailValue(
					"Pane Count",
					paneCount == 1 ? "1 pane" : "\(paneCount) panes",
					valueIdentifier: "detailPane.paneCountValue"
				)
				DetailValue(
					"Status",
					paneCount == 0
						? "This workspace is empty and ready for a fresh shell."
						: "Select a pane to inspect its shell session.",
					valueIdentifier: "detailPane.statusValue"
				)
			}

			Spacer()
		}
		.padding()
		.accessibilityIdentifier("detailPane.workspace")
	}

}

private struct DetailValue: View {
	let label: String
	let value: String
	let valueIdentifier: String?

	init(_ label: String, _ value: String, valueIdentifier: String? = nil) {
		self.label = label
		self.value = value
		self.valueIdentifier = valueIdentifier
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			if let valueIdentifier {
				Text(value)
					.font(.system(.body, design: .monospaced))
					.textSelection(.enabled)
					.accessibilityIdentifier(valueIdentifier)
			} else {
				Text(value)
					.font(.system(.body, design: .monospaced))
					.textSelection(.enabled)
			}
		}
	}
}

#Preview {
	DetailPane(model: ShellModel(), selectedWorkspaceID: .constant(nil))
}
