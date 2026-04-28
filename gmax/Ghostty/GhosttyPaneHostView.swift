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
    var onLifecycleStateChange: ((GhosttyBackendLifecycleState) -> Void)?

    private let session: TerminalSession
    private var surface: GhosttySurfaceHandle?
    private var loadError: String?
    private var activeKeyDownEvent: NSEvent?

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
        activeKeyDownEvent = event
        defer { activeKeyDownEvent = nil }
        interpretKeyEvents([event])
    }

    override func keyUp(with event: NSEvent) {
        surface?.sendKey(action: .release, event: event)
    }

    override func insertText(_ insertString: Any) {
        if let attributedString = insertString as? NSAttributedString {
            sendInsertedText(attributedString.string)
        } else if let string = insertString as? String {
            sendInsertedText(string)
        }
    }

    override func doCommand(by selector: Selector) {
        guard let keyCode = GhosttySpecialKeyCode(selector: selector) else {
            Logger.pane.debug("Ghostty pane spike ignored an AppKit text command. Selector: \(NSStringFromSelector(selector), privacy: .public)")
            return
        }

        sendSpecialKey(keyCode)
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

        onLifecycleStateChange?(.loading)
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
            onLifecycleStateChange?(.ready)
            Logger.pane.notice("Created a Ghostty pane spike surface for a terminal session. Session ID: \(sessionID, privacy: .public)")
        } catch {
            let message = error.localizedDescription
            loadError = message
            session.state = .exited(nil)
            onLifecycleStateChange?(.failed(message))
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
                let message = primary ?? "Ghostty pane spike reported an unknown runtime error."
                loadError = message
                session.state = .exited(nil)
                onLifecycleStateChange?(.failed(message))
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

    private func sendInsertedText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        guard let activeKeyDownEvent else {
            surface?.sendText(text)
            return
        }

        let action: GhosttyKeyAction = activeKeyDownEvent.isARepeat ? .repeatPress : .press
        surface?.sendKey(action: action, event: activeKeyDownEvent, text: text)
    }

    private func sendSpecialKey(_ keyCode: GhosttySpecialKeyCode) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: keyCode.characters,
            charactersIgnoringModifiers: keyCode.characters,
            isARepeat: false,
            keyCode: keyCode.rawValue,
        ) else {
            return
        }

        surface?.sendKey(action: .press, event: event)
    }
}

private enum GhosttySpecialKeyCode: UInt16 {
    case `return` = 36
    case tab = 48
    case delete = 51
    case escape = 53
    case home = 115
    case pageUp = 116
    case forwardDelete = 117
    case end = 119
    case pageDown = 121
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126

    var characters: String {
        switch self {
            case .return:
                "\r"
            case .tab:
                "\t"
            case .delete:
                "\u{7F}"
            case .escape:
                "\u{1B}"
            default:
                ""
        }
    }

    init?(selector: Selector) {
        switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                self = .return
            case #selector(NSResponder.insertTab(_:)):
                self = .tab
            case #selector(NSResponder.deleteBackward(_:)):
                self = .delete
            case #selector(NSResponder.deleteForward(_:)):
                self = .forwardDelete
            case #selector(NSResponder.cancelOperation(_:)):
                self = .escape
            case #selector(NSResponder.moveUp(_:)):
                self = .upArrow
            case #selector(NSResponder.moveDown(_:)):
                self = .downArrow
            case #selector(NSResponder.moveRight(_:)):
                self = .rightArrow
            case #selector(NSResponder.moveLeft(_:)):
                self = .leftArrow
            case #selector(NSResponder.moveToBeginningOfLine(_:)):
                self = .home
            case #selector(NSResponder.moveToEndOfLine(_:)):
                self = .end
            case #selector(NSResponder.pageUp(_:)):
                self = .pageUp
            case #selector(NSResponder.pageDown(_:)):
                self = .pageDown
            default:
                return nil
        }
    }
}
