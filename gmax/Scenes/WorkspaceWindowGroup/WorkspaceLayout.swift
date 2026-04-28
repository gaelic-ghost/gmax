import Foundation
import SwiftUI

struct WorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()

    var id: UUID { rawValue }
}

struct PaneID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()

    var id: UUID { rawValue }
}

struct BrowserSessionID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()

    var id: UUID { rawValue }
}

struct SplitID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()

    var id: UUID { rawValue }
}

enum SplitDirection {
    case right
    case down
}

enum PaneFocusDirection {
    case next
    case previous
    case left
    case right
    case up
    case down
}

struct Workspace: Identifiable, Hashable, Codable {
    var id = WorkspaceID()
    var title: String
    var root: PaneNode? = nil

    var paneLeaves: [PaneLeaf] {
        root?.leaves() ?? []
    }

    var paneCount: Int {
        paneLeaves.count
    }
}

indirect enum PaneNode: Hashable, Codable {
    case leaf(PaneLeaf)
    case split(PaneSplit)
}

enum PaneContent: Hashable, Codable {
    case terminal(TerminalSessionID)
    case browser(BrowserSessionID)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case terminalBackendKind
    }

    var id = PaneID()
    var content: PaneContent = .terminal(TerminalSessionID())
    var terminalBackendKind: TerminalBackendKind?

    nonisolated var terminalSessionID: TerminalSessionID? {
        guard case let .terminal(sessionID) = content else {
            return nil
        }

        return sessionID
    }

    nonisolated var browserSessionID: BrowserSessionID? {
        guard case let .browser(sessionID) = content else {
            return nil
        }

        return sessionID
    }

    nonisolated var resolvedTerminalBackendKind: TerminalBackendKind {
        terminalBackendKind ?? .swiftTerm
    }

    nonisolated init(
        id: PaneID = PaneID(),
        content: PaneContent = .terminal(TerminalSessionID()),
        terminalBackendKind: TerminalBackendKind? = nil,
    ) {
        self.id = id
        self.content = content
        switch content {
            case .terminal:
                self.terminalBackendKind = terminalBackendKind ?? .selectedForNewSession
            case .browser:
                self.terminalBackendKind = nil
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PaneID.self, forKey: .id)
        content = try container.decode(PaneContent.self, forKey: .content)
        switch content {
            case .terminal:
                terminalBackendKind = try container.decodeIfPresent(TerminalBackendKind.self, forKey: .terminalBackendKind)
                    ?? .swiftTerm
            case .browser:
                terminalBackendKind = nil
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        if terminalSessionID != nil {
            try container.encode(resolvedTerminalBackendKind, forKey: .terminalBackendKind)
        }
    }
}

struct PaneSplit: Hashable, Codable {
    enum Axis: String, Hashable, Codable {
        case horizontal
        case vertical
    }

    var id = SplitID()
    var axis: Axis
    var fraction: CGFloat
    var first: PaneNode
    var second: PaneNode
}

extension PaneNode {
    nonisolated func leaves() -> [PaneLeaf] {
        switch self {
            case let .leaf(leaf):
                [leaf]
            case let .split(split):
                split.first.leaves() + split.second.leaves()
        }
    }

    nonisolated func findPane(id: PaneID) -> PaneLeaf? {
        switch self {
            case let .leaf(leaf):
                leaf.id == id ? leaf : nil
            case let .split(split):
                split.first.findPane(id: id) ?? split.second.findPane(id: id)
        }
    }

    nonisolated func firstLeaf() -> PaneLeaf? {
        switch self {
            case let .leaf(leaf):
                leaf
            case let .split(split):
                split.first.firstLeaf() ?? split.second.firstLeaf()
        }
    }

    mutating func split(
        paneID: PaneID,
        direction: SplitDirection,
        newPane: PaneLeaf,
        initialFraction: CGFloat = 0.5,
    ) -> Bool {
        switch self {
            case let .leaf(leaf):
                guard leaf.id == paneID else {
                    return false
                }

                let axis: PaneSplit.Axis = switch direction {
                    case .right: .horizontal
                    case .down: .vertical
                }

                self = .split(
                    PaneSplit(
                        axis: axis,
                        fraction: initialFraction,
                        first: .leaf(leaf),
                        second: .leaf(newPane),
                    ),
                )
                return true

            case var .split(split):
                if split.first.split(
                    paneID: paneID,
                    direction: direction,
                    newPane: newPane,
                    initialFraction: initialFraction,
                ) {
                    self = .split(split)
                    return true
                }

                if split.second.split(
                    paneID: paneID,
                    direction: direction,
                    newPane: newPane,
                    initialFraction: initialFraction,
                ) {
                    self = .split(split)
                    return true
                }

                return false
        }
    }

    nonisolated func removingPane(id: PaneID) -> PaneNode? {
        switch self {
            case let .leaf(leaf):
                return leaf.id == id ? nil : self

            case let .split(split):
                let first = split.first.removingPane(id: id)
                let second = split.second.removingPane(id: id)

                switch (first, second) {
                    case (nil, nil):
                        return nil
                    case (let remaining?, nil):
                        return remaining
                    case (nil, let remaining?):
                        return remaining
                    case let (first?, second?):
                        return .split(
                            PaneSplit(
                                id: split.id,
                                axis: split.axis,
                                fraction: split.fraction,
                                first: first,
                                second: second,
                            ),
                        )
                }
        }
    }

    mutating func updateSplitFraction(splitID: SplitID, fraction: CGFloat) -> Bool {
        switch self {
            case .leaf:
                return false

            case var .split(split):
                if split.id == splitID {
                    split.fraction = fraction
                    self = .split(split)
                    return true
                }

                if split.first.updateSplitFraction(splitID: splitID, fraction: fraction) {
                    self = .split(split)
                    return true
                }

                if split.second.updateSplitFraction(splitID: splitID, fraction: fraction) {
                    self = .split(split)
                    return true
                }

                return false
        }
    }
}
