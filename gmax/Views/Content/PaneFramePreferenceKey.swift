//
//  PaneFramePreferenceKey.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct PaneFramePreferenceKey: PreferenceKey {
	static var defaultValue: [PaneID: CGRect] = [:]

	static func reduce(value: inout [PaneID: CGRect], nextValue: () -> [PaneID: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}
