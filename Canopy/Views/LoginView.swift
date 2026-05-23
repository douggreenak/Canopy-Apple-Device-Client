import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var username = ""
    @State private var password = ""
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
        #if os(macOS)
        Color.systemBackground
        LinearGradient(
            colors: [Color.accentColor.opacity(0.07), Color.clear],
            startPoint: .topLeading, endPoint: .bottomCenter
        )
        #else
        Color(uiColor: .systemBackground)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.55), Color.clear],
            startPoint: .topLeading, endPoint: .center
        )
        // Ambient glow blobs
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 380)
            .blur(radius: 90)
            .offset(x: -40, y: -200)
            .allowsHitTesting(false)
        Circle()
            .fill(Color.accentColor.opacity(0.10))
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
            Text("Your school planner")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Form Card
    private var formCard: some View {
        VStack(spacing: 12) {
            // Fields
            VStack(spacing: 0) {
                fieldRow(
                    systemImage: "person",
                    placeholder: "Username",
                    text: $username,
                    isSecure: false
                )
                Divider().padding(.leading, 52)
                fieldRow(
                    systemImage: "lock",
                    placeholder: "Password",
                    text: $password,
                    isSecure: true
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
            )

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
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 20, y: 6)
        )
    }

    @ViewBuilder
    private func fieldRow(systemImage: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)
                .padding(.leading, 16)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .textContentType(isRegistering ? .newPassword : .password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                } else {
                    TextField(placeholder, text: text)
                        .textContentType(.username)
                        .textAutocapNever()
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
            }
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
        } label: {
            HStack(spacing: 4) {
                Text(isRegistering ? "Already have an account?" : "Don't have an account?")
                    .foregroundStyle(.secondary)
                Text(isRegistering ? "Sign In" : "Create one")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action
    private func submit() async {
        errorMessage = nil
        do {
            if isRegistering {
                try await authStore.register(username: username, password: password)
            } else {
                try await authStore.login(username: username, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Used in background gradient
private extension UnitPoint {
    static let bottomCenter = UnitPoint(x: 0.5, y: 1)
}
