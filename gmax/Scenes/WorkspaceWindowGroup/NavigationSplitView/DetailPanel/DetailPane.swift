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
           let pane = workspace.root?.findPane(id: inspectedPaneID) {
            if let sessionID = pane.terminalSessionID,
               let session = model.sessions.session(for: sessionID) {
                ActivePaneDetails(
                    workspaceTitle: workspace.title,
                    pane: pane,
                    session: session,
                )
            } else if let sessionID = pane.browserSessionID,
                      let session = model.browserSessions.session(for: sessionID) {
                BrowserPaneDetails(
                    workspaceTitle: workspace.title,
                    pane: pane,
                    session: session,
                    controller: model.browserPaneControllers.controller(
                        for: pane,
                        session: session,
                    ),
                )
            } else {
                UnsupportedPaneDetails(
                    workspaceTitle: workspace.title,
                    pane: pane,
                )
            }
        } else if let workspace {
            WorkspaceDetails(
                workspaceTitle: workspace.title,
                paneCount: workspace.root?.leaves().count ?? 0,
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
            case let .exited(exitCode): exitCode.map { "Exited (\($0))" } ?? "Exited"
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
                DetailValue(label: "Session ID", value: session.id.rawValue.uuidString)
            }

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("detailPane.activePane")
    }
}

private struct BrowserPaneDetails: View {
    @AppStorage(WorkspacePersistenceDefaults.browserHomePageURLKey)
    private var browserHomePageURL = ""

    @State private var addressDraft = ""

    let workspaceTitle: String
    let pane: PaneLeaf
    @ObservedObject var session: BrowserSession

    let controller: BrowserPaneController

    var body: some View {
        let state = switch session.state {
            case .idle: "Idle"
            case .loading: "Loading"
            case let .failed(message): "Failed: \(message)"
        }
        let currentAddress = session.url ?? session.lastCommittedURL ?? ""
        let normalizedAddressDraft = BrowserNavigationDefaults.normalizedNavigationURLString(from: addressDraft)
        let normalizedHomePageURL = BrowserNavigationDefaults.normalizedNavigationURLString(from: browserHomePageURL)
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Pane")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Enter a URL",
                    text: $addressDraft,
                    prompt: Text(currentAddress.isEmpty ? "about:blank" : currentAddress),
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard let normalizedAddressDraft else {
                        return
                    }

                    controller.loadAddress(normalizedAddressDraft)
                }
                .onAppear {
                    syncAddressDraft(with: currentAddress)
                }
                .onChange(of: pane.id) { _, _ in
                    syncAddressDraft(with: currentAddress)
                }
                .onChange(of: session.url) { _, newValue in
                    syncAddressDraft(with: newValue ?? session.lastCommittedURL ?? "")
                }
                .onChange(of: session.lastCommittedURL) { _, newValue in
                    syncAddressDraft(with: session.url ?? newValue ?? "")
                }

                HStack {
                    Button("Go") {
                        guard let normalizedAddressDraft else {
                            return
                        }

                        controller.loadAddress(normalizedAddressDraft)
                    }
                    .disabled(normalizedAddressDraft == nil)

                    Button("Home") {
                        controller.goHome()
                    }
                    .disabled(normalizedHomePageURL == nil)

                    Spacer()
                }
            }

            HStack {
                Button("Back") {
                    controller.goBack()
                }
                .disabled(!session.canGoBack)

                Button("Forward") {
                    controller.goForward()
                }
                .disabled(!session.canGoForward)

                Button("Reload") {
                    controller.reload()
                }
            }

            Group {
                DetailValue(label: "Workspace", value: workspaceTitle)
                    .accessibilityIdentifier("detailPane.workspaceTitleValue")
                DetailValue(label: "Pane Type", value: "Browser")
                DetailValue(label: "Title", value: session.title)
                DetailValue(label: "State", value: state)
                DetailValue(label: "URL", value: session.url ?? "Blank")
                DetailValue(label: "Last Committed URL", value: session.lastCommittedURL ?? "Unavailable")
                DetailValue(label: "Can Go Back", value: session.canGoBack ? "Yes" : "No")
                DetailValue(label: "Can Go Forward", value: session.canGoForward ? "Yes" : "No")
                DetailValue(label: "Pane ID", value: pane.id.rawValue.uuidString)
                DetailValue(label: "Browser Session ID", value: session.id.rawValue.uuidString)
            }

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("detailPane.browserPane")
    }

    private func syncAddressDraft(with resolvedAddress: String) {
        guard !resolvedAddress.isEmpty else {
            if addressDraft.isEmpty {
                return
            }
            addressDraft = ""
            return
        }
        guard addressDraft != resolvedAddress else {
            return
        }

        addressDraft = resolvedAddress
    }
}

private struct UnsupportedPaneDetails: View {
    let workspaceTitle: String
    let pane: PaneLeaf

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Pane")
                .font(.title2.weight(.semibold))

            Group {
                DetailValue(label: "Workspace", value: workspaceTitle)
                    .accessibilityIdentifier("detailPane.workspaceTitleValue")
                DetailValue(label: "Pane Type", value: "Browser")
                DetailValue(label: "Status", value: "This pane uses a non-terminal content type that the current inspector does not render yet.")
                DetailValue(label: "Pane ID", value: pane.id.rawValue.uuidString)
                if let sessionID = pane.browserSessionID {
                    DetailValue(label: "Browser Session ID", value: sessionID.rawValue.uuidString)
                }
            }

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("detailPane.unsupportedPane")
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
                        : "Select a pane to inspect its shell session.",
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
            focusedTarget: $focusedTarget,
        )
    }
}
