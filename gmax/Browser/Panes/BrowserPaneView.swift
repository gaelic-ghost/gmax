//
//  BrowserPaneView.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import AppKit
import SwiftUI

struct BrowserPaneView: NSViewRepresentable {
    @Environment(\.openURL) private var openURL

    let controller: BrowserPaneController
    let session: BrowserSession
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void
    let omniboxRevealID: Int
    let isPaneFocused: Bool

    private var accessibilitySnapshot: BrowserAccessibilitySnapshot {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = if trimmedTitle.isEmpty || trimmedTitle == "Browser" {
            "Browser pane"
        } else {
            "\(trimmedTitle) browser pane"
        }

        var valueParts: [String] = []
        switch session.state {
            case .idle:
                valueParts.append("Browser ready")
            case .loading:
                valueParts.append("Browser loading")
            case let .failed(message):
                valueParts.append(message)
        }
        if let currentURL = session.url, !currentURL.isEmpty {
            valueParts.append("URL \(currentURL)")
        } else if let lastCommittedURL = session.lastCommittedURL, !lastCommittedURL.isEmpty {
            valueParts.append("Last committed URL \(lastCommittedURL)")
        }

        return BrowserAccessibilitySnapshot(
            label: label,
            value: valueParts.joined(separator: ". "),
            help: "This browser lives inside a workspace pane. Use the available accessibility actions to reload, split, or close the pane.",
        )
    }

    static func dismantleNSView(_ nsView: BrowserPaneHostView, coordinator: Coordinator) {
        coordinator.dismantle(hostingView: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            openExternalURL: { url in
                openURL(url)
            },
        )
    }

    func makeNSView(context: Context) -> BrowserPaneHostView {
        let hostingView = context.coordinator.makeHostingView()
        hostingView.updateAccessibility(
            snapshot: accessibilitySnapshot,
            onReload: controller.reload,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
        )
        return hostingView
    }

    func updateNSView(_ nsView: BrowserPaneHostView, context: Context) {
        context.coordinator.update(hostingView: nsView)
        nsView.updateAccessibility(
            snapshot: accessibilitySnapshot,
            onReload: controller.reload,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
        )
    }
}

struct BrowserPaneChromeView: View {
    let pane: PaneLeaf
    let controller: BrowserPaneController
    @ObservedObject var session: BrowserSession

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void
    let omniboxRevealID: Int

    var body: some View {
        let isFocused = focusedTarget.wrappedValue == .pane(pane.id)
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = switch session.state {
            case .idle: "Browser ready"
            case .loading: "Browser loading"
            case let .failed(message): message
        }
        let accessibilityLabel = title.isEmpty || title == "Browser" ? "Browser pane" : "\(title) browser pane"
        let accessibilityValue = [
            isFocused ? "Focused" : nil,
            state,
            session.url.flatMap { $0.isEmpty ? nil : "URL \($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: ". ")
        let focusBackgroundStyle = isFocused ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.35))

        BrowserPaneView(
            controller: controller,
            session: session,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
            omniboxRevealID: omniboxRevealID,
            isPaneFocused: isFocused,
        )
        .overlay(alignment: .top) {
            BrowserPaneOmniboxOverlay(
                controller: controller,
                session: session,
                revealID: omniboxRevealID,
                isPaneFocused: isFocused,
            )
            .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) {
            if isFocused {
                BrowserPaneFocusIndicator()
                    .padding([.top, .trailing], 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ContentPaneFramePreferenceKey.self,
                    value: [pane.id: geometry.frame(in: .named("workspace-pane-tree"))],
                )
            }
        }
        .background(focusBackgroundStyle)
        .contentShape(Rectangle())
        .focusable(interactions: .edit)
        .focused(focusedTarget, equals: .pane(pane.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("contentPane.browserLeaf.\(pane.id.rawValue.uuidString)")
        .accessibilityAction(named: Text("Split Right")) {
            onSplitRight()
        }
        .accessibilityAction(named: Text("Split Down")) {
            onSplitDown()
        }
        .accessibilityAction(named: Text("Close Pane")) {
            onClose()
        }
    }
}

private struct BrowserPaneFocusIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 10, height: 10)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BrowserPaneOmniboxOverlay: View {
    @FocusState private var isFieldFocused: Bool
    @State private var isHovered = false
    @State private var isFocusRevealed = false
    @State private var isEditing = false
    @State private var addressDraft = ""
    @State private var textSelection: TextSelection?
    @State private var focusRequestToken = 0
    @State private var collapseTask: Task<Void, Never>?

