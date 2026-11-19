import SwiftUI
import ParsecSDK
import Foundation
import AVFoundation

struct ParsecStatusBar: View {
	@Binding var showMenu: Bool
	@State var metrics: [StreamMetric] = []
	/// Safe area and iPhone Duo occlusions of the full-bleed stream.
	var reserved: DuoReservedSpace = .none
	/// Width taken by the open menu when it sits beside the readout (landscape).
	var menuInset: CGFloat = 0
	@Binding var showDCAlert: Bool
	@Binding var DCAlertText: String
	@Binding var isReconnecting: Bool
	@Binding var connectionLost: Bool
	@Binding var waitingForNetwork: Bool
	@Binding var waitingForStream: Bool
	@State var networkFailureSince: Date?
	@State var frameHeld = false
	@State var parsecViewController: ParsecViewController?
	@State var wasDisconnected: Bool = true
	@State var liveSince: CFTimeInterval?
	@State var seenInterfaceChanges = NetworkWatcher.shared.interfaceChanges
	let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
	let onSilentDisconnect: () -> Void

	init(showMenu: Binding<Bool>, reserved: DuoReservedSpace, menuInset: CGFloat, showDCAlert: Binding<Bool>, DCAlertText: Binding<String>, parsecViewController: ParsecViewController, isReconnecting: Binding<Bool>, connectionLost: Binding<Bool>, waitingForNetwork: Binding<Bool>, waitingForStream: Binding<Bool>, onSilentDisconnect: @escaping () -> Void) {
		_showMenu = showMenu
		self.reserved = reserved
		self.menuInset = menuInset
		_showDCAlert = showDCAlert
		_DCAlertText = DCAlertText
		_isReconnecting = isReconnecting
		_connectionLost = connectionLost
		_waitingForNetwork = waitingForNetwork
		_waitingForStream = waitingForStream
		self.parsecViewController = parsecViewController
		self.onSilentDisconnect = onSilentDisconnect
	}

	var body: some View {
		if (showMenu || SettingsHandler.alwaysShowStatus) && !metrics.isEmpty {
			FlowLayout(spacing: 14, lineSpacing: 3) {
				ForEach(metrics) { metric in
					HStack(spacing: 4) {
						Text(metric.label)
							.foregroundStyle(.secondary)
						Text(metric.value)
							.monospacedDigit()
					}
				}
			}
			.font(.caption2.weight(.medium))
			.padding(.horizontal, 14)
			.padding(.vertical, 7)
			.glassEffect(.regular, in: .rect(cornerRadius: 16))
			// bottom centre: clear of the menu in the leading corner and of the sensor housing
			.padding(.bottom, max(reserved.occlusion.bottom, 10))
			.padding(.horizontal, max(reserved.safeArea.leading, reserved.safeArea.trailing, 16))
			.padding(.leading, menuInset)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
			.allowsHitTesting(false)
			.environment(\.colorScheme, .dark)
			.zIndex(1)
			.accessibilityElement(children: .combine)
		}
		EmptyView()
			.onReceive(timer) { _ in
				poll()
			}
	}

	func holdFrame(_ hold: Bool) {
		let pumping = PictureInPictureManager.shared.isPumping
		if hold {
			frameHeld = true
			if !pumping { ParsecBackgroundManager.shared.glkViewController?.isPaused = true }
		} else if frameHeld {
			frameHeld = false
			if !pumping { ParsecBackgroundManager.shared.glkViewController?.isPaused = false }
		}
	}

	func pictureBack() {
		guard isReconnecting, liveSince != nil else { return }
		ParsecBackgroundManager.shared.onNextFrame = nil
		liveSince = nil
		withAnimation(.easeOut(duration: 0.3)) {
			isReconnecting = false
			waitingForStream = false
		}
		appNote("[reconnect] picture back")
	}

