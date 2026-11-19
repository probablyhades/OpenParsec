import SwiftUI

/// Settings form. A tab on the main screen (with the account section), and a sheet during a stream.
struct SettingsView: View {
	/// Signed-in user, shown above the settings when available.
	var account: IdentifiableUserInfo?
	/// Set on the main screen to offer Log Out.
	var onLogout: (() -> Void)?
	/// Presented as a sheet over the stream, so it needs its own close button.
	var inStream: Bool = false

	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var settings = SettingsStore.shared
	@State private var confirmLogout = false

	var body: some View {
		NavigationStack {
			Form {
				if let onLogout = onLogout {
					Section {
						if let account = account {
							HStack(spacing: 14) {
								Avatar(userID: account.id, name: account.username, size: 52)
								VStack(alignment: .leading, spacing: 2) {
									Text(account.username)
										.font(.headline)
									Text("#\(String(account.id))")
										.font(.subheadline)
										.monospacedDigit()
										.foregroundStyle(.secondary)
								}
							}
							.padding(.vertical, 2)
							.accessibilityElement(children: .combine)
						}
						Button(role: .destructive) { confirmLogout = true } label: {
							Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
								.foregroundStyle(.red)
						}
						.confirmationDialog("Log out of your Parsec account?", isPresented: $confirmLogout, titleVisibility: .visible) {
							Button("Log Out", role: .destructive, action: onLogout)
						}
					}
				}

				Section("Touch & Mouse") {
					Picker(selection: $settings.cursorMode) {
						Text("Touchpad").tag(CursorMode.touchpad)
						Text("Direct").tag(CursorMode.direct)
					} label: { Label("Touch Mode", systemImage: "hand.point.up.left") }
					Picker(selection: $settings.rightClickPosition) {
						Text("First Finger").tag(RightClickPosition.firstFinger)
						Text("Middle").tag(RightClickPosition.middle)
						Text("Second Finger").tag(RightClickPosition.secondFinger)
					} label: { Label("Right Click", systemImage: "cursorarrow.click.2") }
					slider("Pointer Speed", "cursorarrow.motionlines", value: $settings.mouseSensitivity, in: 0.1...4, step: 0.1)
					slider("Cursor Size", "arrow.up.left.and.arrow.down.right", value: $settings.cursorScale, in: 0.1...4, step: 0.1)
					slider("Scroll Speed", "arrow.up.and.down", value: $settings.scrollSensitivity, in: 0.5...5, step: 0.5)
					Toggle(isOn: $settings.reverseScrollDirection) { Label("Reverse Scrolling", systemImage: "arrow.up.arrow.down") }
					Toggle(isOn: $settings.zoomEnabled) { Label("Pinch to Zoom", systemImage: "plus.magnifyingglass") }
				}

				Section("Keyboard") {
					Toggle(isOn: $settings.showKeyboardButton) { Label("Show Keyboard Button", systemImage: "keyboard") }
					Toggle(isOn: $settings.optionAsCommand) { Label("Option Key as Command", systemImage: "command") }
				}

				Section {
					Picker(selection: $settings.renderer) {
						Text("OpenGL").tag(RendererType.opengl)
						Text("Metal").tag(RendererType.metal)
					} label: { Label("Renderer", systemImage: "cpu") }
					Picker(selection: $settings.resolution) {
						ForEach(ParsecResolution.resolutions, id: \.self) { Text($0.desc).tag($0) }
					} label: { Label("Resolution", systemImage: "aspectratio") }
					Picker(selection: $settings.bitrate) {
						Text("Host Default").tag(0)
						ForEach(ParsecResolution.bitrates, id: \.self) { Text("\($0) Mbps").tag($0) }
					} label: { Label("Bitrate", systemImage: "speedometer") }
					Picker(selection: $settings.preferredFramesPerSecond) {
						Text("Auto (Device Max)").tag(0)
						Text("120 FPS").tag(120)
						Text("60 FPS").tag(60)
						Text("30 FPS").tag(30)
					} label: { Label("Frame Rate", systemImage: "timer") }
					Toggle(isOn: $settings.constantFps) { Label("Constant Frame Rate", systemImage: "metronome") }
					Picker(selection: $settings.decoder) {
						Text("H.264").tag(DecoderPref.h264)
						Text("Prefer H.265").tag(DecoderPref.h265)
					} label: { Label("Codec", systemImage: "film") }
				} header: {
					Text("Video")
				} footer: {
					Text("Changing the codec during a stream reconnects it.")
				}

				Section {
					Toggle(isOn: $settings.alwaysShowStatus) { Label("Show Stream Stats", systemImage: "waveform.path.ecg") }
					Toggle(isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 })) { Label("Show Menu Button", systemImage: "line.3.horizontal") }
					Picker(selection: $settings.menuSwipeEdge) {
						Text("Off").tag(MenuSwipeEdge.off)
						Text("Left Edge").tag(MenuSwipeEdge.left)
						Text("Right Edge").tag(MenuSwipeEdge.right)
					} label: { Label("Menu Edge Swipe", systemImage: "hand.draw") }
					Toggle(isOn: $settings.hideStatusBar) { Label("Hide Status Bar", systemImage: "rectangle.topthird.inset.filled") }
					Toggle(isOn: $settings.enablePiP) { Label("Picture in Picture", systemImage: "pip") }
					Toggle(isOn: $settings.startMuted) { Label("Start Muted", systemImage: "speaker.slash") }
				} header: {
					Text("During a Stream")
				} footer: {
					Text("Changing Picture in Picture during a stream reconnects it.")
				}

				Section("Connection") {
					Toggle(isOn: $settings.autoReconnect) { Label("Auto Reconnect", systemImage: "arrow.clockwise") }
					if settings.autoReconnect {
						Toggle(isOn: $settings.errorPrompts) { Label("Show Reconnect Errors", systemImage: "exclamationmark.bubble") }
					}
					Toggle(isOn: $settings.showConnectionLog) { Label("Show Connection Log", systemImage: "text.alignleft") }
				}

				Section("About") {
					LabeledContent("Version", value: SettingsView.versionInfo())
					Link(destination: URL(string: "https://github.com/hugeBlack/OpenParsec")!) {
						Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
					}
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(inStream ? .inline : .large)
			.toolbar {
				if inStream {
					ToolbarItem(placement: .cancellationAction) {
						Button(role: .close) { dismiss() } label: { Label("Close", systemImage: "xmark") }
					}
				}
			}
		}
	}

	private func slider(_ title: String, _ systemImage: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			LabeledContent {
				Text(String(format: "%.1f", value.wrappedValue))
					.monospacedDigit()
			} label: {
				Label(title, systemImage: systemImage)
			}
			Slider(value: value, in: range, step: step) { Text(title) }
		}
	}

	static func versionInfo() -> String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown version"
		let commit = info?["GitCommitInfo"] as? String ?? "Unknown commit"
		return "\(version)-\(commit)"
	}
}

#Preview {
	SettingsView(account: IdentifiableUserInfo(id: 1234567, username: "player"), onLogout: {})
		.preferredColorScheme(.dark)
}
