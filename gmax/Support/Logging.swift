import OSLog

extension Logger {
    nonisolated static let app = Logger(subsystem: "com.gaelic-ghost.gmax", category: "app")
    nonisolated static let workspace = Logger(subsystem: "com.gaelic-ghost.gmax", category: "workspace")
    nonisolated static let pane = Logger(subsystem: "com.gaelic-ghost.gmax", category: "pane")
    nonisolated static let persistence = Logger(subsystem: "com.gaelic-ghost.gmax", category: "persistence")
    nonisolated static let diagnostics = Logger(subsystem: "com.gaelic-ghost.gmax", category: "diagnostics")
}
