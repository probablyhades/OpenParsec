import SwiftUI
import ParsecSDK

struct MainView: View {
	var controller: ContentView?

	@State private var page: Page = .hosts

	// Host page vars
	@State var hosts: [IdentifiableHostInfo] = []
	@State var hostsLoaded: Bool = false
	@State var lastRefresh: Date?

	// Friend page vars
	@State var userInfo: IdentifiableUserInfo?
	@State var friends: [IdentifiableUserInfo] = []
	@State var friendsLoaded: Bool = false
	@State var friendSearch: String = ""

	// Global vars
	@State var showBaseAlert: Bool = false
	@State var baseAlertText: String = ""

	@State var isConnecting: Bool = false
	@State var waitingForApproval: Bool = false
	@State var retryingConnect: Bool = false
	@State var connectPolls = 0
	@State var connectingToName: String = ""
	@State var pollTimer: Timer?
	@State var approvalStartedAt: Date?
	@State var connectStartedAt = Date()

	@State var isRefreshing: Bool = false
	@State var refreshError: String?

	@State var sessionExpired: Bool = false

	@State private var lastHostShown: String?

	@ObservedObject private var settings = SettingsStore.shared
	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	/// Tab bar on the outer display / compact width, sidebar on the inner display / regular width.
	/// On iPhone Duo the system moves the bars to the trailing edge; nothing here overrides that.
	var body: some View {
		ZStack {
			TabView(selection: $page) {
				Tab("Hosts", systemImage: "desktopcomputer", value: Page.hosts) {
					hostsTab
				}
				Tab("Friends", systemImage: "person.2.fill", value: Page.friends) {
					friendsTab
				}
				Tab("Settings", systemImage: "gear", value: Page.settings) {
					SettingsView(account: userInfo, onLogout: logout)
				}
			}
			.tabViewStyle(.sidebarAdaptable)
			.tabBarMinimizeBehavior(.onScrollDown)
			.disabled(isConnecting)

			if isConnecting {
				connectingOverlay
					.transition(.opacity)
			}
		}
		.alert(baseAlertText, isPresented: $showBaseAlert) {}
		.sensoryFeedback(.impact, trigger: isConnecting) { _, connecting in connecting }
		.onAppear(perform: initView)
		.onDisappear { ParsecBackgroundManager.shared.onShortcutReconnect = nil }
	}

	func refreshHostsAndWait() async {
		refreshHosts()
		while isRefreshing {
			try? await Task.sleep(for: .milliseconds(100))
		}
	}

	// MARK: Hosts

	var hostsTab: some View {
		NavigationStack {
			ScrollView(.vertical) {
				VStack(spacing: 12) {
					if sessionExpired {
						banner("Your Parsec session expired", systemImage: "person.crop.circle.badge.exclamationmark", tint: .orange, action: "Sign In", perform: logout)
					}
					if let refreshError = refreshError {
						banner(refreshError, systemImage: "exclamationmark.triangle.fill", tint: .yellow, action: "Retry", perform: refreshHosts)
					}
					if let lastHost = lastHostShown, !isConnecting {
						lastHostCard(lastHost)
					}
					if !hosts.isEmpty {
						sectionHeader("Available")
						LazyVGrid(columns: hostColumns, spacing: 12) {
							ForEach(hosts) { hostCard($0) }
						}
					} else if hostsLoaded {
						ContentUnavailableView {
							Label("No Hosts Online", systemImage: "desktopcomputer")
						} description: {
							Text("Open Parsec on a computer signed in to your account and it will show up here.")
						} actions: {
							Button("Refresh", action: refreshHosts)
								.buttonStyle(.bordered)
								.buttonBorderShape(.capsule)
						}
						.padding(.top, 32)
					} else if isRefreshing {
						ProgressView()
							.controlSize(.large)
							.padding(.top, 80)
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
				.padding(.bottom, 24)
				.animation(.snappy, value: hosts.map(\.id))
			}
			.refreshable { await refreshHostsAndWait() }
			.background(Color(.systemGroupedBackground))
			.navigationTitle("Hosts")
			.navigationSubtitle(hostsSubtitle)
			.toolbar {
				ToolbarItem(placement: .primaryAction) {
					Button(action: refreshHosts) { Label("Refresh", systemImage: "arrow.clockwise") }
						.disabled(isRefreshing)
						.keyboardShortcut("r", modifiers: .command)
				}
			}
		}
	}

	var hostsSubtitle: String {
		if isRefreshing { return "Refreshing…" }
		guard let lastRefresh = lastRefresh else { return "" }
		let count = "\(hosts.count) \(hosts.count == 1 ? "host" : "hosts")"
		return "\(count) · Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))"
	}

	/// Even column counts so cards divide cleanly around the iPhone Duo fold;
	/// driven by size class only, never by display dimensions.
	var hostColumns: [GridItem] {
		Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: horizontalSizeClass == .regular ? 2 : 1)
	}

	func sectionHeader(_ text: String) -> some View {
		Text(text)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 6)
			.padding(.top, 10)
			.accessibilityAddTraits(.isHeader)
	}

