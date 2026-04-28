//
//  GhosttyRuntime.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import AppKit
import Darwin
import Foundation
import OSLog

enum GhosttyPaneSpikeEvent: Int32 {
    case ready = 1
    case title = 2
    case pwd = 3
    case bell = 4
    case notification = 5
    case childExited = 6
    case commandFinished = 7
    case closeRequested = 8
    case error = 9
}

@MainActor
final class GhosttyRuntime {
    fileprivate typealias SurfaceDestroy = @convention(c) (OpaquePointer?) -> Void
    fileprivate typealias SurfaceSetSize = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Void
    fileprivate typealias SurfaceSetScale = @convention(c) (OpaquePointer?, Double) -> Void
    fileprivate typealias SurfaceSetFocus = @convention(c) (OpaquePointer?, Bool) -> Void
    fileprivate typealias SurfaceText = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt) -> Void
    fileprivate typealias SurfaceKey = @convention(c) (
        OpaquePointer?,
        Int32,
        Int32,
        UnsafePointer<CChar>?,
        UInt32,
        UInt32,
        Bool,
    ) -> Bool
    fileprivate typealias SurfaceMousePosition = @convention(c) (OpaquePointer?, Double, Double) -> Void
    fileprivate typealias SurfaceMouseButton = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    fileprivate typealias SurfaceScroll = @convention(c) (OpaquePointer?, Double, Double) -> Void
    fileprivate typealias SurfaceRefresh = @convention(c) (OpaquePointer?) -> Void

    fileprivate struct SurfaceFunctions {
        fileprivate let destroy: SurfaceDestroy
        fileprivate let setSize: SurfaceSetSize
        fileprivate let setScale: SurfaceSetScale
        fileprivate let setFocus: SurfaceSetFocus
        fileprivate let text: SurfaceText
        fileprivate let key: SurfaceKey
        fileprivate let mousePosition: SurfaceMousePosition
        fileprivate let mouseButton: SurfaceMouseButton
        fileprivate let scroll: SurfaceScroll
        fileprivate let refresh: SurfaceRefresh
    }

    private typealias EventCallback = @convention(c) (
        UnsafeMutableRawPointer?,
        Int32,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        Int64,
    ) -> Void

    private typealias RuntimeCreate = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        EventCallback,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<OpaquePointer?>,
        UnsafeMutablePointer<CChar>,
        Int,
    ) -> Int32
    private typealias RuntimeTick = @convention(c) (OpaquePointer?) -> Void
    private typealias RuntimeDestroy = @convention(c) (OpaquePointer?) -> Void
    private typealias SurfaceCreate = @convention(c) (
        OpaquePointer?,
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        Double,
        Float,
        EventCallback,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<OpaquePointer?>,
        UnsafeMutablePointer<CChar>,
        Int,
    ) -> Int32

    static let shared = GhosttyRuntime()

    private var runtime: OpaquePointer?
    private var dlHandle: UnsafeMutableRawPointer?
    private var createSurfaceFunction: SurfaceCreate?
    private var tickFunction: RuntimeTick?
    private var destroyRuntimeFunction: RuntimeDestroy?
    private var surfaceFunctions: SurfaceFunctions?
    private var lastError: String?

    isolated deinit {
        destroyRuntimeFunction?(runtime)
        if let dlHandle {
            dlclose(dlHandle)
        }
    }

    private init() {}

    func makeSurface(
        nsView: NSView,
        launchConfiguration: TerminalLaunchConfiguration,
        fontSize: Float,
        onEvent: @escaping (GhosttyPaneSpikeEvent, String?, String?, Int64) -> Void,
    ) throws -> GhosttySurfaceHandle {
        try ensureLoaded()
        guard let runtime, let createSurfaceFunction, let surfaceFunctions else {
            throw GhosttyRuntimeError.unavailable(lastError ?? "The Ghostty spike runtime was not initialized.")
        }

        var surface: OpaquePointer?
        var error = [CChar](repeating: 0, count: 2048)
        let box = GhosttySurfaceEventBox(onEvent: onEvent)
        let boxPointer = Unmanaged.passRetained(box).toOpaque()
        let result = withOptionalCString(launchConfiguration.currentDirectory) { workingDirectory in
            launchConfiguration.executable.withCString { command in
                createSurfaceFunction(
                    runtime,
                    Unmanaged.passUnretained(nsView).toOpaque(),
                    workingDirectory,
                    command,
                    Double(nsView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2),
                    fontSize,
                    ghosttySurfaceEventCallback,
                    boxPointer,
                    &surface,
                    &error,
                    error.count,
                )
            }
        }

        guard result != 0, let surface else {
            Unmanaged<GhosttySurfaceEventBox>.fromOpaque(boxPointer).release()
            throw GhosttyRuntimeError.unavailable(errorMessage(from: error))
        }

        tickFunction?(runtime)
        return GhosttySurfaceHandle(
            surface: surface,
            eventBoxPointer: boxPointer,
            functions: surfaceFunctions,
        )
    }

    func tick() {
        tickFunction?(runtime)
    }

    fileprivate func recordRuntimeEvent(event: Int32, primaryText: String?, secondaryText: String?, number: Int64) {
        guard let event = GhosttyPaneSpikeEvent(rawValue: event) else {
            return
        }

        switch event {
            case .ready:
                Logger.pane.notice("Ghostty pane spike runtime is ready. Message: \(primaryText ?? "", privacy: .public)")
            case .error:
                Logger.pane.error("Ghostty pane spike runtime reported an error. Message: \(primaryText ?? "", privacy: .public)")
            default:
                Logger.pane.debug("Ghostty pane spike runtime event \(event.rawValue, privacy: .public). Primary: \(primaryText ?? "", privacy: .public). Secondary: \(secondaryText ?? "", privacy: .public). Number: \(number)")
        }
    }

    private func ensureLoaded() throws {
        if runtime != nil {
            return
        }

        let shimPath = resolvedShimPath()
        guard FileManager.default.fileExists(atPath: shimPath) else {
            throw GhosttyRuntimeError.unavailable(
                "The Ghostty pane spike shim was not found at \(shimPath). Run tools/ghostty-spike/build-shim.sh, or set GMAX_GHOSTTY_SHIM_PATH to the built libgmax-ghostty-shim.dylib before enabling Ghostty terminal panes.",
            )
        }
        guard let dlHandle = dlopen(shimPath, RTLD_NOW | RTLD_LOCAL) else {
            throw GhosttyRuntimeError.unavailable(String(cString: dlerror()))
        }

        self.dlHandle = dlHandle
        let createRuntime: RuntimeCreate = try load("gmax_ghostty_runtime_create", from: dlHandle)
        tickFunction = try load("gmax_ghostty_runtime_tick", from: dlHandle)
        destroyRuntimeFunction = try load("gmax_ghostty_runtime_destroy", from: dlHandle)
        createSurfaceFunction = try load("gmax_ghostty_surface_create", from: dlHandle)
        surfaceFunctions = try SurfaceFunctions(
            destroy: load("gmax_ghostty_surface_destroy", from: dlHandle),
            setSize: load("gmax_ghostty_surface_set_size", from: dlHandle),
            setScale: load("gmax_ghostty_surface_set_scale", from: dlHandle),
            setFocus: load("gmax_ghostty_surface_set_focus", from: dlHandle),
            text: load("gmax_ghostty_surface_text", from: dlHandle),
            key: load("gmax_ghostty_surface_key", from: dlHandle),
            mousePosition: load("gmax_ghostty_surface_mouse_position", from: dlHandle),
            mouseButton: load("gmax_ghostty_surface_mouse_button", from: dlHandle),
            scroll: load("gmax_ghostty_surface_scroll", from: dlHandle),
            refresh: load("gmax_ghostty_surface_refresh", from: dlHandle),
        )

        var createdRuntime: OpaquePointer?
        var error = [CChar](repeating: 0, count: 2048)
        let result = resolvedGhosttyBinaryPath().withCString { ghosttyPath in
            withOptionalCString(resolvedSparklePath()) { sparklePath in
                createRuntime(
                    ghosttyPath,
                    sparklePath,
                    ghosttyRuntimeEventCallback,
                    Unmanaged.passUnretained(self).toOpaque(),
                    &createdRuntime,
                    &error,
                    error.count,
                )
            }
        }

        guard result != 0, let createdRuntime else {
            throw GhosttyRuntimeError.unavailable(errorMessage(from: error))
        }

        runtime = createdRuntime
        Logger.pane.notice("Loaded the Ghostty pane spike runtime from \(shimPath, privacy: .public).")
    }

    private func resolvedShimPath() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["GMAX_GHOSTTY_SHIM_PATH"], !path.isEmpty {
            return NSString(string: path).expandingTildeInPath
        }

        let fileManager = FileManager.default
        let relativeShimPath = "build/GhosttyPaneSpike/libgmax-ghostty-shim.dylib"
        let searchRoots = [
            fileManager.currentDirectoryPath,
            Bundle.main.bundleURL.path,
            #filePath,
        ]

        for root in searchRoots {
            if let shimPath = firstExistingAncestorPath(named: relativeShimPath, from: root) {
                return shimPath
            }
        }

        return fileManager
            .currentDirectoryPath
            .appending("/\(relativeShimPath)")
    }

    private func firstExistingAncestorPath(named relativePath: String, from startPath: String) -> String? {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: startPath)
        if !startPath.hasSuffix("/") {
            url.deleteLastPathComponent()
        }

        while true {
            let candidate = url.appendingPathComponent(relativePath).path
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return nil
            }
            url = parent
        }
    }

    private func resolvedGhosttyBinaryPath() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["GMAX_GHOSTTY_APP_BINARY"], !path.isEmpty {
            return NSString(string: path).expandingTildeInPath
        }

        return "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    }

    private func resolvedSparklePath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["GMAX_GHOSTTY_SPARKLE_PATH"], !path.isEmpty {
            return NSString(string: path).expandingTildeInPath
        }

        let defaultPath = "/Applications/Ghostty.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
        return FileManager.default.fileExists(atPath: defaultPath) ? defaultPath : nil
    }

    private func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, symbol) else {
            throw GhosttyRuntimeError.unavailable("The Ghostty pane spike shim is missing required symbol \(symbol).")
        }

        return unsafeBitCast(pointer, to: T.self)
    }
}

