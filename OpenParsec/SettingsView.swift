import SwiftUI

struct SettingsView: View {
	@Binding var visible: Bool
	@ObservedObject private var settings = SettingsStore.shared

	let resolutionChoices: [Choice<ParsecResolution>]

	init(visible: Binding<Bool>) {
		_visible = visible
		var tmp: [Choice<ParsecResolution>] = []
		for res in ParsecResolution.resolutions {
			tmp.append(Choice(res.desc, res))
		}
		resolutionChoices = tmp
	}

	var body: some View {
		ZStack {
			if visible {
				// Background
				Rectangle()
					.fill(Color.init(red: 0, green: 0, blue: 0, opacity: 0.67))
					.edgesIgnoringSafeArea(.all)
			}
		}

		ZStack {
			if visible {
				// Main controls
				VStack {
					// Navigation controls
					ZStack {
						Rectangle()
							.fill(Color("BackgroundTab"))
							.frame(height: 52)
							.shadow(color: Color("Shading"), radius: 4, y: 6)
						ZStack {
							HStack {
								Button(action: saveAndExit, label: { Image(systemName: "xmark").scaleEffect(x: -1) })
								 .padding()
								Spacer()
							}
							Text("Settings")
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
							Spacer()
						}
						.foregroundColor(Color("AccentColor"))
					}
					.zIndex(1)

					ScrollView {
						VStack {
							CatTitle("Touch & Mouse")
							CatList {
								CatItem("Touch Mode") {
									MultiPicker(selection: $settings.cursorMode, options:
									[
										Choice("Touchpad", CursorMode.touchpad),
										Choice("Direct", CursorMode.direct)
									])
								}
								CatItem("Right Click") {
									MultiPicker(selection: $settings.rightClickPosition, options:
									[
										Choice("First Finger", RightClickPosition.firstFinger),
										Choice("Middle", RightClickPosition.middle),
										Choice("Second Finger", RightClickPosition.secondFinger)
									])
								}
								CatSlider("Pointer Speed", value: $settings.mouseSensitivity, in: 0.1...4, step: 0.1)
								CatSlider("Cursor Size", value: $settings.cursorScale, in: 0.1...4, step: 0.1)
								CatSlider("Scroll Speed", value: $settings.scrollSensitivity, in: 0.5...5, step: 0.5)
								CatItem("Reverse Scrolling") {
									Toggle("", isOn: $settings.reverseScrollDirection)
										.frame(width: 80)
								}
								CatItem("Pinch to Zoom") {
									Toggle("", isOn: $settings.zoomEnabled)
										.frame(width: 80)
								}
							}
							CatTitle("Keyboard")
							CatList {
								CatItem("Show Keyboard Button") {
									Toggle("", isOn: $settings.showKeyboardButton)
										.frame(width: 80)
								}
								CatItem("Option Key as Command") {
									Toggle("", isOn: $settings.optionAsCommand)
										.frame(width: 80)
								}
							}
							CatTitle("Video")
							CatList {
								CatItem("Renderer") {
									SegmentPicker(selection: $settings.renderer, options: [
										Choice("OpenGL", RendererType.opengl),
										Choice("Metal", RendererType.metal)
									])
									.frame(width: 165)
								}
								CatItem("Resolution") {
									MultiPicker(selection: $settings.resolution, options: resolutionChoices)
								}
								CatItem("Bitrate") {
									MultiPicker(selection: $settings.bitrate, options: [Choice("Host Default", 0)] + ParsecResolution.bitrates.map { Choice("\($0) Mbps", $0) })
								}
								CatItem("Frame Rate") {
									MultiPicker(selection: $settings.preferredFramesPerSecond, options:
									[
										Choice("Auto (Device Max)", 0),
										Choice("120 FPS", 120),
										Choice("60 FPS", 60),
										Choice("30 FPS", 30)
									])
								}
								CatItem("Constant Frame Rate") {
									Toggle("", isOn: $settings.constantFps)
										.frame(width: 80)
								}
								CatItem("Codec") {
									MultiPicker(selection: $settings.decoder, options:
									[
										Choice("H.264", DecoderPref.h264),
										Choice("Prefer H.265", DecoderPref.h265)
									])
								}
							}
							CatTitle("During a Stream")
							CatList {
								CatItem("Show Stream Stats") {
									Toggle("", isOn: $settings.alwaysShowStatus)
										.frame(width: 80)
								}
								CatItem("Show Menu Button") {
									Toggle("", isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 }))
										.frame(width: 80)
								}
								CatItem("Menu Edge Swipe") {
									MultiPicker(selection: $settings.menuSwipeEdge, options:
									[
										Choice("Off", MenuSwipeEdge.off),
										Choice("Left Edge", MenuSwipeEdge.left),
										Choice("Right Edge", MenuSwipeEdge.right)
									])
								}
								CatItem(UIDevice.current.userInterfaceIdiom == .pad ? "Hide iPad Status Bar" : "Hide iPhone Status Bar") {
									Toggle("", isOn: $settings.hideStatusBar)
										.frame(width: 80)
								}
								CatItem("Picture in Picture") {
									Toggle("", isOn: $settings.enablePiP)
										.frame(width: 80)
								}
								CatItem("Start Muted") {
									Toggle("", isOn: $settings.startMuted)
										.frame(width: 80)
								}
							}
							CatTitle("Developer")
							CatList {
								CatItem("Auto Reconnect") {
									Toggle("", isOn: $settings.autoReconnect)
										.frame(width: 80)
								}
								if settings.autoReconnect {
									CatItem("Show Reconnect Errors") {
										Toggle("", isOn: $settings.errorPrompts)
											.frame(width: 80)
									}
								}
								CatItem("Show Connection Log") {
									Toggle("", isOn: $settings.showConnectionLog)
										.frame(width: 80)
								}
							}
							Text(getVersionInfo())
								.multilineTextAlignment(.center)
								.opacity(0.5)
								.padding()
						}
					}
                    .foregroundColor(Color("Foreground"))
				}
				.background(Rectangle().fill(Color("BackgroundGray")))
				.cornerRadius(8)
				.padding()
			}
		}
        .preferredColorScheme(appScheme)
		.scaleEffect(visible ? 1 : 0, anchor: .zero)
	}

	func saveAndExit() {
		// SettingsHandler.renderer = renderer
		withAnimation(.easeInOut(duration: 0.24)) {
			visible = false
		}
	}

	func getVersionInfo() -> String {
		SettingsView.versionInfo()
	}

	static func versionInfo() -> String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown version"
		let commit = info?["GitCommitInfo"] as? String ?? "Unknown commit"
		return "Version \(version)-\(commit)"
	}
}