	func banner(_ text: String, systemImage: String, tint: Color, action: String, perform: @escaping () -> Void) -> some View {
		HStack(spacing: 12) {
			Image(systemName: systemImage)
				.font(.title3)
				.foregroundStyle(tint)
				.accessibilityHidden(true)
			Text(text)
				.font(.subheadline)
			Spacer(minLength: 8)
			Button(action, action: perform)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.fontWeight(.semibold)
		}
		.padding(.leading, 16)
		.padding(.trailing, 12)
		.padding(.vertical, 12)
		.card()
	}

	/// The fastest way back in: the one tinted card on the screen.
	func lastHostCard(_ lastHost: String) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack(alignment: .top) {
				VStack(alignment: .leading, spacing: 4) {
					Label("Last connected", systemImage: "clock.arrow.circlepath")
						.font(.footnote.weight(.semibold))
						.foregroundStyle(Color.accentColor)
					Text(lastHost)
						.font(.title2.bold())
						.lineLimit(2)
				}
				Spacer(minLength: 8)
				Menu {
					Toggle("Reconnect on App Launch", systemImage: "bolt", isOn: $settings.autoConnectOnLaunch)
					Button("Forget This Host", systemImage: "xmark", role: .destructive, action: clearLastHost)
				} label: {
					Image(systemName: "ellipsis")
						.font(.body.weight(.semibold))
						.frame(width: 44, height: 44)
						.contentShape(.rect)
				}
				.accessibilityLabel("Last host options")
				.padding(.top, -10)
				.padding(.trailing, -10)
			}
			Button(action: reconnectLastHost) {
				Label("Reconnect", systemImage: "play.fill")
					.fontWeight(.semibold)
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
		}
		.padding(18)
		.card(cornerRadius: 26, tint: .accentColor)
	}

	func hostCard(_ i: IdentifiableHostInfo) -> some View {
		HStack(spacing: 14) {
			Avatar(userID: i.user.id, name: i.user.name, size: 52)
			VStack(alignment: .leading, spacing: 3) {
				Text(i.hostname)
					.font(.headline)
					.lineLimit(2)
				Text("\(i.user.name)#\(String(i.user.id))")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				if i.connections > 0 {
					Label("\(i.connections) connected", systemImage: "person.fill")
						.font(.caption.weight(.medium))
						.foregroundStyle(.green)
						.padding(.top, 1)
				}
			}
			Spacer(minLength: 8)
			Button("Connect") { connectTo(i) }
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.capsule)
				.fontWeight(.semibold)
		}
		.padding(14)
		.card()
		.contentShape(.contextMenuPreview, .rect(cornerRadius: 22, style: .continuous))
		.contextMenu {
			Button("Connect", systemImage: "play") { connectTo(i) }
			Button("Copy Name", systemImage: "doc.on.doc") { UIPasteboard.general.string = i.hostname }
		}
	}

	// MARK: Friends

	var filteredFriends: [IdentifiableUserInfo] {
		let query = friendSearch.trimmingCharacters(in: .whitespaces)
		guard !query.isEmpty else { return friends }
		return friends.filter { $0.username.localizedCaseInsensitiveContains(query) || String($0.id).contains(query) }
	}

	var friendsTab: some View {
		NavigationStack {
			ScrollView(.vertical) {
				VStack(spacing: 10) {
					if let user = userInfo, friendSearch.isEmpty {
						sectionHeader("You")
						userRow(user)
					}
					if !filteredFriends.isEmpty {
						sectionHeader("Friends")
						LazyVGrid(columns: hostColumns, spacing: 10) {
							ForEach(filteredFriends) { userRow($0) }
						}
					} else if !friendSearch.isEmpty {
						ContentUnavailableView.search(text: friendSearch)
							.padding(.top, 32)
					} else if friendsLoaded {
						ContentUnavailableView("No Friends Yet", systemImage: "person.2", description: Text("Friends you add in Parsec appear here."))
							.padding(.top, 32)
					}
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 24)
			}
			.background(Color(.systemGroupedBackground))
			.navigationTitle("Friends")
			.navigationSubtitle(friendsLoaded ? "\(friends.count) \(friends.count == 1 ? "friend" : "friends")" : "")
			.searchable(text: $friendSearch, prompt: "Search friends")
		}
	}

	func userRow(_ user: IdentifiableUserInfo) -> some View {
		HStack(spacing: 12) {
			Avatar(userID: user.id, name: user.username, size: 44)
			Text(user.username)
				.font(.body.weight(.medium))
				.lineLimit(1)
			Spacer(minLength: 8)
			Text("#\(String(user.id))")
				.font(.subheadline)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.card(cornerRadius: 20)
		.accessibilityElement(children: .combine)
		.contentShape(.contextMenuPreview, .rect(cornerRadius: 20, style: .continuous))
		.contextMenu {
			Button("Copy Username", systemImage: "doc.on.doc") { UIPasteboard.general.string = "\(user.username)#\(user.id)" }
		}
	}

	// MARK: Connecting

	var connectingOverlay: some View {
		StatusOverlay(
			symbol: waitingForApproval ? "person.crop.circle.badge.clock" : "desktopcomputer",
			title: connectingToName,
			message: waitingForApproval ? "Waiting for the host to approve you…" : retryingConnect ? "No answer, trying again…" : "Requesting connection…",
			showLog: settings.showConnectionLog
		) {
			Button("Cancel", action: cancelConnection)
		}
	}

	func initView() {
		#if DEBUG
		if DemoData.enabled { // UI work without a Parsec account: launch with -demoData
			hosts = DemoData.hosts
			friends = DemoData.friends
			userInfo = DemoData.user
			lastHostShown = DemoData.hosts[0].hostname
			hostsLoaded = true
			friendsLoaded = true
			lastRefresh = Date()
			return
		}
		#endif
		lastHostShown = ParsecBackgroundManager.shared.lastPeerId != nil ? ParsecBackgroundManager.shared.lastHostname : nil
		refreshHosts()
		refreshSelf()
		refreshFriends()

		ParsecBackgroundManager.shared.onShouldReconnect = { peerId in
			if let host = hosts.first(where: { $0.id == peerId }) {
				connectTo(host)
			} else {
				refreshHosts()
			}
		}

		NetworkWatcher.shared.onReturn = {
			guard NetworkHandler.clinfo != nil, !ParsecBackgroundManager.shared.hasActiveConnection else { return }
			refreshHosts()
			refreshFriends()
		}
		NetworkWatcher.shared.start()

		ParsecBackgroundManager.shared.onShortcutReconnect = {
			if !isConnecting { reconnectLastHost() }
		}
		let pending = ParsecBackgroundManager.shared.reconnectPending
		ParsecBackgroundManager.shared.reconnectPending = false

		NetworkWatcher.shared.whenKnown {
			if (SettingsHandler.autoConnectOnLaunch && ParsecBackgroundManager.shared.resumeOnLaunch || pending) && !isConnecting && !ParsecBackgroundManager.shared.hasActiveConnection, ParsecBackgroundManager.shared.lastPeerId != nil {
				reconnectLastHost()
			}
		}
	}

	func reconnectLastHost() {
		guard let peerId = ParsecBackgroundManager.shared.lastPeerId else { return }
		let hostname = ParsecBackgroundManager.shared.lastHostname ?? peerId
		let user = UserInfo(id: 0, name: "", warp: false, team_id: "")
		let stub = IdentifiableHostInfo(id: peerId, hostname: hostname, user: user, connections: 0)
		appNote("[connect] last host from the saved id, host list \(hosts.isEmpty ? "not loaded yet" : "loaded")")
		connectTo(stub)
	}

	func clearLastHost() {
		ParsecBackgroundManager.shared.disableAutoReconnect()
		lastHostShown = nil
	}

	func refreshHosts() {
		guard !isRefreshing else { return }
		#if DEBUG
		if DemoData.enabled { return }
		#endif
		withAnimation {
			isRefreshing = true

			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				isRefreshing = false
				sessionExpired = true
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/v2/hosts?mode=desktop&public=false")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					defer { isRefreshing = false }

					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							refreshError = nil
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							sessionExpired = false
							guard let info: HostInfoList = try? decoder.decode(HostInfoList.self, from: data) else {
								refreshError = "Couldn't refresh hosts: bad response"
								return
							}
							refreshError = nil
							hosts.removeAll()
							if let datas = info.data {
								datas.forEach { h in
									hosts.append(IdentifiableHostInfo(id: h.peer_id, hostname: h.name, user: h.user, connections: h.players))
								}
							}
							if let lastId = ParsecBackgroundManager.shared.lastPeerId, let current = hosts.first(where: { $0.id == lastId }), current.hostname != ParsecBackgroundManager.shared.lastHostname {
								ParsecBackgroundManager.shared.lastHostname = current.hostname
								if lastHostShown != nil { lastHostShown = current.hostname }
							}

							hostsLoaded = true
							lastRefresh = Date()
						} else if statusCode == 403, let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) { // 403 Forbidden
							refreshError = "Couldn't refresh hosts: \(info.error)"
						} else {
							refreshError = "Couldn't refresh hosts (HTTP \(statusCode))"
						}
					} else {
						refreshError = "Can't reach Parsec"
					}
				}
			}
			task.resume()
		}
	}

	func refreshSelf() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/me")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let selfInfo = try? decoder.decode(SelfInfo.self, from: data) else { return }
							userInfo = IdentifiableUserInfo(id: selfInfo.data.id, username: selfInfo.data.name)
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = "Error gathering user info: \(info.error)"
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func refreshFriends() {
		withAnimation {
			let clinfo = NetworkHandler.clinfo
			if clinfo == nil {
				return
			}

			let apiURL = URL(string: "https://kessel-api.parsec.app/friendships")!

			var request = URLRequest(url: apiURL)
			request.httpMethod = "GET"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.setValue("Bearer \(clinfo!.session_id)", forHTTPHeaderField: "Authorization")
			request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")

			let task = URLSession.shared.dataTask(with: request) { (data, response, _) in
				DispatchQueue.main.async {
					if let data = data {
						guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return }
						if statusCode == 401 {
							sessionExpired = true
							return
						}
						let decoder = JSONDecoder()

						if statusCode == 200 { // 200 OK
							guard let info: FriendInfoList = try? decoder.decode(FriendInfoList.self, from: data) else { return }
							friends.removeAll()
							if let datas = info.data {
								datas.forEach { f in
									friends.append(IdentifiableUserInfo(id: f.user_id, username: f.user_name))
								}
							}
							friendsLoaded = true
						} else {
							guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else { return }

							baseAlertText = "Error gathering friends: \(info.error)"
							showBaseAlert = true
						}
					}
				}
			}
			task.resume()
		}
	}

	func connectTo(_ who: IdentifiableHostInfo, retried: Bool = false) {
		if NetworkWatcher.shared.noNetwork {
			appNote("[connect] no network, not trying")
			withAnimation {
				isConnecting = false
				waitingForApproval = false
				retryingConnect = false
			}
			baseAlertText = "No network connection"
			showBaseAlert = true
			return
		}

		if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
			let scale = window.screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(window.bounds.width * scale), height: Int(window.bounds.height * scale))
		} else {
			// no key window yet on a launch reconnect, without this it asks the host for 3840x2160
			let screen = UIScreen.main
			let scale = screen.nativeScale
			ParsecResolution.updateClientResolution(width: Int(screen.bounds.width * scale), height: Int(screen.bounds.height * scale))
		}

		pollTimer?.invalidate()
		pollTimer = nil
		CParsec.initialize()
		DataManager.model.reset()
		ParsecBackgroundManager.shared.reconnectAttempts = 0
		connectingToName = who.hostname
		retryingConnect = retried
		withAnimation { isConnecting = true }

		connectStartedAt = Date()
		let status = CParsec.connect(who.id)
		appNote("[connect] started, status \(status.rawValue)")
		connectPolls = 0
		approvalStartedAt = nil

		// Polling status
		pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
			MainActor.assumeIsolated {
				pollConnect(who)
			}
		}
	}

	func pollConnect(_ who: IdentifiableHostInfo) {
		let status = CParsec.getStatus()
		connectPolls += 1

		if let err = CParsec.setupError, err.at > connectStartedAt, status == PARSEC_CONNECTING || status == CONNECT_WRN_APPROVAL {
			CParsec.setupError = nil
			appNote("[connect] sdk setup failed after \(connectPolls) polls, retried \(retryingConnect): \(err.line)")
			retryOrGiveUp(who)
			return
		}

		if status == PARSEC_CONNECTING { return } // wait

		if status == CONNECT_WRN_APPROVAL {
			if approvalStartedAt == nil {
				appNote("[connect] status \(status.rawValue) after \(connectPolls) polls, retried \(retryingConnect)")
				if connectPolls >= 20 {
					retryOrGiveUp(who)
					return
				}
			}
			let started = approvalStartedAt ?? Date()
			approvalStartedAt = started
			if !waitingForApproval { withAnimation { waitingForApproval = true } }
			if Date().timeIntervalSince(started) < 60 { return }
		}

		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}
		appNote("[connect] result \(status.rawValue)")

		if status == PARSEC_OK {
			ParsecBackgroundManager.shared.connectionDidGoLive(peerId: who.id, hostname: hosts.first(where: { $0.id == who.id })?.hostname ?? who.hostname)
			if let c = controller {
				c.setView(.parsec)
			}
		} else {
			CParsec.disconnect()
			baseAlertText = status.readable(connecting: true)
			showBaseAlert = true
		}

		pollTimer?.invalidate()
	}

	func retryOrGiveUp(_ who: IdentifiableHostInfo) {
		pollTimer?.invalidate()
		CParsec.disconnect()
		if !retryingConnect {
			connectTo(who, retried: true)
			return
		}
		withAnimation {
			isConnecting = false
			retryingConnect = false
		}
		baseAlertText = "\(who.hostname) didn't answer the connection request"
		showBaseAlert = true
	}

	func cancelConnection() {
		appNote("[connect] cancelled")
		withAnimation {
			isConnecting = false
			waitingForApproval = false
			retryingConnect = false
		}

		CParsec.disconnect()

		pollTimer?.invalidate()
	}

	func logout() {
		removeFromKeychain(key: GLBDataModel.shared.SessionKeyChainKey)
		NetworkHandler.clinfo = nil
		ParsecBackgroundManager.shared.disableAutoReconnect()
		if let c = controller {
			c.setView(.login)
		}
	}

	func removeFromKeychain(key: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
		let status = SecItemDelete(query as CFDictionary)
		if status == errSecSuccess {
			print("Successfully removed data from keychain.")
		}
	}
}