	func poll() {
		if showDCAlert || ParsecBackgroundManager.shared.isPaused || ParsecBackgroundManager.shared.endedByUser {
			return
		}

		var pcs = ParsecClientStatus()
		var status = CParsec.getStatusEx(&pcs)

		let pipActive = PictureInPictureManager.shared.isPiPActive
		let offline = NetworkWatcher.shared.noNetwork

		if waitingForNetwork {
			if offline {
				holdFrame(true)
				return
			}
			waitingForNetwork = false
			ParsecBackgroundManager.shared.resumedAt = Date()
			if let peerId = ParsecBackgroundManager.shared.lastPeerId {
				let mgr = ParsecBackgroundManager.shared
				mgr.reconnectAttempts = 1
				appNote("[reconnect] network back, reconnecting")
				isReconnecting = true
				parsecViewController?.resetKeyState()
				CParsec.reconnect(peerId)
				mgr.reconnectStartTime = Date()
				return
			}
		}

		if status == PARSEC_OK && !isReconnecting && !pipActive {
			if offline {
				appNote("[stream] no network, not waiting on sdk")
				status = NETWORK_ERR_INTERRUPTED
			} else if SettingsHandler.autoReconnect && NetworkWatcher.shared.interfaceChanges != seenInterfaceChanges {
				appNote("[stream] network interface changed, reconnecting")
				status = NETWORK_ERR_INTERRUPTED
			}
		}
		seenInterfaceChanges = NetworkWatcher.shared.interfaceChanges

		if status == PARSEC_OK && pcs.networkFailure && !isReconnecting && !pipActive {
			if networkFailureSince == nil { networkFailureSince = Date() }
			let lost = Date().timeIntervalSince(networkFailureSince!)
			let justResumed = Date().timeIntervalSince(ParsecBackgroundManager.shared.resumedAt ?? .distantPast) < 10
			connectionLost = true
			if lost >= 3 || justResumed {
				networkFailureSince = nil
				connectionLost = false
				ParsecBackgroundManager.shared.resumedAt = nil
				status = NETWORK_ERR_INTERRUPTED
				appNote("[stream] network failure held, treating it as a lost connection")
			}
		} else {
			networkFailureSince = nil
			connectionLost = false
		}

		if status != PARSEC_OK {
			liveSince = nil
			waitingForStream = false
			ParsecBackgroundManager.shared.onNextFrame = nil
			holdFrame(true)
			if ParsecBackgroundManager.shared.isMarkedForReconnect {
				return
			}

			if offline && !pipActive {
				isReconnecting = false
				connectionLost = false
				if SettingsHandler.autoReconnect && ParsecBackgroundManager.shared.lastPeerId != nil {
					ParsecBackgroundManager.shared.reconnectAttempts = 0
					waitingForNetwork = true
					appNote("[stream] no network, waiting")
					return
				}
				appNote("[stream] ended, no network, alert")
				DCAlertText = "No network connection"
				showDCAlert = true
				return
			}

			let setupFailure = isReconnecting ? CParsec.setupError.flatMap { $0.at > ParsecBackgroundManager.shared.reconnectStartTime ? $0.line : nil } : nil

			if status == PARSEC_CONNECTING && isReconnecting && setupFailure == nil {
				if Date().timeIntervalSince(ParsecBackgroundManager.shared.reconnectStartTime) < 15 {
					return
				}
			}

			if status == CONNECT_WRN_APPROVAL && isReconnecting && setupFailure == nil {
				if Date().timeIntervalSince(ParsecBackgroundManager.shared.reconnectStartTime) < 60 {
					return
				}
			}

			// PiP: connection died (screen lock killed GPU). Kill connection+audio once,
			// subsequent polls exit via isMarkedForReconnect above.
			if pipActive {
				appNote("[stream] lost during picture in picture, status \(status.rawValue), reconnect owed")
				CParsec.disconnect()
				try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
				ParsecBackgroundManager.shared.connectionDidEnd()
				ParsecBackgroundManager.shared.markForReconnect()
				wasDisconnected = true
				return
			}

			if SettingsHandler.autoReconnect, !status.isPermanentFailure || (status == CONNECT_WRN_APPROVAL && setupFailure != nil), let peerId = ParsecBackgroundManager.shared.lastPeerId {
				let mgr = ParsecBackgroundManager.shared
				if mgr.reconnectAttempts < 3 {
					let gap: TimeInterval = mgr.reconnectAttempts == 0 ? 0 : mgr.reconnectAttempts == 1 ? 2 : 5
					if Date().timeIntervalSince(mgr.reconnectStartTime) < gap {
						return
					}
					mgr.reconnectAttempts += 1
					appNote("[reconnect] attempt \(mgr.reconnectAttempts) after status \(status.rawValue)\(setupFailure.map { ", sdk setup failed: \($0)" } ?? "")")
					isReconnecting = true
					parsecViewController?.resetKeyState()
					CParsec.reconnect(peerId)
					mgr.reconnectStartTime = Date()
					return
				}
				mgr.reconnectAttempts = 0
			}

			isReconnecting = false
			wasDisconnected = true
			let silent = SettingsHandler.autoReconnect && !SettingsHandler.errorPrompts && !status.isPermanentFailure
			appNote("[stream] ended, status \(status.rawValue), \(silent ? "silent" : "alert")")
			if silent {
				// silent: auto-reconnect spent its retries, dont nag with an alert
				onSilentDisconnect()
			} else {
				DCAlertText = status.readable()
				showDCAlert = true
			}
			return
		}

		holdFrame(connectionLost)

		if isReconnecting {
			if liveSince == nil {
				liveSince = CACurrentMediaTime()
				withAnimation(.easeInOut(duration: 0.2)) { waitingForStream = true }
				ParsecBackgroundManager.shared.onNextFrame = { pictureBack() }
				ParsecBackgroundManager.shared.reconnectAttempts = 0
				appNote("[reconnect] live again")
				ParsecView.getHostUserData()
				// SDK forgets stream dims on reconnect, re-send them so the frame fills not corners
				if let vc = parsecViewController {
					CParsec.setFrame(vc.view.bounds.width, vc.view.bounds.height, vc.screenScale)
				}
			}
			if CParsec.runningRenderer != .metal || CACurrentMediaTime() - liveSince! > 6 {
				pictureBack()
			}
		}

		if showMenu || SettingsHandler.alwaysShowStatus {
			let decoderName = String.fromBuffer(&pcs.decoder.0.name.0, length: 16)
			let m = pcs.`self`.metrics.0
			let d = pcs.decoder.0
			metrics = [
				StreamMetric(label: "Decode", value: String(format: "%.2f ms", m.decodeLatency)),
				StreamMetric(label: "Encode", value: String(format: "%.2f ms", m.encodeLatency)),
				StreamMetric(label: "Network", value: String(format: "%.2f ms", m.networkLatency)),
				StreamMetric(label: "Bitrate", value: String(format: "%.2f Mbps", m.bitrate)),
				StreamMetric(label: "RTx", value: "\(m.fastRTs + m.slowRTs)"),
				StreamMetric(label: "Queue", value: "\(m.queuedFrames)"),
				StreamMetric(label: "Draw", value: "\(String(format: "%.0f", CParsec.drawRate)) fps \(CParsec.rendererName)"),
				StreamMetric(label: d.h265 ? "H.265" : "H.264", value: "\(d.width)×\(d.height) \(d.color444 ? "4:4:4" : "4:2:0") \(decoderName)")
			]
		}
	}
}