@MainActor
final class GhosttySurfaceHandle {
    private let surface: OpaquePointer
    private let eventBoxPointer: UnsafeMutableRawPointer
    private let functions: GhosttyRuntime.SurfaceFunctions

    isolated deinit {
        functions.destroy(surface)
        Unmanaged<GhosttySurfaceEventBox>.fromOpaque(eventBoxPointer).release()
    }

    fileprivate init(
        surface: OpaquePointer,
        eventBoxPointer: UnsafeMutableRawPointer,
        functions: GhosttyRuntime.SurfaceFunctions,
    ) {
        self.surface = surface
        self.eventBoxPointer = eventBoxPointer
        self.functions = functions
    }

    func setSize(width: UInt32, height: UInt32) {
        functions.setSize(surface, width, height)
    }

    func setScale(_ scale: Double) {
        functions.setScale(surface, scale)
    }

    func setFocus(_ focused: Bool) {
        functions.setFocus(surface, focused)
    }

    func sendText(_ text: String) {
        text.withCString { pointer in
            functions.text(surface, pointer, UInt(strlen(pointer)))
        }
    }

    func sendKey(action: GhosttyKeyAction, event: NSEvent, text: String? = nil, composing: Bool = false) {
        let modifiers = GhosttyInputModifierFlags(event.modifierFlags)
        let unshiftedCodepoint = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        if let text, !text.isEmpty {
            text.withCString { pointer in
                _ = functions.key(
                    surface,
                    action.rawValue,
                    modifiers.rawValue,
                    pointer,
                    UInt32(event.keyCode),
                    unshiftedCodepoint,
                    composing,
                )
            }
        } else {
            _ = functions.key(
                surface,
                action.rawValue,
                modifiers.rawValue,
                nil,
                UInt32(event.keyCode),
                unshiftedCodepoint,
                composing,
            )
        }
    }

