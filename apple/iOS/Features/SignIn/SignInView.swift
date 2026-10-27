import SwiftUI
import GymaCore

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var key = ""
    @State private var server = TokenStore.server.absoluteString
    @State private var showServer = false
    @State private var error: String?
    @State private var signingIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Training planner")
                    .font(.title.weight(.semibold))
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal access key").font(.subheadline)
                    SecureField("", text: $key)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .inputField()
                }

                DisclosureGroup("Server", isExpanded: $showServer) {
                    TextField("https://", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .inputField()
                        .padding(.top, 8)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

                if let error { ErrorBanner(message: error) }

                Button(action: submit) {
                    Text(signingIn ? "Signing in…" : "Sign in")
                }
                .buttonStyle(.primary)
                .disabled(signingIn || key.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("Use the API_TOKEN value of your Cloudflare Worker. It is stored in this iPhone’s Keychain.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 72)
        }
        .screenBackground()
    }

    private func submit() {
        guard !signingIn else { return }
        signingIn = true; error = nil
        Task {
            error = await model.signIn(key: key, server: server)
            signingIn = false
            if error == nil { key = "" }
        }
    }
}
