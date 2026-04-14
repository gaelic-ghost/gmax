//
//  PaneTreeMutationTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
import Testing
@testable import gmax

struct PaneTreeMutationTests {
	@Test func splitLeafReplacesLeafWithExpectedSplit() throws {
		let originalPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		var root = PaneNode.leaf(originalPane)

		let didSplit = root.split(
			paneID: originalPane.id,
			direction: .right,
			newPane: insertedPane,
			initialFraction: 0.4
		)

		#expect(didSplit)
		let split = try #require(extractSplit(from: root))
		#expect(split.axis == .horizontal)
		#expect(split.fraction == 0.4)
		#expect(extractLeaf(from: split.first)?.id == originalPane.id)
		#expect(extractLeaf(from: split.second)?.id == insertedPane.id)
		#expect(root.paneCount() == 2)
	}

	@Test func splitNestedLeafRewritesOnlyTheTargetBranch() throws {
		let leftPane = PaneLeaf()
		let targetPane = PaneLeaf()
		let insertedPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .leaf(targetPane)
			)
		)

		let didSplit = root.split(
			paneID: targetPane.id,
			direction: .down,
			newPane: insertedPane
		)

		#expect(didSplit)
		let outerSplit = try #require(extractSplit(from: root))
		#expect(outerSplit.axis == .horizontal)
		#expect(extractLeaf(from: outerSplit.first)?.id == leftPane.id)

		let nestedSplit = try #require(extractSplit(from: outerSplit.second))
		#expect(nestedSplit.axis == .vertical)
		#expect(extractLeaf(from: nestedSplit.first)?.id == targetPane.id)
		#expect(extractLeaf(from: nestedSplit.second)?.id == insertedPane.id)
		#expect(root.leaves().map(\.id) == [leftPane.id, targetPane.id, insertedPane.id])
	}

	@Test func removePaneCollapsesTheParentToTheSurvivingSibling() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .leaf(rightPane)
			)
		)

		let result = root.removePane(id: rightPane.id)

		let collapsedNode = try #require(extractCollapsedNode(from: result))
		#expect(extractLeaf(from: collapsedNode)?.id == leftPane.id)
		#expect(extractLeaf(from: root)?.id == leftPane.id)
		#expect(root.paneCount() == 1)
	}

	@Test func removeNestedPaneCollapsesOnlyTheNestedBranch() throws {
		let leftPane = PaneLeaf()
		let topRightPane = PaneLeaf()
		let bottomRightPane = PaneLeaf()
		var root = PaneNode.split(
			PaneSplit(
				axis: .horizontal,
				fraction: 0.5,
				first: .leaf(leftPane),
				second: .split(
					PaneSplit(
						axis: .vertical,
						fraction: 0.5,
						first: .leaf(topRightPane),
						second: .leaf(bottomRightPane)
					)
				)
			)
		)

		let result = root.removePane(id: topRightPane.id)

		_ = try #require(extractCollapsedNode(from: result))
		let outerSplit = try #require(extractSplit(from: root))
		#expect(extractLeaf(from: outerSplit.first)?.id == leftPane.id)
		#expect(extractLeaf(from: outerSplit.second)?.id == bottomRightPane.id)
		#expect(root.leaves().map(\.id) == [leftPane.id, bottomRightPane.id])
	}

	@Test func updateSplitFractionOnlyMutatesTheMatchingSplit() throws {
		let leftPane = PaneLeaf()
		let topRightPane = PaneLeaf()
		let bottomRightPane = PaneLeaf()
		let nestedSplit = PaneSplit(
			axis: .vertical,
			fraction: 0.3,
			first: .leaf(topRightPane),
			second: .leaf(bottomRightPane)
		)
		let outerSplit = PaneSplit(
			axis: .horizontal,
			fraction: 0.6,
			first: .leaf(leftPane),
			second: .split(nestedSplit)
		)
		var root = PaneNode.split(outerSplit)

		let didUpdate = root.updateSplitFraction(splitID: nestedSplit.id, fraction: 0.7)

		#expect(didUpdate)
		let resolvedOuterSplit = try #require(extractSplit(from: root))
		#expect(resolvedOuterSplit.fraction == 0.6)
		let resolvedNestedSplit = try #require(extractSplit(from: resolvedOuterSplit.second))
		#expect(resolvedNestedSplit.fraction == 0.7)
	}
}

private func extractLeaf(from node: PaneNode) -> PaneLeaf? {
	guard case .leaf(let leaf) = node else {
		return nil
	}
	return leaf
}

private func extractSplit(from node: PaneNode) -> PaneSplit? {
	guard case .split(let split) = node else {
		return nil
	}
	return split
}

private func extractCollapsedNode(from result: PaneRemovalResult?) -> PaneNode? {
	guard case .collapsedTo(let node) = result else {
		return nil
	}
	return node
}