struct StreamMetric: Identifiable {
	var label: String
	var value: String
	var id: String { label }
}

// CRITICAL: This class exists to PERSIST the ParsecViewController instance across SwiftUI view updates.
// Do not remove or change to a struct. If ParsecViewController is recreated, the keyboard responder chain breaks.
class ParsecSession: ObservableObject {
    let controller: ParsecViewController

    init() {
        self.controller = ParsecViewController()
    }
}

struct MenuRowsHeightKey: PreferenceKey {
	static let defaultValue: CGFloat = 0

	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}

struct ParsecView: View {
	var controller: ContentView?

	@State var showDCAlert: Bool = false
	@State var DCAlertText: String = "Disconnected (reason unknown)"
	@State var hideOverlay: Bool = false
	@State var hideKeyboardButton: Bool = false
	@AppStorage("keyboardHintShown") var keyboardHintShown: Bool = false
	@AppStorage("keyboardPanHintShown") var keyboardPanHintShown: Bool = false
	@State var hint: String?
	@State var showMenu: Bool = false
	@State var menuRowsHeight: CGFloat = 0
	@ScaledMetric var menuWidth: CGFloat = 270
	@Namespace private var glass
	@AppStorage("menuSwipeHintShown") var menuSwipeHintShown: Bool = false

	@State var showKeyboard: Bool = false
	@State var zoomEnabled: Bool = false
	@Environment(\.verticalSizeClass) var verticalSizeClass

	@State var muted: Bool = false
	@State var preferH265: Bool = true
	@State var isReconnecting: Bool = false
	@State var connectionLost: Bool = false
	@State var showSettings: Bool = false
	@State var decoderAtOpen: DecoderPref = .h264
	@State var fpsAtOpen: Int = 0
	@State var pipAtOpen: Bool = false
	@State var resolutionAtOpen: ParsecResolution = .client
	@State var bitrateAtOpen: Int = 0
	@State var waitingForNetwork: Bool = false
	@State var waitingForStream: Bool = false
	/// iPhone Duo camera occlusions and fold; the stream itself stays full-bleed, only our overlays avoid them.
	@State var duoSpace: DuoReservedSpace = .none