    func mousePosition(x: Double, y: Double) {
        functions.mousePosition(surface, x, y)
    }

    func mouseButton(state: Int32, button: Int32) {
        functions.mouseButton(surface, state, button)
    }

    func scroll(deltaX: Double, deltaY: Double) {
        functions.scroll(surface, deltaX, deltaY)
    }

    func refresh() {
        functions.refresh(surface)
    }
}

enum GhosttyKeyAction: Int32 {
    case release = 0
    case press = 1
    case repeatPress = 2
}

struct GhosttyInputModifierFlags {
    let rawValue: Int32

    init(_ flags: NSEvent.ModifierFlags) {
        var rawValue: Int32 = 0
        if flags.contains(.shift) {
            rawValue |= 1 << 0
        }
        if flags.contains(.control) {
            rawValue |= 1 << 1
        }
        if flags.contains(.option) {
            rawValue |= 1 << 2
        }
        if flags.contains(.command) {
            rawValue |= 1 << 3
        }
        if flags.contains(.capsLock) {
            rawValue |= 1 << 4
        }

        self.rawValue = rawValue
    }
}

private final class GhosttySurfaceEventBox {
    let onEvent: (GhosttyPaneSpikeEvent, String?, String?, Int64) -> Void

    init(onEvent: @escaping (GhosttyPaneSpikeEvent, String?, String?, Int64) -> Void) {
        self.onEvent = onEvent
    }
}

