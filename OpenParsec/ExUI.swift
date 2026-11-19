import SwiftUI

// MARK: - Surfaces

extension View {
	/// Content cards stay out of the glass layer (glass is for controls), just a continuous rounded fill.
	func card(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
		background {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(Color(.secondarySystemGroupedBackground))
				.overlay {
					if let tint = tint {
						RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.16))
					}
				}
		}
	}
}

// MARK: - Avatar

/// Parsec account avatar, with the user's initial while it loads or when there is none.
struct Avatar: View {
	var userID: Int
	var name: String
	var size: CGFloat = 48

	private var url: URL? {
		guard userID > 0 else { return nil }
		let px = Int(size) * 3
		return URL(string: "https://parsecusercontent.com/cors-resize-image/w=\(px),h=\(px),fit=crop,background=white,q=90,f=jpeg/avatars/\(userID)/avatar")
	}

	var body: some View {
		AsyncImage(url: url) { phase in
			if let image = phase.image {
				image.resizable().scaledToFill()
			} else {
				ZStack {
					Color.accentColor.opacity(0.22)
					Text(name.prefix(1).uppercased())
						.font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.frame(width: size, height: size)
		.clipShape(.rect(cornerRadius: size * 0.3, style: .continuous))
		.accessibilityHidden(true)
	}
}

// MARK: - Status overlay

/// Full-screen state shown while connecting or reconnecting: a symbol, what is happening, and a way out.
struct StatusOverlay<Actions: View>: View {
	var symbol: String
	var animating: Bool = true
	var title: String
	var message: String?
	var showLog: Bool = false
	/// Scrim over a held stream frame; the main screen uses a blur instead.
	var overStream: Bool = false
	@ViewBuilder var actions: Actions

	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: symbol)
				.font(.system(size: 48, weight: .medium))
				.symbolRenderingMode(.hierarchical)
				.symbolEffect(.pulse, options: .repeat(.continuous), isActive: animating)
				.contentTransition(.symbolEffect(.replace))
				.frame(height: 60)
				.accessibilityHidden(true)
			VStack(spacing: 6) {
				Text(title)
					.font(.title3.weight(.semibold))
				if let message = message {
					Text(message)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.contentTransition(.opacity)
				}
			}
			.multilineTextAlignment(.center)
			actions
				.buttonStyle(.glass)
				.controlSize(.large)
			if showLog {
				ConnectionLogPanel()
			}
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background {
			if overStream {
				Color.black.opacity(0.6).ignoresSafeArea()
			} else {
				Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.35)).ignoresSafeArea()
			}
		}
		.foregroundStyle(.white)
		.environment(\.colorScheme, .dark)
	}
}

struct ConnectionLogPanel: View {
	@ObservedObject var log = ConnectionLog.shared

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(Array(log.lines.suffix(14).enumerated()), id: \.offset) { _, line in
				Text(line)
					.font(.system(size: 10, design: .monospaced))
					.foregroundStyle(.white.opacity(0.8))
					.lineLimit(2)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(12)
		.frame(maxWidth: 640)
		.background(.black.opacity(0.45), in: .rect(cornerRadius: 14, style: .continuous))
	}
}

// MARK: - Flow layout

/// Lays children out in rows, wrapping when a row is full. Used for the stream stats readout.
struct FlowLayout: Layout {
	var spacing: CGFloat = 12
	var lineSpacing: CGFloat = 4

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		arrange(subviews, in: proposal.width ?? .infinity).size
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let rows = arrange(subviews, in: bounds.width).rows
		var y = bounds.minY
		for row in rows {
			// centre each row
			var x = bounds.minX + (bounds.width - row.width) / 2
			for i in row.items {
				let size = subviews[i].sizeThatFits(.unspecified)
				subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
				x += size.width + spacing
			}
			y += row.height + lineSpacing
		}
	}

	private struct Row {
		var items: [Int] = []
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func arrange(_ subviews: Subviews, in maxWidth: CGFloat) -> (rows: [Row], size: CGSize) {
		var rows: [Row] = []
		var row = Row()
		for i in subviews.indices {
			let size = subviews[i].sizeThatFits(.unspecified)
			let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
			if needed > maxWidth, !row.items.isEmpty {
				rows.append(row)
				row = Row(items: [i], width: size.width, height: size.height)
			} else {
				row.items.append(i)
				row.width = needed
				row.height = max(row.height, size.height)
			}
		}
		if !row.items.isEmpty { rows.append(row) }
		let width = rows.map(\.width).max() ?? 0
		let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
		return (rows, CGSize(width: width, height: height))
	}
}

// MARK: - Reserved space

/// Space that custom (non-system) overlays must keep clear of: the safe area, and on iPhone Duo
/// the camera occlusions (outer camera, inner camera while active) and the folding region.
struct DuoReservedSpace: Equatable {
	/// Safe area of the reading view, for overlays inside a full-bleed container.
	var safeArea = EdgeInsets()
	/// Union of the active occlusion margins, to pad edge-pinned controls.
	var occlusion = EdgeInsets()
	/// Frame of an active fold, in the reading view's local space.
	var fold: CGRect?

	static let none = DuoReservedSpace()

	/// Max height for something hanging from `top`, so it stops short of a horizontal fold.
	func heightAboveFold(from top: CGFloat) -> CGFloat? {
		guard let f = fold, f.width > f.height, f.minY > top else { return nil }
		return f.minY - top
	}
}

private struct DuoReservedSpaceReader: ViewModifier {
	@Binding var space: DuoReservedSpace

	func body(content: Content) -> some View {
		content.background(GeometryReader { proxy in
			let value = Self.read(proxy)
			Color.clear
				.onAppear { space = value }
				.onChange(of: value) { _, v in space = v }
		})
	}

	static func read(_ proxy: GeometryProxy) -> DuoReservedSpace {
		var out = DuoReservedSpace()
		out.safeArea = proxy.safeAreaInsets
		if #available(iOS 27.1, *) {
			for r in proxy.reservedRegions(kind: .occlusion) where r.isActive {
				out.occlusion.top = max(out.occlusion.top, r.margins.top)
				out.occlusion.leading = max(out.occlusion.leading, r.margins.leading)
				out.occlusion.bottom = max(out.occlusion.bottom, r.margins.bottom)
				out.occlusion.trailing = max(out.occlusion.trailing, r.margins.trailing)
			}
			out.fold = proxy.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
		}
		return out
	}
}

extension View {
	/// Reads the safe area and iPhone Duo reserved regions for this view's frame.
	func readDuoReservedSpace(_ space: Binding<DuoReservedSpace>) -> some View {
		modifier(DuoReservedSpaceReader(space: space))
	}
}