	@State var resolutions: [ParsecResolution]
	@State var bitrates: [Int]

    // Persist the VC across view updates using StateObject.
    // CRITICAL: Changing this to @State or a simple var will break the keyboard after menu interactions.
	@StateObject var session = ParsecSession()

    // Observer shared state for updates
    @ObservedObject var dataModel = DataManager.model
	@ObservedObject var settingsStore = SettingsStore.shared

    // Computed property for convenience refactoring
    var parsecViewController: ParsecViewController {
        return session.controller
    }

	// @State var showDisplays: Bool = false

	init(_ controller: ContentView?) {
		self.controller = controller

		_muted = State(initialValue: SettingsHandler.startMuted)
		_zoomEnabled = State(initialValue: SettingsHandler.zoomEnabled)
		_resolutions = State(initialValue: ParsecResolution.resolutions)
		_bitrates = State(initialValue: ParsecResolution.bitrates)

    }

    // We need to set up the callback somewhere safer than init.
    // 'onAppear' is a good place, or inside the init of ParsecSession if possible (but it doesn't have access to binding).
    // Let's use onAppear/post.

	var body: some View {
		ZStack {

			UIViewControllerWrapper(self.parsecViewController)
				.zIndex(1)
				.persistentSystemOverlays(.hidden)

			ParsecStatusBar(showMenu: $showMenu, reserved: duoSpace, menuInset: showMenu && verticalSizeClass == .compact ? menuWidth + 74 : 0, showDCAlert: $showDCAlert, DCAlertText: $DCAlertText, parsecViewController: parsecViewController, isReconnecting: $isReconnecting, connectionLost: $connectionLost, waitingForNetwork: $waitingForNetwork, waitingForStream: $waitingForStream, onSilentDisconnect: { disconnect() })

			if isReconnecting || connectionLost || waitingForNetwork {
				StatusOverlay(
					symbol: waitingForNetwork ? "wifi.slash" : isReconnecting ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark",
					animating: !waitingForNetwork,
					title: overlayTitle,
					message: waitingForNetwork ? "OpenParsec will reconnect when you're back online" : nil,
					showLog: settingsStore.showConnectionLog,
					overStream: true
				) {
					Button("Close") { disconnect() }
				}
				.transition(.asymmetric(insertion: .identity, removal: .opacity))
				.zIndex(10)
			}

			if dataModel.isBlocked {
				toast("Host is using the machine", systemImage: "lock.fill")
					.zIndex(3)
			}

			if let hint = hint {
				toast(hint, systemImage: nil)
					.padding(.top, showKeyboard ? 100 : 0)
					.frame(maxHeight: .infinity, alignment: showKeyboard ? .top : .center)
					.allowsHitTesting(false)
					.transition(.opacity.combined(with: .scale(scale: 0.94)))
					.zIndex(3)
			}

			// The stream stays full-bleed; these controls float over it in one glass group.
			GlassEffectContainer(spacing: 10) {
				HStack(alignment: .top, spacing: 0) {
					VStack(alignment: .leading, spacing: 10) {
						if !hideOverlay {
							Button(action: toggleMenu) {
								Image("IconTransparent")
									.resizable()
									.scaledToFit()
									.frame(width: 34, height: 34)
									.opacity(showMenu ? 1 : 0.7)
									.frame(width: 48, height: 48)
									.contentShape(.circle)
							}
							.glassEffect(showMenu ? .regular.interactive() : .clear.interactive(), in: .circle)
							.glassEffectID("menuButton", in: glass)
							.accessibilityLabel(showMenu ? "Close Menu" : "Menu")
						}
						if !hideKeyboardButton {
							Button(action: toggleKeyboard) {
								Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
									.font(.system(size: 19, weight: .medium))
									.contentTransition(.symbolEffect(.replace))
									.frame(width: 48, height: 48)
									.contentShape(.circle)
							}
							.glassEffect(showKeyboard ? .regular.interactive() : .clear.interactive(), in: .circle)
							.glassEffectID("keyboardButton", in: glass)
							.accessibilityLabel(showKeyboard ? "Hide Keyboard" : "Show Keyboard")
						}
						if showMenu && verticalSizeClass != .compact {
							menuPanel
								.layoutPriority(1)
						}
					}
					.fixedSize(horizontal: showMenu && verticalSizeClass == .compact, vertical: false)
					if showMenu && verticalSizeClass == .compact {
						menuPanel
							.padding(.leading, 10)
					}
					Spacer(minLength: 0)
				}
			}
			.buttonStyle(.plain)
			.foregroundStyle(.white)
			.environment(\.colorScheme, .dark)
			.padding(16)
			.padding(duoSpace.occlusion)
			.frame(maxHeight: duoSpace.heightAboveFold(from: 0), alignment: .top)
			.frame(maxHeight: .infinity, alignment: .top)
			.zIndex(2)
		}
		.statusBarHidden(SettingsHandler.hideStatusBar)
		.alert(DCAlertText, isPresented: $showDCAlert) {
			Button("Reconnect") {
				guard let peerId = ParsecBackgroundManager.shared.lastPeerId else {
					disconnect()
					return
				}
				if NetworkWatcher.shared.noNetwork {
					DispatchQueue.main.async {
						DCAlertText = "No network connection"
						showDCAlert = true
					}
					return
				}
				reconnectTo(peerId)
			}
			Button("Close", role: .cancel) { disconnect() }
		}
		.onChange(of: showSettings) { _, open in
			if !open { applyStreamSettings() }
		}
		.onChange(of: isReconnecting) { _, reconnecting in
			if !reconnecting {
				CParsec.setMuted(muted)
				if muted { CParsec.pause(video: false, audio: true) }
			}
		}
		.onAppear(perform: post)
		.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ParsecBackgroundDisconnect"))) { _ in
			if PictureInPictureManager.shared.isPiPActive {
				return
			}
			disconnect(isBackgroundDisconnect: true)
		}
		.ignoresSafeArea()
		.readDuoReservedSpace($duoSpace)
		.sheet(isPresented: $showSettings) {
			SettingsView(inStream: true)
				.preferredColorScheme(.dark)
		}
	}

	func toast(_ text: String, systemImage: String?) -> some View {
		HStack(spacing: 8) {
			if let systemImage = systemImage {
				Image(systemName: systemImage)
					.foregroundStyle(.secondary)
			}
			Text(text)
				.multilineTextAlignment(.center)
		}
		.font(.subheadline.weight(.medium))
		.foregroundStyle(.white)
		.padding(.horizontal, 18)
		.padding(.vertical, 12)
		.glassEffect(.regular, in: .rect(cornerRadius: 22))
		.environment(\.colorScheme, .dark)
		.padding(.horizontal, 24)
	}

	func toggleMenu() {
		withAnimation(.smooth(duration: 0.3)) { showMenu.toggle() }
		if showMenu { ParsecView.getHostUserData() }
	}

	var menuPanel: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(spacing: 0) {
					Button(action: disableOverlay) {
						menuRow("Hide Buttons", "eye.slash")
					}
					Button(action: toggleMute) {
						menuRow("Sound", muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: muted ? "Off" : "On")
					}
					Menu {
						ForEach(resolutions, id: \.self) { resolution in
							Toggle(resolution.desc, isOn: Binding(
								get: { resolution.width == dataModel.resolutionX && resolution.height == dataModel.resolutionY },
								set: { _ in changeResolution(res: resolution) }
							))
						}
					} label: {
						menuRow("Resolution", "aspectratio", picker: true)
					}
					Menu {
						Toggle("Host Default", isOn: Binding(get: { settingsStore.bitrate == 0 }, set: { _ in changeBitRate(bitrate: 0) }))
						ForEach(bitrates, id: \.self) { bitrate in
							Toggle("\(bitrate) Mbps", isOn: Binding(get: { bitrate == settingsStore.bitrate }, set: { _ in changeBitRate(bitrate: bitrate) }))
						}
					} label: {
						menuRow("Bitrate", "speedometer", value: settingsStore.bitrate == 0 ? "Default" : "\(settingsStore.bitrate) Mbps", picker: true)
					}
					if dataModel.displayConfigs.count > 1 {
						Menu {
							Button("Auto") {
								changeDisplay(displayId: "none")
							}
							ForEach(dataModel.displayConfigs, id: \.self) { config in
								Button("\(config.name) \(config.adapterName)") {
									changeDisplay(displayId: config.id)
								}
							}
						} label: {
							menuRow("Switch Display", "display.2", picker: true)
						}
					}
					Button(action: toggleConstantFps) {
						menuRow("Constant Frame Rate", "metronome", value: dataModel.constantFps ? "On" : "Off")
					}
					Button(action: toggleZoom) {
						menuRow("Pinch to Zoom", "plus.magnifyingglass", value: zoomEnabled ? "On" : "Off")
					}
					Button(action: toggleTouchMode) {
						menuRow("Touch Mode", settingsStore.cursorMode == .direct ? "hand.point.up.left" : "rectangle.and.hand.point.up.left", value: settingsStore.cursorMode == .direct ? "Direct" : "Touchpad")
					}
					Button(action: openSettings) {
						menuRow("Settings", "gear")
					}
				}
				.padding(.top, 6)
				.background(GeometryReader { proxy in
					Color.clear.preference(key: MenuRowsHeightKey.self, value: proxy.size.height)
				})
			}
			.frame(maxHeight: menuRowsHeight)
			.onPreferenceChange(MenuRowsHeightKey.self) { menuRowsHeight = $0 }
			Divider()
				.padding(.horizontal, 16)
			Button(role: .destructive, action: { disconnect() }) {
				menuRow("Disconnect", "xmark.circle.fill")
					.foregroundStyle(.red)
			}
			.padding(.bottom, 6)
		}
		.glassEffect(.regular, in: .rect(cornerRadius: 26))
		.glassEffectID("menuPanel", in: glass)
		.frame(maxWidth: menuWidth)
	}

	/// Menu rows carry a symbol, their title and the current value, so they read at a glance over the stream.
	func menuRow(_ title: String, _ systemImage: String, value: String? = nil, picker: Bool = false) -> some View {
		HStack(spacing: 12) {
			Image(systemName: systemImage)
				.font(.body)
				.frame(width: 26)
			Text(title)
				.lineLimit(1)
			Spacer(minLength: 8)
			if let value = value {
				Text(value)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			if picker {
				Image(systemName: "chevron.up.chevron.down")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
			}
		}
		.font(.subheadline)
		.padding(.horizontal, 16)
		.frame(minHeight: 44)
		.contentShape(.rect)
	}

	var overlayTitle: String {
		if waitingForNetwork {
			return "No network connection"
		}
		if !isReconnecting {
			return "Connection lost..."
		}
		if waitingForStream {
			return "Reconnected, waiting for the stream..."
		}
		return ParsecBackgroundManager.shared.lastHostname.map { "Reconnecting to \($0)..." } ?? "Reconnecting..."
	}

	func post() {
		ParsecBackgroundManager.shared.onShouldDisconnect = {
			NotificationCenter.default.post(name: NSNotification.Name("ParsecBackgroundDisconnect"), object: nil)
		}
		ParsecBackgroundManager.shared.onEndedInBackground = { [self] in
			ParsecBackgroundManager.shared.onNextFrame = nil
			waitingForStream = false
			if showDCAlert || waitingForNetwork { return }
			isReconnecting = true
		}
		ParsecBackgroundManager.shared.onResumeEndedSession = { [self] in
			if showDCAlert || waitingForNetwork { return }
			guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
			appNote("[reconnect] back from the background, reconnecting")
			reconnectTo(peerId)
			ParsecBackgroundManager.shared.reconnectAttempts = 1
		}
		do {
			PictureInPictureManager.shared.onPiPStopped = { [self] in
				if UIApplication.shared.applicationState != .active {
					ParsecBackgroundManager.shared.glkViewController?.isPaused = true
					CParsec.sendReleaseMessage()
					CParsec.pause()
					ParsecBackgroundManager.shared.isPaused = true
					if UIApplication.shared.applicationState == .background {
						ParsecBackgroundManager.shared.holdSessionInBackground()
					}
				} else {
					if ParsecBackgroundManager.shared.isReconnecting {
						return
					}
					// Check actual Parsec status — timers don't reliably fire in background
					var pcs = ParsecClientStatus()
					let currentStatus = CParsec.getStatusEx(&pcs)
					if currentStatus != PARSEC_OK || ParsecBackgroundManager.shared.isMarkedForReconnect {
						CParsec.disconnect()
						try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
						ParsecBackgroundManager.shared.markForReconnect()
						DispatchQueue.main.async {
							self.disconnect(isBackgroundDisconnect: true)
						}
					}
				}
			}
			PictureInPictureManager.shared.onPiPStartFailed = {
				if UIApplication.shared.applicationState != .active {
					ParsecBackgroundManager.shared.glkViewController?.isPaused = true
					CParsec.sendReleaseMessage()
					CParsec.pause()
					ParsecBackgroundManager.shared.isPaused = true
					if UIApplication.shared.applicationState == .background {
						ParsecBackgroundManager.shared.holdSessionInBackground()
					}
				}
			}
		}

		CParsec.applyConfig()
		CParsec.setMuted(muted)
		if muted { CParsec.pause(video: false, audio: true) }
		parsecViewController.setZoomEnabled(zoomEnabled)

		DataManager.model.constantFps = SettingsHandler.constantFps

		let screenSize: CGSize = self.parsecViewController.view.frame.size
		let scaleFactor = parsecViewController.screenNativeScale
		ParsecResolution.updateClientResolution(width: Int(screenSize.width * scaleFactor), height: Int(screenSize.height * scaleFactor))

		ParsecView.getHostUserData()

		hideOverlay = SettingsHandler.noOverlay
		hideKeyboardButton = !SettingsHandler.showKeyboardButton
		parsecViewController.updateMenuEdgeSwipe(menuHidden: hideOverlay)
		offerHint()

		let overlayHidden = $hideOverlay
		let keyboardButtonHidden = $hideKeyboardButton
		let menuShown = $showMenu
		parsecViewController.onMenuEdgeSwipe = {
			overlayHidden.wrappedValue = false
			keyboardButtonHidden.wrappedValue = !SettingsHandler.showKeyboardButton
			menuShown.wrappedValue = true
			ParsecView.getHostUserData()
		}

        let keyboardShown = $showKeyboard
        parsecViewController.onKeyboardVisibilityChanged = { visible in
            keyboardShown.wrappedValue = visible
        }
		let hint = $hint
		let panHintShown = $keyboardPanHintShown
		parsecViewController.onKeyboardCoversPicture = {
			guard !panHintShown.wrappedValue else { return }
			panHintShown.wrappedValue = true
			withAnimation { hint.wrappedValue = "Part of the screen is under the keyboard\nDrag ↕\u{FE0E} to move it into view" }
			DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
				withAnimation { hint.wrappedValue = nil }
			}
		}

		parsecViewController.setKeyboardVisible(showKeyboard)
	}

	func openSettings() {
		decoderAtOpen = SettingsHandler.decoder
		fpsAtOpen = SettingsHandler.preferredFramesPerSecond
		pipAtOpen = SettingsHandler.enablePiP
		resolutionAtOpen = SettingsHandler.resolution
		bitrateAtOpen = SettingsHandler.bitrate
		showMenu = false
		if showKeyboard { toggleKeyboard() }
		showSettings = true
	}

	func applyStreamSettings() {
		zoomEnabled = SettingsHandler.zoomEnabled
		parsecViewController.setZoomEnabled(zoomEnabled)
		parsecViewController.updatePanHandle()
		parsecViewController.positionCursorOverlay()
		hideOverlay = SettingsHandler.noOverlay
		hideKeyboardButton = !SettingsHandler.showKeyboardButton
		parsecViewController.updateMenuEdgeSwipe(menuHidden: hideOverlay)
		offerHint()

		var hostConfigChanged = false
		if SettingsHandler.resolution != resolutionAtOpen {
			DataManager.model.resolutionX = SettingsHandler.resolution.width
			DataManager.model.resolutionY = SettingsHandler.resolution.height
			hostConfigChanged = true
		}
		if SettingsHandler.constantFps != DataManager.model.constantFps {
			DataManager.model.constantFps = SettingsHandler.constantFps
			hostConfigChanged = true
		}
		if hostConfigChanged { CParsec.updateHostVideoConfig() }
		if SettingsHandler.bitrate != bitrateAtOpen { applyBitrate() }
		if SettingsHandler.preferredFramesPerSecond != fpsAtOpen { parsecViewController.applyFrameRate() }
		if SettingsHandler.enablePiP != pipAtOpen {
			ParsecBackgroundManager.shared.reconnectPending = true
			disconnect()
		} else if SettingsHandler.decoder != decoderAtOpen {
			reconnectToApply()
		}
	}

	func reconnectToApply() {
		guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
		appNote("[reconnect] to apply settings")
		reconnectTo(peerId)
	}

	func reconnectTo(_ peerId: String) {
		isReconnecting = true
		ParsecBackgroundManager.shared.reconnectAttempts = 0
		parsecViewController.resetKeyState()
		CParsec.reconnect(peerId)
		ParsecBackgroundManager.shared.reconnectStartTime = Date()
	}

	func disableOverlay() {
		hideOverlay = true
		hideKeyboardButton = true
		showMenu = false
		parsecViewController.updateMenuEdgeSwipe(menuHidden: true)
		offerHint(always: true)
	}

	func offerHint(always: Bool = false) {
		let menu = hideOverlay && (always || !menuSwipeHintShown)
		let keyboard = hideKeyboardButton && (always || !keyboardHintShown)
		guard menu || keyboard else { return }
		if menu { menuSwipeHintShown = true }
		if keyboard { keyboardHintShown = true }
		let text = [menu ? "Swipe from the left edge for the menu" : nil, keyboard ? "Tap with three fingers to show or hide the keyboard" : nil].compactMap { $0 }.joined(separator: "\n")
		withAnimation { hint = text }
		DispatchQueue.main.asyncAfter(deadline: .now() + (menu && keyboard ? 6 : 4)) {
			withAnimation { hint = nil }
		}
	}

	func toggleMute() {
		muted.toggle()
		CParsec.setMuted(muted)
		if muted {
			CParsec.pause(video: false, audio: true)
		} else {
			CParsec.resume()
		}
	}

		/*func genDisplaySheet() -> ActionSheet
	{
		let len:Int = 16
		var outputs = [ParsecOutput?](repeating:nil, count:len)
		ParsecGetOutputs(&outputs, UInt32(len))
		print("Listing \(outputs.count) displays")

		func getDeviceName(_ output:ParsecOutput) -> String
		{
			return withUnsafePointer(to:output.device)
			{
				$0.withMemoryRebound(to: UInt8.self, capacity:MemoryLayout.size(ofValue:$0))
				{
					String(cString:$0)
				}
			}
		}

		let buttons = outputs.enumerated().map
		{ i, output in
			Alert.Button.default(Text("\(i) - \(getDeviceName(output))"), action:{print("Selected device \(i)")})
		}
		return ActionSheet(title: Text("Select a Display:"), buttons:buttons + [Alert.Button.cancel()])
	}*/

	func disconnect(isBackgroundDisconnect: Bool = false) {
		appNote("[stream] disconnect\(isBackgroundDisconnect ? " in the background" : "")")
		if !isBackgroundDisconnect {
			ParsecBackgroundManager.shared.endSession()
		}
		ParsecBackgroundManager.shared.onResumeEndedSession = nil
		ParsecBackgroundManager.shared.onEndedInBackground = nil
		ParsecBackgroundManager.shared.onNextFrame = nil

		PictureInPictureManager.shared.teardown()

		CParsec.sendReleaseMessage()
		CParsec.disconnect()
		DataManager.model.output = "none"
		CParsec.drawRate = 0
		self.parsecViewController.glkView.cleanUp()

		parsecViewController.scrollView.zoomScale = 1.0
		parsecViewController.scrollView.contentOffset = .zero

		if let c = controller {
			c.setView(.main)
		}
	}

	func changeResolution(res: ParsecResolution) {
        SettingsHandler.resolution = res
		DispatchQueue.main.async {
			DataManager.model.resolutionX = res.width
			DataManager.model.resolutionY = res.height
			CParsec.updateHostVideoConfig()
		}
	}

	func changeBitRate(bitrate: Int) {
		SettingsHandler.bitrate = bitrate
		applyBitrate()
	}

	func applyBitrate() {
		let target = SettingsHandler.bitrate > 0 ? SettingsHandler.bitrate : DataManager.model.hostDefaultBitrate
		guard target > 0, target != DataManager.model.bitrate else { return }
		DataManager.model.bitrate = target
		CParsec.updateHostVideoConfig()
	}

	func toggleConstantFps() {
		DispatchQueue.main.async {
			DataManager.model.constantFps.toggle()
			CParsec.updateHostVideoConfig()
			SettingsHandler.constantFps = DataManager.model.constantFps
		}
	}

	func toggleKeyboard() {
		DispatchQueue.main.async {
			showKeyboard.toggle()
			parsecViewController.setKeyboardVisible(showKeyboard)
		}
	}

	func toggleZoom() {
		DispatchQueue.main.async {
			zoomEnabled.toggle()
			parsecViewController.setZoomEnabled(zoomEnabled)
			SettingsHandler.zoomEnabled = zoomEnabled
		}
	}

	func toggleTouchMode() {
		DispatchQueue.main.async {
			SettingsHandler.cursorMode = SettingsHandler.cursorMode == .direct ? .touchpad : .direct
			parsecViewController.updatePanHandle()
		}
	}

	func changeDisplay(displayId: String) {
		DispatchQueue.main.async {
			DataManager.model.output = displayId
			CParsec.updateHostVideoConfig()
		}
	}

	static func getHostUserData() {
		let data = Data()
		CParsec.sendUserData(type: .getVideoConfig, message: data)
		CParsec.sendUserData(type: .getAdapterInfo, message: data)
	}

}
