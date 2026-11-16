import SwiftUI

/**
 * Category Title
 *
 * Displays a title before the start of a list.
 */
struct CatTitle: View {
	var text: String

	init(_ text: String) {
		self.text = text
	}

	var body: some View {
		HStack {
			Text(text)
			Spacer()
		}
		.padding(.horizontal)
		.padding(.vertical, 4)
	}
}

/**
 * Category List
 *
 * Displays a list of items. Acts as a container.
 * Use of `CatItem`s is recommended.
 */
struct CatList<Content: View>: View {
	var content: () -> Content

	init(@ViewBuilder content: @escaping () -> Content) {
		self.content = content
	}

	var body: some View {
		VStack(content: content)
			.padding(.vertical, 10)
			.background(Rectangle().fill(Color("BackgroundTab")).cornerRadius(10))
			.padding(.horizontal)
	}
}

/**
 * Category Item
 *
 * Displays a new item with a label in a list.
 * Should be used within `CatList`s.
 */
struct CatItem<Content: View>: View {
	var title: String
	var content: () -> Content

	init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
		self.title = title
		self.content = content
	}

	var body: some View {
		HStack {
			Text(title)
				.lineLimit(1)
			Spacer()
			content()
		}
		.padding(.horizontal)
	}
}

struct CatSlider: View {
	var title: String
	var value: Binding<Double>
	var range: ClosedRange<Double>
	var step: Double

	init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
		self.title = title
		self.value = value
		self.range = range
		self.step = step
	}

	var body: some View {
		VStack(spacing: 4) {
			HStack {
				Text(title)
					.lineLimit(1)
				Spacer()
				Text(String(format: "%.1f", value.wrappedValue))
			}
			Slider(value: value, in: range, step: step)
		}
		.padding(.horizontal)
	}
}

struct ConnectionLogPanel: View {
	@ObservedObject var log = ConnectionLog.shared

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(Array(log.lines.suffix(14).enumerated()), id: \.offset) { _, line in
				Text(line)
					.font(.system(size: 10, design: .monospaced))
					.foregroundColor(.white.opacity(0.85))
					.lineLimit(2)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(10)
		.frame(maxWidth: 640)
		.background(Color.black.opacity(0.55))
		.cornerRadius(8)
		.padding(.horizontal, 16)
		.padding(.top, 8)
	}
}

/**
 * Choice
 *
 * Used to depict a single choice with a given label and value.
 */
struct Choice<T: Hashable> {
	var label: String
	var value: T

	init(_ label: String, _ value: T) {
		self.label = label
		self.value = value
	}
}

/**
 * Segmented Picker
 *
 * Displays a segmented picker with a given list of choices.
 */
struct SegmentPicker<SelectionValue: Hashable>: View {
	var selection: Binding<SelectionValue>
	var options: [Choice<SelectionValue>]

	init(selection: Binding<SelectionValue>, options: [Choice<SelectionValue>]) {
		self.selection = selection
		self.options = options
	}

	var body: some View {
		Picker("", selection: selection) {
			ForEach(options.indices, id: \.self) { i in
				Text(options[i].label).tag(options[i].value)
			}
		}
		.pickerStyle(.segmented)
	}
}

/**
 * Multiple Choice Picker
 *
 * Displays a button that opens a menu to pick from a given list of choices.
 */
struct MultiPicker<SelectionValue: Hashable>: View {
	var selection: Binding<SelectionValue>
	var options: [Choice<SelectionValue>]

	@State var showChoices: Bool = false
	@State var valueText: String = "Choose..."

	init(selection: Binding<SelectionValue>, options: [Choice<SelectionValue>]) {
		self.selection = selection
		self.options = options
	}

	var body: some View {
		if #available(iOS 15, *) {
			Picker("", selection: selection) {
				ForEach(options.indices, id: \.self) { i in
					Text(options[i].label).tag(options[i].value)
				}
			}
			.pickerStyle(.menu)
		} else {
			// Dumb workaround for older iOS versions. -Angel
			Button(action: {showChoices.toggle()}) {
				HStack {
					Text(valueText)
						.multilineTextAlignment(.center)
						.padding(.trailing, -4)
					Image(systemName: "chevron.up.chevron.down")
						.font(.system(size: 12))
				}
				.foregroundColor(Color("AccentColor"))
			}
			.actionSheet(isPresented: $showChoices) {
				genActionSheet()
			}
			.onAppear {
				for option in options {
					if option.value == selection.wrappedValue {
						valueText = option.label
						break
					}
				}
			}
		}
	}

	func genActionSheet() -> ActionSheet {
		let buttons = options.map { option in
			Alert.Button.default(Text(option.value == selection.wrappedValue ? "    \(option.label)  ✓" : option.label), action: {select(option)})
		}
		return ActionSheet(title: Text("Pick your preference:"), buttons: buttons + [Alert.Button.cancel()])
	}

	func select(_ option: Choice<SelectionValue>) {
		valueText = option.label
		selection.wrappedValue = option.value
	}
}

// MARK: - Liquid Glass