    let controller: BrowserPaneController
    @ObservedObject var session: BrowserSession

    let revealID: Int
    let isPaneFocused: Bool

    private var isPreviewExpanded: Bool {
        isHovered || isFocusRevealed || isEditing || isFieldFocused
    }

    private var isEditingExpanded: Bool {
        isEditing
    }

    private var currentAddress: String {
        session.url ?? session.lastCommittedURL ?? BrowserNavigationDefaults.initialPageURLString()
    }

    private var normalizedAddressDraft: String? {
        BrowserNavigationDefaults.normalizedNavigationURLString(from: addressDraft)
    }

    private var previewText: String {
        let resolvedAddress = currentAddress
        guard let url = URL(string: resolvedAddress) else {
            return resolvedAddress
        }

        if let host = url.host(), !host.isEmpty {
            return host
        }

        if let scheme = url.scheme, scheme == "about" || scheme == "file" {
            return resolvedAddress
        }

        return resolvedAddress
    }

    var body: some View {
        Group {
            if isPreviewExpanded {
                if isEditingExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)

                        TextField("", text: $addressDraft, selection: $textSelection, prompt: Text(currentAddress))
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                            .focused($isFieldFocused)
                            .accessibilityIdentifier("browserPane.omniboxField")
                            .onSubmit {
                                guard let normalizedAddressDraft else {
                                    return
                                }

                                controller.loadAddress(normalizedAddressDraft)
                                endEditing(restorePreview: false, refocusWebView: false)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)

                        Text(previewText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 12, height: 12)
                    .opacity(0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard isPreviewExpanded, !isEditingExpanded else {
                return
            }

            beginKeyboardEditing(selectAll: true)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            syncDraft()
        }
        .onChange(of: revealID) { _, _ in
            guard isPaneFocused else {
                return
            }

            beginKeyboardEditing(selectAll: true)
        }
        .onChange(of: session.url) { _, _ in
            guard !isEditing else {
                return
            }

            syncDraft()
        }
        .onChange(of: session.lastCommittedURL) { _, _ in
            guard !isEditing else {
                return
            }

            syncDraft()
        }
        .onChange(of: isPaneFocused) { _, newValue in
            guard newValue else {
                if !(isEditing || isFieldFocused) {
                    isFocusRevealed = false
                    collapseTask?.cancel()
                    collapseTask = nil
                }
                return
            }
            guard !isEditingExpanded else {
                return
            }

            syncDraft()
            isFocusRevealed = true
            scheduleFocusCollapse()
        }
        .onChange(of: isFieldFocused) { _, newValue in
            if newValue {
                collapseTask?.cancel()
                collapseTask = nil
                return
            }

            guard isEditing else {
                return
            }

            endEditing(restorePreview: isPaneFocused, refocusWebView: false)
        }
        .onChange(of: focusRequestToken) { _, _ in
            guard isEditing else {
                return
            }

            Task { @MainActor in
                await Task.yield()
                guard isEditing else {
                    return
                }

                isFieldFocused = true
                textSelection = TextSelection(range: addressDraft.startIndex..<addressDraft.endIndex)
            }
        }
        .onExitCommand {
            guard isEditing else {
                return
            }

            syncDraft()
            endEditing(restorePreview: isPaneFocused, refocusWebView: true)
        }
        .animation(.easeInOut(duration: 0.18), value: isPreviewExpanded)
        .onDisappear {
            collapseTask?.cancel()
            collapseTask = nil
        }
    }

    private func syncDraft() {
        let resolvedAddress = currentAddress
        guard addressDraft != resolvedAddress else {
            return
        }

        addressDraft = resolvedAddress
    }

    private func beginKeyboardEditing(selectAll: Bool) {
        syncDraft()
        collapseTask?.cancel()
        collapseTask = nil
        isFocusRevealed = false
        isEditing = true
        focusRequestToken += 1
        if selectAll {
            textSelection = TextSelection(range: addressDraft.startIndex..<addressDraft.endIndex)
        }
    }

    private func scheduleFocusCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            isFocusRevealed = false
        }
    }

    private func endEditing(restorePreview: Bool, refocusWebView: Bool) {
        isEditing = false
        isFieldFocused = false
        textSelection = nil

        if restorePreview {
            isFocusRevealed = true
            scheduleFocusCollapse()
        } else {
            isFocusRevealed = false
        }

        if refocusWebView {
            Task { @MainActor in
                controller.focusWebView()
            }
        }
    }
}
