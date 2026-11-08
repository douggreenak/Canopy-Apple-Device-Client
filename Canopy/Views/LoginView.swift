import SwiftUI

// Port of web src/components/LoginScreen.tsx — sign-in / create-account with
// a show/hide password toggle and the register-mode password helper. Server
// errors ("Invalid username or password.") surface verbatim.
struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: max(geo.size.height * 0.1, 48))
                        iconView.padding(.bottom, 20)
                        titleView.padding(.bottom, 36)
                        formCard
                            .frame(maxWidth: 420)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 24)
                        toggleLink
                            .padding(.bottom, max(geo.size.height * 0.06, 32))
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.1), value: isRegistering)
        .animation(.easeInOut(duration: 0.18), value: errorMessage != nil)
    }

    // MARK: - Background
    @ViewBuilder
    private var background: some View {
        // Base: blur whatever is behind the window (wallpaper on iOS, desktop on macOS)
        Rectangle().fill(.ultraThinMaterial)
        #if os(macOS)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.06), Color.clear],
            startPoint: .topLeading, endPoint: .bottomCenter
        )
        #else
        // Decorative accent tint + ambient glow blobs
        LinearGradient(
            colors: [Color.accentColor.opacity(0.45), Color.clear],
            startPoint: .topLeading, endPoint: .center
        )
        Circle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 380)
            .blur(radius: 90)
            .offset(x: -40, y: -200)
            .allowsHitTesting(false)
        Circle()
            .fill(Color.accentColor.opacity(0.08))
            .frame(width: 260)
            .blur(radius: 60)
            .offset(x: 130, y: 240)
            .allowsHitTesting(false)
        #endif
    }

    // MARK: - Icon
    private var iconView: some View {
        CanopyIconView(size: 92)
    }

    // MARK: - Title
    private var titleView: some View {
        VStack(spacing: 6) {
            Text("Canopy")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                #if os(macOS)
                .foregroundStyle(.primary)
                #else
                .foregroundStyle(.white)
                #endif
            Text(isRegistering ? "Create an account to get started." : "Sign in to access your planner.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    // MARK: - Form Card
    private var formCard: some View {
        VStack(spacing: 12) {
            // Fields
            VStack(spacing: 0) {
                usernameRow
                Divider().padding(.leading, 52)
                passwordRow
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
            )

            if isRegistering {
                Text("Choose one you'll remember — there's no \"forgot password\" reset, but you can change it anytime from Settings once you're signed in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Error
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                    Text(err)
                        .font(.footnote)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.push(from: .top).combined(with: .opacity))
            }

            // Button
            submitButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 6)
        )
    }

    private var usernameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)
                .padding(.leading, 16)
            TextField("Username", text: $username)
                .textContentType(.username)
                .textAutocapNever()
                .autocorrectionDisabled()
                .focused($focused, equals: .username)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .disabled(authStore.isLoading)
                .padding(.vertical, 15)
                .padding(.trailing, 16)
        }
    }

    private var passwordRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)
                .padding(.leading, 16)
            PasswordField("Password", text: $password, isRevealed: $showPassword)
                .textContentType(isRegistering ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { Task { await submit() } } }
                .disabled(authStore.isLoading)
                .padding(.vertical, 15)
                .padding(.trailing, 16)
        }
    }

    private var submitButton: some View {
        Button {
            focused = nil
            Task { await submit() }
        } label: {
            Group {
                if authStore.isLoading {
                    ProgressView().tint(.white).controlSize(.regular)
                } else {
                    Text(isRegistering ? "Create Account" : "Sign In")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(canSubmit
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary.opacity(0.2)))
            )
            .shadow(
                color: canSubmit ? Color.accentColor.opacity(0.4) : .clear,
                radius: 12, y: 4
            )
        }
        .disabled(!canSubmit || authStore.isLoading)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    // MARK: - Toggle
    private var toggleLink: some View {
        Button {
            isRegistering.toggle()
            errorMessage = nil
            username = ""
            password = ""
            showPassword = false
        } label: {
            HStack(spacing: 4) {
                Text(isRegistering ? "Already have an account?" : "Don't have an account?")
                    .foregroundStyle(.secondary)
                Text(isRegistering ? "Sign In" : "Create Account")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .disabled(authStore.isLoading)
    }

    // MARK: - Action
    private func submit() async {
        errorMessage = nil
        guard canSubmit else { errorMessage = "Please enter a username and password."; return }
        do {
            if isRegistering {
                try await authStore.register(username: username, password: password)
            } else {
                try await authStore.login(username: username, password: password)
            }
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .timedOut || e.code == .cannotConnectToHost {
            errorMessage = "Network error. Please try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Password field with show/hide eye toggle (web Visibility adornment)
//
// Shared by Login, Change Password, Delete Account, PowerSchool and the
// Setup Wizard. Keeps a single text binding so toggling never loses input.
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    init(_ placeholder: String, text: Binding<String>, isRevealed: Binding<Bool>) {
        self.placeholder = placeholder
        self._text = text
        self._isRevealed = isRevealed
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .textAutocapNever()
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
    }
}

// Used in background gradient
private extension UnitPoint {
    static let bottomCenter = UnitPoint(x: 0.5, y: 1)
}
