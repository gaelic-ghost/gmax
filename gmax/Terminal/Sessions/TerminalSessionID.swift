import Foundation

struct TerminalSessionID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue = UUID()

	var id: UUID { rawValue }
}