#Preview {
	MainView(nil)
		.preferredColorScheme(.dark)
}

struct IdentifiableHostInfo: Identifiable {
	var id: String // Peer ID
	var hostname: String // Computer's Display Name
	var user: UserInfo // User Data
	var connections: Int // User's Connected To This Host
}

struct IdentifiableUserInfo: Identifiable {
	var id: Int // User ID
	var username: String // User Display Name
}

private enum Page {
	case hosts
	case friends
	case settings
}

#if DEBUG
enum DemoData {
	static let enabled = ProcessInfo.processInfo.arguments.contains("-demoData")

	static let user = IdentifiableUserInfo(id: 4821077, username: "nova")
	static let hosts = [
		IdentifiableHostInfo(id: "demo-1", hostname: "STUDIO-PC", user: UserInfo(id: 4821077, name: "nova", warp: false, team_id: ""), connections: 0),
		IdentifiableHostInfo(id: "demo-2", hostname: "Living Room Mac mini", user: UserInfo(id: 4821077, name: "nova", warp: false, team_id: ""), connections: 2),
		IdentifiableHostInfo(id: "demo-3", hostname: "render-node-04", user: UserInfo(id: 1930442, name: "kestrel", warp: false, team_id: ""), connections: 0)
	]
	static let friends = [
		IdentifiableUserInfo(id: 1930442, username: "kestrel"),
		IdentifiableUserInfo(id: 2204815, username: "Marlowe"),
		IdentifiableUserInfo(id: 907133, username: "juniper_fox"),
		IdentifiableUserInfo(id: 3310988, username: "Okonkwo")
	]
}
#endif