extension View {
	/// Floating control surface. Liquid Glass on iOS 26+, the old translucent fill before that.
	@ViewBuilder
	func glassPanel(cornerRadius: CGFloat = 16, fallback: Color = Color("BackgroundPrompt").opacity(0.75)) -> some View {
		if #available(iOS 26, *) {
			self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
		} else {
			self.background(Rectangle().fill(fallback)).cornerRadius(min(cornerRadius, 8))
		}
	}

	/// Interactive glass for a single floating button (menu / keyboard toggles over the stream).
	@ViewBuilder
	func glassControl(active: Bool = false, cornerRadius: CGFloat = 14) -> some View {
		if #available(iOS 26, *) {
			self.glassEffect(active ? .regular.interactive() : .clear.interactive(), in: .rect(cornerRadius: cornerRadius))
		} else {
			self.background(Rectangle().fill(Color("BackgroundPrompt").opacity(active ? 0.75 : 0.5))).cornerRadius(8)
		}
	}

	/// Content cards stay out of the glass layer (glass is for controls), just a continuous rounded fill.
	func card(cornerRadius: CGFloat = 8) -> some View {
		Group {
			if #available(iOS 26, *) {
				self.background(Color("BackgroundCard"), in: .rect(cornerRadius: 20, style: .continuous))
			} else {
				self.background(Rectangle().fill(Color("BackgroundCard"))).cornerRadius(cornerRadius)
			}
		}
	}
}

/**
 * Action Button
 *
 * Primary / secondary button. Native glass button styles on iOS 26+,
 * the original filled rounded rectangle on older systems.
 */
struct ActionButton: View {
	var title: String
	var systemImage: String?
	var prominent: Bool = true
	var fullWidth: Bool = false
	var role: ButtonRole?
	var action: () -> Void

	init(_ title: String, systemImage: String? = nil, prominent: Bool = true, fullWidth: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void) {
		self.title = title
		self.systemImage = systemImage
		self.prominent = prominent
		self.fullWidth = fullWidth
		self.role = role
		self.action = action
	}

	var body: some View {
		if #available(iOS 26, *) {
			let button = Button(role: role, action: action) {
				Group {
					if let systemImage = systemImage {
						Label(title, systemImage: systemImage)
					} else {
						Text(title)
					}
				}
				.lineLimit(1)
				.frame(maxWidth: fullWidth ? .infinity : nil)
			}
			.controlSize(fullWidth ? .extraLarge : .large)
			if prominent {
				button.buttonStyle(.glassProminent)
			} else {
				button.buttonStyle(.glass)
			}
		} else {
			Button(action: action) {
				Text(title)
					.lineLimit(1)
					.fixedSize()
					.foregroundColor(prominent ? .white : Color("Foreground"))
					.padding(.horizontal, fullWidth ? 0 : 20)
					.frame(maxWidth: fullWidth ? .infinity : nil, minHeight: fullWidth ? 54 : 44)
					.background(prominent ? Color("AccentColor") : Color("BackgroundButton"))
					.cornerRadius(8)
			}
		}
	}
}

// MARK: - iPhone Duo reserved regions

/// Space that custom (non-system) overlays must keep clear of on iPhone Duo:
/// camera occlusions (outer camera, inner camera while active) and the folding region.
struct DuoReservedSpace: Equatable {
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
		#if compiler(>=6.4) // iOS 27 SDK (Xcode 27); CI on Xcode 26 builds without Duo support
		if #available(iOS 27.1, *) {
			content.background(GeometryReader { proxy in
				let value = Self.read(proxy)
				Color.clear
					.onAppear { space = value }
					.onChange(of: value) { _, v in space = v }
			})
		} else {
			content
		}
		#else
		content
		#endif
	}

	#if compiler(>=6.4)
	@available(iOS 27.1, *)
	static func read(_ proxy: GeometryProxy) -> DuoReservedSpace {
		var out = DuoReservedSpace()
		for r in proxy.reservedRegions(kind: .occlusion) where r.isActive {
			out.occlusion.top = max(out.occlusion.top, r.margins.top)
			out.occlusion.leading = max(out.occlusion.leading, r.margins.leading)
			out.occlusion.bottom = max(out.occlusion.bottom, r.margins.bottom)
			out.occlusion.trailing = max(out.occlusion.trailing, r.margins.trailing)
		}
		out.fold = proxy.reservedRegions(kind: .division).first(where: { $0.isActive })?.frame
		return out
	}
	#endif
}

extension View {
	/// Reads iPhone Duo reserved regions for this view's frame. No-op before iOS 27.1 / on other devices.
	func readDuoReservedSpace(_ space: Binding<DuoReservedSpace>) -> some View {
		modifier(DuoReservedSpaceReader(space: space))
	}
}

struct ExUI_Previews: PreviewProvider {
	@State static var value1 = false
	@State static var value2 = true

	static var previews: some View {
		VStack {
			CatTitle("Category Title")
			CatList {
				CatItem("Category Item") {
					Toggle("", isOn: .constant(true))
						.frame(width: 80)
				}
			}
			CatTitle("Other Controls")
			CatList {
				CatItem("Segmented Picker") {
					SegmentPicker(selection: $value1, options:
					[
						Choice("False", false),
						Choice("True", true)
					])
					.frame(width: 180)
				}
				CatItem("Multiple Choice Picker") {
					MultiPicker(selection: $value2, options:
					[
						Choice("False", false),
						Choice("True", true)
					])
				}
			}
			Spacer()
		}
		.background(Rectangle().fill(Color("BackgroundGray")).edgesIgnoringSafeArea(.all))
		.foregroundColor(Color("Foreground"))
		.colorScheme(appScheme)
	}
}