/// Native settings: a grouped Form in a sheet, used on iOS 26+ (system Liquid Glass toolbar and controls).
@available(iOS 26, *)
struct NativeSettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var settings = SettingsStore.shared

	var body: some View {
		NavigationStack {
			Form {
				Section("Touch & Mouse") {
					Picker("Touch Mode", selection: $settings.cursorMode) {
						Text("Touchpad").tag(CursorMode.touchpad)
						Text("Direct").tag(CursorMode.direct)
					}
					Picker("Right Click", selection: $settings.rightClickPosition) {
						Text("First Finger").tag(RightClickPosition.firstFinger)
						Text("Middle").tag(RightClickPosition.middle)
						Text("Second Finger").tag(RightClickPosition.secondFinger)
					}
					slider("Pointer Speed", value: $settings.mouseSensitivity, in: 0.1...4, step: 0.1)
					slider("Cursor Size", value: $settings.cursorScale, in: 0.1...4, step: 0.1)
					slider("Scroll Speed", value: $settings.scrollSensitivity, in: 0.5...5, step: 0.5)
					Toggle("Reverse Scrolling", isOn: $settings.reverseScrollDirection)
					Toggle("Pinch to Zoom", isOn: $settings.zoomEnabled)
				}
				Section("Keyboard") {
					Toggle("Show Keyboard Button", isOn: $settings.showKeyboardButton)
					Toggle("Option Key as Command", isOn: $settings.optionAsCommand)
				}
				Section("Video") {
					Picker("Renderer", selection: $settings.renderer) {
						Text("OpenGL").tag(RendererType.opengl)
						Text("Metal").tag(RendererType.metal)
					}
					.pickerStyle(.segmented)
					Picker("Resolution", selection: $settings.resolution) {
						ForEach(ParsecResolution.resolutions, id: \.self) { Text($0.desc).tag($0) }
					}
					Picker("Bitrate", selection: $settings.bitrate) {
						Text("Host Default").tag(0)
						ForEach(ParsecResolution.bitrates, id: \.self) { Text("\($0) Mbps").tag($0) }
					}
					Picker("Frame Rate", selection: $settings.preferredFramesPerSecond) {
						Text("Auto (Device Max)").tag(0)
						Text("120 FPS").tag(120)
						Text("60 FPS").tag(60)
						Text("30 FPS").tag(30)
					}
					Toggle("Constant Frame Rate", isOn: $settings.constantFps)
					Picker("Codec", selection: $settings.decoder) {
						Text("H.264").tag(DecoderPref.h264)
						Text("Prefer H.265").tag(DecoderPref.h265)
					}
				}
				Section("During a Stream") {
					Toggle("Show Stream Stats", isOn: $settings.alwaysShowStatus)
					Toggle("Show Menu Button", isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 }))
					Picker("Menu Edge Swipe", selection: $settings.menuSwipeEdge) {
						Text("Off").tag(MenuSwipeEdge.off)
						Text("Left Edge").tag(MenuSwipeEdge.left)
						Text("Right Edge").tag(MenuSwipeEdge.right)
					}
					Toggle("Hide Status Bar", isOn: $settings.hideStatusBar)
					Toggle("Picture in Picture", isOn: $settings.enablePiP)
					Toggle("Start Muted", isOn: $settings.startMuted)
				}
				Section {
					Toggle("Auto Reconnect", isOn: $settings.autoReconnect)
					if settings.autoReconnect {
						Toggle("Show Reconnect Errors", isOn: $settings.errorPrompts)
					}
					Toggle("Show Connection Log", isOn: $settings.showConnectionLog)
				} header: {
					Text("Developer")
				} footer: {
					Text(SettingsView.versionInfo())
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) { dismiss() } label: { Label("Close", systemImage: "xmark") }
				}
			}
		}
	}

	private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			LabeledContent(title, value: String(format: "%.1f", value.wrappedValue))
			Slider(value: value, in: range, step: step)
		}
	}
}

extension View {
	/// Presents settings as a native sheet on iOS 26+, or the original in-place overlay before that.
	@ViewBuilder
	func settingsPresentation(isPresented: Binding<Bool>) -> some View {
		if #available(iOS 26, *) {
			self.sheet(isPresented: isPresented) { NativeSettingsView().preferredColorScheme(appScheme) }
		} else {
			self.overlay(SettingsView(visible: isPresented))
		}
	}
}

struct SettingsView_Previews: PreviewProvider {
	@State static var value: Bool = true

	static var previews: some View {
		SettingsView(visible: $value)
	}
}
