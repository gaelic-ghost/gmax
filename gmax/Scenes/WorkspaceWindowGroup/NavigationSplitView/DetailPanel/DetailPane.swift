//
//  DetailPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct DetailPane: View {
	@ObservedObject var model: WorkspaceStore
	@Binding var selectedWorkspaceID: WorkspaceID?
	let inspectedPaneID: PaneID?
	let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding

	var body: some View {
		let workspace = selectedWorkspaceID.flatMap { workspaceID in
			model.workspaces.first { $0.id == workspaceID }
		}
		detailContent(workspace: workspace)
			.focusable(interactions: .activate)
			.focused(focusedTarget, equals: .inspector)
			.contentShape(Rectangle())
			.accessibilityRespondsToUserInteraction(true)
			.accessibilityAddTraits(focusedTarget.wrappedValue == .inspector ? .isSelected : [])
	}

	@ViewBuilder
	private func detailContent(workspace: Workspace?) -> some View {
		if let workspace,
		   let inspectedPaneID,
		   let pane = workspace.root?.findPane(id: inspectedPaneID),
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
				DetailValue(label: "Workspace", value: workspaceTitle)
					.accessibilityIdentifier("detailPane.workspaceTitleValue")
				DetailValue(label: "Title", value: session.title)
				DetailValue(label: "State", value: state)
				DetailValue(label: "Current Directory", value: session.currentDirectory ?? "Unavailable")
				DetailValue(label: "Pane ID", value: pane.id.rawValue.uuidString)
				DetailValue(label: "Session ID", value: pane.sessionID.rawValue.uuidString)
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
				DetailValue(label: "Workspace", value: workspaceTitle)
					.accessibilityIdentifier("detailPane.workspaceTitleValue")
				DetailValue(label: "Pane Count", value: paneCount == 1 ? "1 pane" : "\(paneCount) panes")
					.accessibilityIdentifier("detailPane.paneCountValue")
				DetailValue(
					label: "Status",
					value: paneCount == 0
						? "This workspace is empty and ready for a fresh shell."
						: "Select a pane to inspect its shell session."
				)
				.accessibilityIdentifier("detailPane.statusValue")
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

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.system(.body, design: .monospaced))
				.textSelection(.enabled)
		}
	}
}

#Preview {
	DetailPanePreview()
}

private struct DetailPanePreview: View {
	@FocusState private var focusedTarget: WorkspaceFocusTarget?

	var body: some View {
		DetailPane(
			model: WorkspaceStore(),
			selectedWorkspaceID: .constant(nil),
			inspectedPaneID: nil,
			focusedTarget: $focusedTarget
		)
	}
}
