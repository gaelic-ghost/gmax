//
//  ContentPaneLeafView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct ContentPaneLeafView: View {
    @State private var chromeRevealID = 0

    let pane: PaneLeaf
    let controller: TerminalPaneController
    @ObservedObject var session: TerminalSession

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let onMovePaneFocus: (PaneFocusDirection) -> Void
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void

    var body: some View {
        let isFocused = focusedTarget.wrappedValue == .pane(pane.id)
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = switch session.state {
            case .idle: "Shell ready to launch"
            case .running: "Shell running"
            case let .exited(exitCode): exitCode.map { "Shell exited with status \($0)" } ?? "Shell exited"
        }
        let shellPhase: String? = switch session.shellPhase {
            case .unknown: nil
            case .atPrompt: "Shell at prompt"
            case .runningCommand: "Shell running a command"
        }
        let shellStatusDescription: String? = switch shellStatusIndicatorState {
            case .running: "Command running"
            case .finished: "Last command finished successfully"
            case .failed: "Last command failed"
            case nil: nil
        }
        let paneHostIdentity = "\(pane.id.rawValue.uuidString)-\(session.relaunchGeneration)"
        let accessibilityLabel = title.isEmpty || title == "Shell" ? "Shell pane" : "\(title) pane"
        let accessibilityValue = [
            isFocused ? "Focused" : nil,
            state,
            shellPhase,
            shellStatusDescription,
            session.currentDirectory.flatMap { $0.isEmpty ? nil : "Directory \($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: ". ")
        let paneActionsHint = "Activate to focus this pane. Additional actions are available for splitting, closing, and restarting the shell."
        let focusBackgroundStyle = isFocused ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.35))
        paneSurface(isFocused: isFocused, paneHostIdentity: paneHostIdentity)
            .focusable(interactions: .edit)
            .focused(focusedTarget, equals: .pane(pane.id))
            .background(ContentPaneFrameReporter(paneID: pane.id))
            .background(focusBackgroundStyle)
            .onChange(of: isFocused) { _, newValue in
                guard newValue else {
                    return
                }

                chromeRevealID += 1
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(paneActionsHint)
            .accessibilityIdentifier("contentPane.leaf.\(pane.id.rawValue.uuidString)")
            .accessibilityRespondsToUserInteraction(true)
            .accessibilityAddTraits(isFocused ? .isSelected : [])
            .accessibilityAction(named: Text("Split Right")) {
                onSplitRight()
            }
            .accessibilityAction(named: Text("Split Down")) {
                onSplitDown()
            }
            .accessibilityAction(named: Text("Close Pane")) {
                onClose()
            }
            .accessibilityAction(named: Text("Restart Shell")) {
                restartShell()
            }
    }

    private func paneSurface(isFocused: Bool, paneHostIdentity: String) -> some View {
        TerminalPaneView(
            controller: controller,
            session: session,
            onRestart: restartShell,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
        )
        // The pane host must stay keyed to the actual pane leaf, not just relaunches,
        // or SwiftUI can reuse a surviving sibling's coordinator after split collapse.
        .id(paneHostIdentity)
        .background(.black)
        .overlay(alignment: .top) {
            ContentPaneLeafHeader(title: session.title, revealID: chromeRevealID)
                .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if isFocused {
                    ContentPaneLeafFocusIndicator()
                }
                if let shellStatusIndicatorState {
                    ContentPaneLeafShellStatusIndicator(state: shellStatusIndicatorState)
                }
            }
            .padding([.top, .trailing], 12)
        }
        .overlay(alignment: .bottomLeading) {
            if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
                ContentPaneLeafFooter(
                    currentDirectory: currentDirectory,
                    revealID: chromeRevealID,
                )
                .padding([.leading, .bottom], 12)
            }
        }
        .overlay {
            if case let .exited(exitCode) = session.state {
                exitedSessionOverlay(exitCode: exitCode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exitedSessionOverlay(exitCode: Int32?) -> some View {
        VStack(spacing: 10) {
            Text("Shell Session Ended")
                .font(.headline.weight(.semibold))

            Text(exitCode.map {
                "The shell process exited with status \($0). Start a fresh login shell in this pane when you're ready."
            } ?? "The shell process ended unexpectedly or without a reported exit status. Start a fresh login shell in this pane when you're ready.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Restart Shell") {
                restartShell()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func restartShell() {
        guard session.state != .running else { return }

        session.prepareForRelaunch()
    }

    private var shellStatusIndicatorState: ContentPaneLeafShellStatusIndicator.Status? {
        switch session.shellPhase {
            case .runningCommand:
                return .running
            case .atPrompt:
                guard let exitStatus = session.lastCommandExitStatus else {
                    return nil
                }
                return exitStatus == 0 ? .finished : .failed
            case .unknown:
                return nil
        }
    }
}

private struct ContentPaneLeafHeader: View {
    let title: String
    let revealID: Int

    var body: some View {
        ContentPaneLeafChromeBadge(
            text: title,
            revealID: revealID,
            font: .headline,
        )
    }
}

private struct ContentPaneLeafFooter: View {
    let currentDirectory: String
    let revealID: Int

    var body: some View {
        ContentPaneLeafChromeBadge(
            text: currentDirectory,
            revealID: revealID,
            font: .caption,
            foregroundStyle: AnyShapeStyle(.secondary),
            truncationMode: .middle,
        )
    }
}

private struct ContentPaneLeafFocusIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 10, height: 10)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ContentPaneLeafShellStatusIndicator: View {
    enum Status {
        case running
        case finished
        case failed
    }

    @State private var isPulsing = false
    @State private var isFailureBlinking = false
    @State private var pulseTask: Task<Void, Never>?
    @State private var failureBlinkTask: Task<Void, Never>?

    let state: Status

    init(state: Status) {
        self.state = state
    }

    private var fillColor: Color {
        switch state {
            case .running, .finished:
                return .blue
            case .failed:
                return .red
        }
    }

    private var shouldPulse: Bool {
        state == .running
    }

    private var shouldBlinkFailure: Bool {
        state == .failed && isFailureBlinking
    }

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 10, height: 10)
            .scaleEffect(shouldPulse ? (isPulsing ? 1 : 0.78) : 1)
            .opacity(opacity)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .onAppear {
                updateAnimationState()
            }
            .onChange(of: state) { _, _ in
                updateAnimationState()
            }
            .onDisappear {
                pulseTask?.cancel()
                pulseTask = nil
                failureBlinkTask?.cancel()
                failureBlinkTask = nil
            }
            .animation(.easeInOut(duration: 0.18), value: isPulsing)
            .animation(.easeInOut(duration: 0.18), value: isFailureBlinking)
    }

    private var opacity: Double {
        if shouldPulse {
            return isPulsing ? 0.95 : 0.42
        }
        if shouldBlinkFailure {
            return isFailureBlinking ? 0.95 : 0.2
        }
        return 0.95
    }

    private func updateAnimationState() {
        pulseTask?.cancel()
        pulseTask = nil
        failureBlinkTask?.cancel()
        failureBlinkTask = nil
        isFailureBlinking = false

        if shouldPulse {
            isPulsing = true
            pulseTask = Task { @MainActor in
                while !Task.isCancelled, state == .running {
                    try? await Task.sleep(for: .seconds(0.65))
                    guard !Task.isCancelled, state == .running else {
                        break
                    }

                    isPulsing.toggle()
                }

                guard !Task.isCancelled else {
                    return
                }

                isPulsing = false
            }
        } else {
            isPulsing = false
        }

        guard state == .failed else {
            return
        }

        isFailureBlinking = true
        failureBlinkTask = Task { @MainActor in
            let endTime = ContinuousClock.now + .seconds(1.1)
            while !Task.isCancelled, ContinuousClock.now < endTime, state == .failed {
                try? await Task.sleep(for: .seconds(0.11))
                guard !Task.isCancelled, state == .failed else {
                    break
                }

                isFailureBlinking.toggle()
            }

            guard !Task.isCancelled else {
                return
            }

            isFailureBlinking = false
        }
    }
}

private struct ContentPaneLeafChromeBadge: View {
    @State private var isHovered = false
    @State private var isFocusRevealed = false
    @State private var collapseTask: Task<Void, Never>?

    let text: String
    let revealID: Int
    let font: Font
    var foregroundStyle: AnyShapeStyle = .init(.primary)
    var truncationMode: Text.TruncationMode = .tail

    private var isExpanded: Bool {
        isHovered || isFocusRevealed
    }

    var body: some View {
        Group {
            if isExpanded {
                Text(text)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)
                    .truncationMode(truncationMode)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 12, height: 12)
                    .opacity(0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: revealID) { _, _ in
            isFocusRevealed = true
            scheduleFocusCollapse()
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
        .onDisappear {
            collapseTask?.cancel()
            collapseTask = nil
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
}

private struct ContentPaneFrameReporter: View {
    let paneID: PaneID

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: ContentPaneFramePreferenceKey.self,
                value: [paneID: geometry.frame(in: .named("workspace-pane-tree"))],
            )
        }
    }
}
