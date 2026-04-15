/*
 WorkspacePersistenceProfile defines which persistent store configuration the
 app should use for a given runtime. It keeps production, debug, UI-test, and
 in-memory testing stores explicit so persistence behavior is intentional
 instead of being inferred from scattered ad hoc branches.
 */

import Foundation

protocol ProcessInfoReading {
	nonisolated var environment: [String: String] { get }
}

extension ProcessInfo: ProcessInfoReading {}

enum WorkspacePersistenceProfile: String, Sendable {
	case productionOnDisk = "production"
	case debugOnDisk = "debug"
	case uiTestOnDisk = "ui-test"
	case inMemory = "in-memory"

	nonisolated static let environmentKey = "GMAX_PERSISTENCE_PROFILE"
	nonisolated static let uiTestResetStateEnvironmentKey = "GMAX_UI_TEST_RESET_STATE"

	nonisolated static func appDefault(processInfo: ProcessInfoReading = ProcessInfo.processInfo) -> WorkspacePersistenceProfile {
		if let requestedProfile = processInfo.environment[environmentKey] {
			if let explicitProfile = WorkspacePersistenceProfile(rawValue: requestedProfile) {
				return explicitProfile
			}
		}

		if processInfo.environment[uiTestResetStateEnvironmentKey] == "1" {
			return .uiTestOnDisk
		}

		#if DEBUG
		return .debugOnDisk
		#else
		return .productionOnDisk
		#endif
	}

	nonisolated var usesInMemoryStore: Bool {
		self == .inMemory
	}

	nonisolated var storeFileName: String? {
		switch self {
			case .productionOnDisk:
				return "WorkspaceStore.sqlite"
			case .debugOnDisk:
				return "WorkspaceStore.debug.sqlite"
			case .uiTestOnDisk:
				return "WorkspaceStore.ui-test.sqlite"
			case .inMemory:
				return nil
		}
	}

	nonisolated var contextName: String {
		switch self {
			case .productionOnDisk:
				return "WorkspacePersistence.productionViewContext"
			case .debugOnDisk:
				return "WorkspacePersistence.debugViewContext"
			case .uiTestOnDisk:
				return "WorkspacePersistence.uiTestViewContext"
			case .inMemory:
				return "WorkspacePersistence.inMemoryViewContext"
		}
	}

	nonisolated var displayName: String {
		switch self {
			case .productionOnDisk:
				return "production on-disk workspace store"
			case .debugOnDisk:
				return "debug on-disk workspace store"
			case .uiTestOnDisk:
				return "UI-test on-disk workspace store"
			case .inMemory:
				return "in-memory workspace store"
		}
	}
}
