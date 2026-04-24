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
    @State private var isHovered = false
    @State private var isKeyboardRevealed = false
    @State private var isFieldFocused = false
    @State private var addressDraft = ""
    @State private var focusSelectionToken = 0
    @State private var focusRequestToken = 0

    let controller: BrowserPaneController
    @ObservedObject var session: BrowserSession

    let revealID: Int
    let isPaneFocused: Bool

    private var isExpanded: Bool {
        isHovered || isKeyboardRevealed || isFieldFocused
    }

    private var currentAddress: String {
        session.url ?? session.lastCommittedURL ?? BrowserNavigationDefaults.initialPageURLString()
    }

    private var normalizedAddressDraft: String? {
        BrowserNavigationDefaults.normalizedNavigationURLString(from: addressDraft)
    }

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)

                    BrowserOmniboxTextField(
                        text: $addressDraft,
                        placeholder: currentAddress,
                        isFocused: $isFieldFocused,
                        focusRequestToken: focusRequestToken,
                        selectAllToken: focusSelectionToken,
                        onSubmit: {
                            guard let normalizedAddressDraft else {
                                return
                            }

                            controller.loadAddress(normalizedAddressDraft)
                            isKeyboardRevealed = false
                            isFieldFocused = false
                        },
                        onCancel: {
                            syncDraft()
                            isKeyboardRevealed = false
                            isFieldFocused = false
                            Task { @MainActor in
                                controller.focusWebView()
                            }
                        },
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 12, height: 12)
                    .opacity(0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            syncDraft()
            focusRequestToken += 1
            focusSelectionToken += 1
            isKeyboardRevealed = true
        }
        .onChange(of: session.url) { _, _ in
            guard !isKeyboardRevealed else {
                return
            }

            syncDraft()
        }
        .onChange(of: session.lastCommittedURL) { _, _ in
            guard !isKeyboardRevealed else {
                return
            }

            syncDraft()
        }
        .onChange(of: isPaneFocused) { _, newValue in
            guard !newValue else {
                return
            }

            isKeyboardRevealed = false
            isFieldFocused = false
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private func syncDraft() {
        let resolvedAddress = currentAddress
        guard addressDraft != resolvedAddress else {
            return
        }

        addressDraft = resolvedAddress
    }
}

private struct BrowserOmniboxTextField: NSViewRepresentable {
    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate, NSControlTextEditingDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool

        let onSubmit: () -> Void
        let onCancel: () -> Void

        var focusRequestToken: Int = 0
        var selectAllToken: Int = 0
        var lastAppliedFocusRequestToken: Int = -1
        var lastAppliedSelectAllToken: Int = -1

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
        ) {
            _text = text
            _isFocused = isFocused
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else {
                return
            }

            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector,
        ) -> Bool {
            switch commandSelector {
                case #selector(NSResponder.insertNewline(_:)):
                    onSubmit()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    onCancel()
                    return true
                default:
                    return false
            }
        }
    }

    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool

    let focusRequestToken: Int
    let selectAllToken: Int
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            onSubmit: onSubmit,
            onCancel: onCancel,
        )
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.focusRequestToken = focusRequestToken
        context.coordinator.selectAllToken = selectAllToken

        if context.coordinator.lastAppliedFocusRequestToken != focusRequestToken {
            requestFocusIfNeeded(for: nsView, coordinator: context.coordinator)
        } else if isFocused {
            requestSelectionIfNeeded(for: nsView, coordinator: context.coordinator)
        } else if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    private func requestFocusIfNeeded(
        for nsView: NSSearchField,
        coordinator: Coordinator,
    ) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
            nsView.currentEditor()?.selectAll(nil)
            coordinator.lastAppliedFocusRequestToken = focusRequestToken
            coordinator.lastAppliedSelectAllToken = selectAllToken
        }
    }

    private func requestSelectionIfNeeded(
        for nsView: NSSearchField,
        coordinator: Coordinator,
    ) {
        guard coordinator.lastAppliedSelectAllToken != selectAllToken else {
            return
        }

        DispatchQueue.main.async {
            guard isFocused else {
                return
            }

            nsView.currentEditor()?.selectAll(nil)
            coordinator.lastAppliedSelectAllToken = selectAllToken
        }
    }
}
