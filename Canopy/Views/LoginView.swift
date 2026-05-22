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
        ZStack {
            // Liquid glass background gradient
            LinearGradient(
                colors: [Color.canopyGreenDark.opacity(0.55), Color(hex: "#0a1f0b")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glass orbs for depth
            Circle()
                .fill(Color.canopyGreen.opacity(0.25))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: -80, y: -160)

            Circle()
                .fill(Color(hex: "#1B5E20").opacity(0.3))
                .frame(width: 250, height: 250)
                .blur(radius: 50)
                .offset(x: 120, y: 200)

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, max(60, geo.size.height * 0.12))
                            .padding(.bottom, 40)
                        formCard
                            .padding(.horizontal, 24)
                        Spacer(minLength: 32)
                        toggleButton.padding(.bottom, 40)
                    }
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRegistering)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "tree.fill")
                .font(.system(size: 76))
                .foregroundStyle(
                    LinearGradient(colors: [.canopyGreen, Color(hex: "#66BB6A")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .canopyGreen.opacity(0.6), radius: 20)
                .symbolEffect(.pulse, options: .repeating)
            Text("Canopy")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Your school planner")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Form card
    private var formCard: some View {
        VStack(spacing: 14) {
            // Fields in a single glass pill
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "person").foregroundStyle(.secondary).frame(width: 20)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .foregroundStyle(.primary)
                }
                .padding(14)

                Divider().opacity(0.2)

                HStack {
                    Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 20)
                    SecureField("Password", text: $password)
                        .textContentType(isRegistering ? .newPassword : .password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                }
                .padding(14)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5))

            // Error
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                }
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Submit
            Button {
                focused = nil
                Task { await submit() }
            } label: {
                ZStack {
                    if authStore.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(isRegistering ? "Create Account" : "Sign In")
                            .font(.headline).foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(colors: [Color.canopyGreen, Color.canopyGreenDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .canopyGreen.opacity(0.4), radius: 12, y: 4)
            }
            .disabled(!canSubmit || authStore.isLoading)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Toggle
    private var toggleButton: some View {
        Button {
            isRegistering.toggle()
            errorMessage = nil
        } label: {
            Group {
                if isRegistering {
                    Text("Already have an account? ") + Text("Sign In").bold()
                } else {
                    Text("Don't have an account? ") + Text("Create one").bold()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
        }
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