enum GhosttyRuntimeError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
            case let .unavailable(message): message
        }
    }
}

private let ghosttyRuntimeEventCallback: @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    Int64,
) -> Void = { userdata, event, primary, secondary, number in
    guard let userdata else {
        return
    }

    let userdataAddress = UInt(bitPattern: userdata)
    let primaryText = primary.map { String(cString: $0) }
    let secondaryText = secondary.map { String(cString: $0) }
    Task { @MainActor in
        guard let userdata = UnsafeMutableRawPointer(bitPattern: userdataAddress) else {
            return
        }

        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
        runtime.recordRuntimeEvent(event: event, primaryText: primaryText, secondaryText: secondaryText, number: number)
    }
}

private let ghosttySurfaceEventCallback: @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    Int64,
) -> Void = { userdata, event, primary, secondary, number in
    guard let userdata, let event = GhosttyPaneSpikeEvent(rawValue: event) else {
        return
    }

    let userdataAddress = UInt(bitPattern: userdata)
    let primaryText = primary.map { String(cString: $0) }
    let secondaryText = secondary.map { String(cString: $0) }
    Task { @MainActor in
        guard let userdata = UnsafeMutableRawPointer(bitPattern: userdataAddress) else {
            return
        }

        let box = Unmanaged<GhosttySurfaceEventBox>.fromOpaque(userdata).takeUnretainedValue()
        box.onEvent(event, primaryText, secondaryText, number)
    }
}

private func withOptionalCString<T>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
    guard let string, !string.isEmpty else {
        return body(nil)
    }

    return string.withCString(body)
}

private func errorMessage(from buffer: [CChar]) -> String {
    buffer.withUnsafeBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else {
            return "The Ghostty pane spike returned an empty error buffer."
        }

        return String(cString: baseAddress)
    }
}
