//
//  GhosttyPaneHostView.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import AppKit
import OSLog

@MainActor
final class GhosttyPaneHostView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }

    var onCloseRequested: (() -> Void)?

    private let session: TerminalSession
    private var surface: GhosttySurfaceHandle?
    private var loadError: String?

    init(session: TerminalSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            createSurfaceIfNeeded()
            updateSurfaceGeometry()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceGeometry()
    }

    override func layout() {
        super.layout()
        updateSurfaceGeometry()
    }

    override func becomeFirstResponder() -> Bool {
        surface?.setFocus(true)
        session.clearBellAttention()
        return true
    }

    override func resignFirstResponder() -> Bool {
        surface?.setFocus(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        if let attributedString = insertString as? NSAttributedString {
            surface?.sendText(attributedString.string)
        } else if let string = insertString as? String {
            surface?.sendText(string)
        }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
            case #selector(insertNewline(_:)):
                surface?.sendText("\r")
            case #selector(deleteBackward(_:)):
                surface?.sendText("\u{7f}")
            case #selector(insertTab(_:)):
                surface?.sendText("\t")
            case #selector(cancelOperation(_:)):
                surface?.sendText("\u{1b}")
            case #selector(moveUp(_:)):
                surface?.sendText("\u{1b}[A")
            case #selector(moveDown(_:)):
                surface?.sendText("\u{1b}[B")
            case #selector(moveRight(_:)):
                surface?.sendText("\u{1b}[C")
            case #selector(moveLeft(_:)):
                surface?.sendText("\u{1b}[D")
            default:
                Logger.pane.debug("Ghostty pane spike ignored an AppKit text command. Selector: \(NSStringFromSelector(selector), privacy: .public)")
        }
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        surface?.mouseButton(state: 1, button: 0)
    }

    override func mouseUp(with event: NSEvent) {
        sendMousePosition(event)
        surface?.mouseButton(state: 0, button: 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        surface?.mouseButton(state: 1, button: 1)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMousePosition(event)
        surface?.mouseButton(state: 0, button: 1)
    }

    override func scrollWheel(with event: NSEvent) {
        surface?.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
    }

    func refreshSurface() {
        surface?.refresh()
    }

    private func createSurfaceIfNeeded() {
        guard surface == nil, loadError == nil else {
            return
        }

        let sessionID = session.id.rawValue.uuidString
        do {
            surface = try GhosttyRuntime.shared.makeSurface(
                nsView: self,
                launchConfiguration: session.launchConfiguration,
                fontSize: 14,
                onEvent: { [weak self] event, primary, secondary, number in
                    self?.handle(event: event, primary: primary, secondary: secondary, number: number)
                },
            )
            session.state = .running
            session.title = "Ghostty"
            Logger.pane.notice("Created a Ghostty pane spike surface for a terminal session. Session ID: \(sessionID, privacy: .public)")
        } catch {
            let message = error.localizedDescription
            loadError = message
            session.state = .exited(nil)
            Logger.pane.error("The Ghostty pane spike could not create a surface. Session ID: \(sessionID, privacy: .public). Error: \(message, privacy: .public)")
            needsDisplay = true
        }
    }

    private func handle(event: GhosttyPaneSpikeEvent, primary: String?, secondary: String?, number: Int64) {
        switch event {
            case .ready:
                break
            case .title:
                session.title = primary.flatMap { $0.isEmpty ? nil : $0 } ?? "Ghostty"
            case .pwd:
                session.currentDirectory = primary
            case .bell:
                session.recordBell()
            case .notification:
                session.recordAttentionNotification(title: primary ?? "Ghostty", body: secondary ?? "")
            case .childExited:
                session.state = .exited(Int32(clamping: number))
                session.clearShellIntegrationState()
            case .commandFinished:
                session.applyShellIntegrationEvent(.commandFinished(exitStatus: Int32(clamping: number)))
            case .closeRequested:
                onCloseRequested?()
            case .error:
                loadError = primary ?? "Ghostty pane spike reported an unknown runtime error."
                session.state = .exited(nil)
        }
    }

    private func updateSurfaceGeometry() {
        guard let surface else {
            return
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        surface.setScale(Double(scale))
        let width = max(UInt32((bounds.width * scale).rounded(.down)), 1)
        let height = max(UInt32((bounds.height * scale).rounded(.down)), 1)
        surface.setSize(width: width, height: height)
        surface.refresh()
    }

    private func sendMousePosition(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        surface?.mousePosition(x: location.x, y: bounds.height - location.y)
    }
}
