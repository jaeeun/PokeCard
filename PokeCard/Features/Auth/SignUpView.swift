//
//  SignUpView.swift
//  PokeCard
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: AuthViewModel

    init() {
        _vm = StateObject(wrappedValue: AuthViewModel(appState: AppState()))
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        MascotBadge(size: 76)
                        Text("Create your account")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.top, 12)

                    CuteCard(tint: Theme.secondary) {
                        VStack(spacing: 16) {
                            TextField("Display name (optional)", text: $vm.displayName)
                                .textFieldStyle(CuteTextFieldStyle())

                            TextField("Email", text: $vm.email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textFieldStyle(CuteTextFieldStyle())

                            SecureField("Password (min 6 chars)", text: $vm.password)
                                .textFieldStyle(CuteTextFieldStyle())

                            SecureField("Confirm password", text: $vm.confirmPassword)
                                .textFieldStyle(CuteTextFieldStyle())

                            if let error = vm.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                Task { await vm.signUp() }
                            } label: {
                                if vm.isBusy { ProgressView().tint(.white) }
                                else { Text("Sign Up") }
                            }
                            .buttonStyle(.cute(fill: Theme.secondary))
                            .disabled(vm.isBusy)
                        }
                    }

                    Button("I already have an account") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(24)
            }
        }
        .task { vm.rebind(to: appState) }
        .onChange(of: appState.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(AppState(authService: PreviewAuthService()))
}
