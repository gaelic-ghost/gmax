import Darwin
import Foundation

typealias GhosttySpikeEventCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    Int64,
) -> Void

typealias GhosttySpikeRuntimeCreate = @convention(c) (
    UnsafePointer<CChar>,
    UnsafePointer<CChar>?,
    GhosttySpikeEventCallback,
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<OpaquePointer?>,
    UnsafeMutablePointer<CChar>,
    Int,
) -> Int32

typealias GhosttySpikeRuntimeDestroy = @convention(c) (OpaquePointer?) -> Void

func expandedPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

func requiredSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T {
    guard let symbol = dlsym(handle, name) else {
        fputs("The Ghostty pane spike smoke test could not find required shim symbol \(name).\n", stderr)
        exit(1)
    }

    return unsafeBitCast(symbol, to: T.self)
}

let environment = ProcessInfo.processInfo.environment
let shimPath = expandedPath(
    environment["GMAX_GHOSTTY_SHIM_PATH"]
        ?? FileManager.default.currentDirectoryPath.appending("/build/GhosttyPaneSpike/libgmax-ghostty-shim.dylib"),
)
let ghosttyPath = expandedPath(
    environment["GMAX_GHOSTTY_APP_BINARY"]
        ?? "/Applications/Ghostty.app/Contents/MacOS/ghostty",
)
let sparklePath = environment["GMAX_GHOSTTY_SPARKLE_PATH"]
    .map(expandedPath(_:))
    ?? "/Applications/Ghostty.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

guard let handle = dlopen(shimPath, RTLD_NOW | RTLD_LOCAL) else {
    fputs("The Ghostty pane spike smoke test could not load \(shimPath): \(String(cString: dlerror()))\n", stderr)
    exit(1)
}

let createRuntime: GhosttySpikeRuntimeCreate = requiredSymbol("gmax_ghostty_runtime_create", from: handle)
let destroyRuntime: GhosttySpikeRuntimeDestroy = requiredSymbol("gmax_ghostty_runtime_destroy", from: handle)
let callback: GhosttySpikeEventCallback = { _, event, primary, secondary, number in
    let primaryText = primary.map { String(cString: $0) } ?? ""
    let secondaryText = secondary.map { String(cString: $0) } ?? ""
    print("event=\(event) number=\(number) primary=\(primaryText) secondary=\(secondaryText)")
}

var runtime: OpaquePointer?
var error = [CChar](repeating: 0, count: 2048)
let result = ghosttyPath.withCString { ghosttyPointer in
    sparklePath.withCString { sparklePointer in
        createRuntime(
            ghosttyPointer,
            sparklePointer,
            callback,
            nil,
            &runtime,
            &error,
            error.count,
        )
    }
}

guard result != 0 else {
    error.withUnsafeBufferPointer { pointer in
        let message = pointer.baseAddress.map { String(cString: $0) } ?? "the Ghostty shim did not provide an error message"
        fputs("The Ghostty pane spike smoke test could not create the runtime: \(message)\n", stderr)
    }
    exit(1)
}

destroyRuntime(runtime)
print("Ghostty pane spike runtime smoke test passed.")
