import SwiftUI
import os

struct LoginView: View {
	var controller: ContentView?

	@State var inputEmail: String = ""
	@State var inputPassword: String = ""
	@State var inputTFA: String = ""
	@State private var presentTFA = false
	@State var isLoading: Bool = false
	@State var errorText: String?
	@State private var failures = 0
	@FocusState private var focus: Field?

	private enum Field {
		case email, password, tfa
	}

	init(_ controller: ContentView?) {
		self.controller = controller
	}

	var canSubmit: Bool {
		!inputEmail.isEmpty && !inputPassword.isEmpty && !isLoading
	}

	var body: some View {
		GeometryReader { proxy in
			ScrollView {
				VStack(spacing: 28) {
					header
					VStack(spacing: 14) {
						fields
						if let errorText = errorText {
							Label(errorText, systemImage: "exclamationmark.circle.fill")
								.font(.footnote)
								.foregroundStyle(.red)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.horizontal, 4)
								.transition(.opacity.combined(with: .move(edge: .top)))
						}
						Button(action: { authenticate() }) {
							ZStack {
								Text("Sign In")
									.fontWeight(.semibold)
									.opacity(isLoading ? 0 : 1)
								if isLoading {
									ProgressView()
								}
							}
							.frame(maxWidth: .infinity)
						}
						.buttonStyle(.glassProminent)
						.controlSize(.extraLarge)
						.disabled(!canSubmit)
						.padding(.top, 6)
					}
					Text("Use your Parsec account. OpenParsec is an independent open-source client and is not affiliated with Parsec.")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				.padding(24)
				.frame(maxWidth: 440)
				.frame(maxWidth: .infinity, minHeight: proxy.size.height)
			}
			.scrollBounceBehavior(.basedOnSize)
			.scrollDismissesKeyboard(.interactively)
		}
		.background {
			ZStack {
				Color(.systemGroupedBackground)
				// one soft glow in the icon's own colour, so the mark sits in light rather than on a flat panel
				RadialGradient(colors: [Color.accentColor.opacity(0.32), .clear], center: UnitPoint(x: 0.5, y: 0.12), startRadius: 0, endRadius: 420)
			}
			.ignoresSafeArea()
		}
		.animation(.snappy, value: errorText)
		.sensoryFeedback(.error, trigger: failures)
		.sheet(isPresented: $presentTFA) { tfaSheet }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in retryRestore() }
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retryRestore() }
	}

	var header: some View {
		VStack(spacing: 4) {
			Image("IconTransparent")
				.resizable()
				.scaledToFit()
				.frame(width: 112, height: 112)
				.accessibilityHidden(true)
			Text("OpenParsec")
				.font(.system(.largeTitle, design: .rounded, weight: .bold))
			Text("Your computers, from anywhere")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
	}

	var fields: some View {
		VStack(spacing: 0) {
			TextField("Email", text: $inputEmail)
				.textContentType(.username)
				.keyboardType(.emailAddress)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.submitLabel(.next)
				.focused($focus, equals: .email)
				.onSubmit { focus = .password }
				.padding(.horizontal, 18)
				.frame(minHeight: 54)
			Divider()
				.padding(.leading, 18)
			SecureField("Password", text: $inputPassword)
				.textContentType(.password)
				.submitLabel(.go)
				.focused($focus, equals: .password)
				.onSubmit { if canSubmit { authenticate() } }
				.padding(.horizontal, 18)
				.frame(minHeight: 54)
		}
		.card(cornerRadius: 20)
		.disabled(isLoading)
	}

	var tfaSheet: some View {
		NavigationStack {
			VStack(spacing: 20) {
				Image(systemName: "lock.shield")
					.font(.system(size: 44))
					.symbolRenderingMode(.hierarchical)
					.foregroundStyle(Color.accentColor)
					.accessibilityHidden(true)
				Text("Enter the code from your authenticator app")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
				TextField("Code", text: $inputTFA)
					.font(.system(.title, design: .monospaced, weight: .semibold))
					.multilineTextAlignment(.center)
					.textContentType(.oneTimeCode)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.submitLabel(.go)
					.focused($focus, equals: .tfa)
					.onSubmit(submitTFA)
					.frame(minHeight: 60)
					.card(cornerRadius: 20)
				Button(action: submitTFA) {
					Text("Verify")
						.fontWeight(.semibold)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.glassProminent)
				.controlSize(.extraLarge)
				.disabled(inputTFA.isEmpty)
				Spacer(minLength: 0)
			}
			.padding(24)
			.navigationTitle("Two-Factor Authentication")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { presentTFA = false } label: { Label("Cancel", systemImage: "xmark") }
				}
			}
			.onAppear {
				inputTFA = ""
				focus = .tfa
			}
		}
		.presentationDetents([.medium])
		.preferredColorScheme(.dark)
	}

	func submitTFA() {
		guard !inputTFA.isEmpty else { return }
		presentTFA = false
		authenticate(inputTFA)
	}

	func fail(_ text: String) {
		errorText = text
		failures += 1
	}

	func retryRestore() {
		if !isLoading && !presentTFA, let c = controller {
			c.retryRestore()
		}
	}

	func saveToKeychain(data: Data, key: String) {
		SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess else {
			print("Error saving to Keychain: \(status)")
			return
		}
		print("Data saved to Keychain.")
	}

	func authenticate(_ tfa: String? = "") {
		#if DEBUG
		if inputEmail == "test@example.com" { // skip authentication (DEBUG ONLY)
			if let c = controller {
				c.setView(.main)
			}
			return
		}
		#endif

		focus = nil
		errorText = nil
		withAnimation { isLoading = true }

		let apiURL = URL(string: "https://kessel-api.parsec.app/v1/auth")!

		var request = URLRequest(url: apiURL)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("parsec/150-93b Windows/11 libmatoya/4.0", forHTTPHeaderField: "User-Agent")
		request.httpBody = try? JSONSerialization.data(withJSONObject:
		[
			"email": inputEmail,
			"password": inputPassword,
			"tfa": tfa
		], options: [])

		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			DispatchQueue.main.async {
				isLoading = false
				if let data = data {
					guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
						fail("Bad response from the server")
						return
					}
					let decoder = JSONDecoder()

					if statusCode == 201 { // 201 Created
						// store it and recover it from the next app opening, so people won't swear
						guard let info: ClientInfo = try? decoder.decode(ClientInfo.self, from: data) else {
							fail("Bad response from the server")
							return
						}
						NetworkHandler.clinfo = info

						saveToKeychain(data: data, key: GLBDataModel.shared.SessionKeyChainKey)

						if let c = controller {
							print("*** Login succeeded! ***")
							c.setView(.main)
						}
					} else if statusCode >= 400 { // 4XX client errors
						guard let info: ErrorInfo = try? decoder.decode(ErrorInfo.self, from: data) else {
							fail("Login failed (HTTP \(statusCode))")
							return
						}

						let json = try? JSONSerialization.jsonObject(with: data, options: [])
						if let dict = json as? [String: Any], let isTFARequired = dict["tfa_required"] as? Bool {
							print("Code output:")
							print(dict)
							if isTFARequired {
								presentTFA = true
							} else {
								fail("Error: \(info)")
							}
						} else {
							fail(info.error)
						}
					} else {
						fail("Login failed (HTTP \(statusCode))")
					}
				} else {
					fail(error?.localizedDescription ?? "Could not reach the server")
				}
			}
		}
		task.resume()
	}
}

#Preview {
	LoginView(nil)
		.preferredColorScheme(.dark)
}
