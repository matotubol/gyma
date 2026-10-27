import SwiftUI
import GymaCore

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var key = ""
    @State private var server = TokenStore.server.absoluteString
    @State private var error: String?
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Access key", text: $key)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    Text("The API_TOKEN of your Cloudflare Worker. It is stored in this iPhone’s Keychain.")
                }

                Section("Server") {
                    TextField("https://", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Text("Sign In")
                            if signingIn { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(signingIn || key.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Gyma")
        }
    }

    private func submit() {
        guard !signingIn, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        signingIn = true; error = nil
        Task {
            error = await model.signIn(key: key, server: server)
            signingIn = false
            if error == nil { key = "" }
        }
    }
}
