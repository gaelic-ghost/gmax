//
//  TerminalAppearancePreview.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
import SwiftUI

struct TerminalAppearancePreview: View {
	let appearance: TerminalAppearance

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("$ pwd")
			Text("~/Workspace/gmax")
			Text("$ swift build")
			Text("Build complete! Nerd glyphs: \u{e0b6} \u{f115} \u{f0e7}")
		}
		.font(Font(appearance.resolvedFont))
		.foregroundStyle(Color(nsColor: appearance.theme.foregroundColor))
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Color(nsColor: appearance.theme.backgroundColor))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color(nsColor: appearance.theme.cursorColor).opacity(0.35), lineWidth: 1)
		)
	}
}
