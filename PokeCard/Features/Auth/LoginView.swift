//
//  LoginView.swift
//  PokeCard
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: AuthViewModel
    @State private var showSignUp = false

    // AppState is injected via the environment, but the view model needs it at
    // init time, so we build it lazily in onAppear-safe fashion.
    init() {
        // Placeholder; real wiring happens in `body` via `.task`.
        _vm = StateObject(wrappedValue: AuthViewModel(appState: AppState()))
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header

                    CuteCard {
                        VStack(spacing: 16) {
                            TextField("Email", text: $vm.email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textFieldStyle(CuteTextFieldStyle())

                            SecureField("Password", text: $vm.password)
                                .textFieldStyle(CuteTextFieldStyle())

                            if let error = vm.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                Task { await vm.signIn() }
                            } label: {
                                if vm.isBusy { ProgressView().tint(.white) }
                                else { Text("Log In") }
                            }
                            .buttonStyle(.cute)
                            .disabled(vm.isBusy)

                            OrDivider()

                            GoogleSignInButton {
                                Task { await vm.signInWithGoogle() }
                            }
                            .disabled(vm.isBusy)
                        }
                    }

                    signUpPrompt

                    guestButton
                }
                .padding(24)
            }
        }
        .task {
            // Rebind the view model to the real, environment-provided AppState.
            vm.rebind(to: appState)
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .environmentObject(appState)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            MascotBadge()
            Text("PokeCard")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Scan, collect & track your cards")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 24)
    }

    private var signUpPrompt: some View {
        HStack(spacing: 4) {
            Text("New trainer?")
                .foregroundStyle(Theme.textSecondary)
            Button("Create an account") { showSignUp = true }
                .fontWeight(.bold)
                .foregroundStyle(Theme.primary)
        }
        .font(.subheadline)
    }

    private var guestButton: some View {
        Button {
            appState.continueAsGuest()
        } label: {
            Text("Skip for now · Continue as guest")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .underline()
        }
        .padding(.top, 4)
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState(authService: PreviewAuthService()))
}
