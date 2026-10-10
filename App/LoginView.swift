import AuthenticationServices
import SwiftUI

/// Provider selection and email OTP share the existing account/session implementation.
/// Google/Apple run in the system authentication browser (ASWebAuthenticationSession) with PKCE.
struct LoginView: View {
    var welcome = false
    @Environment(AccountModel.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var showingEmail = false
    @State private var email = ""
    @State private var code = ""
    @State private var createUser = false
    @State private var consent = false
    @State private var importDeviceRecords = false
    @FocusState private var focusedField: Field?
    private enum Field { case email, code }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                if showingEmail { emailForm.disabled(account.busy) }
                else { providers.disabled(account.busy) }
                if account.messageContext != .backup, let message = account.message {
                    Text(message)
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if account.busy { ProgressView(account.operationTitle) }
                if welcome {
                    Button("로그인 없이 시작") { account.continueAsGuest() }
                        .disabled(account.busy)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                Label("연결이 끊겨도 기록은 기기에 안전하게 보관돼요", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .disabled(!account.initialized)
        .onChange(of: account.pendingEmail) { _, pending in
            code = ""
            focusedField = pending == nil ? .email : .code
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 76, height: 76)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(showingEmail ? (account.pendingEmail == nil ? "이메일로 시작하기" : "메일함을 확인해 주세요") : "헬스노트")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(showingEmail ? "비밀번호 없이, 이메일 인증번호로 간편하게." : "오늘의 운동과 일상,\n내 계정으로 계속 이어가세요.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var providers: some View {
        VStack(spacing: 14) {
            providerButton(.apple, symbol: "apple.logo")
            providerButton(.google, symbol: nil)
            HStack(spacing: 16) {
                Rectangle().frame(height: 1)
                Text("또는").font(.caption).fixedSize()
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(.secondary.opacity(0.4))
            .padding(.vertical, 4)
            Button {
                showingEmail = true
                focusedField = .email
            } label: {
                Label("이메일로 계속하기", systemImage: "envelope")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(!account.configured)
            if account.hasGuestRecords && account.configured { importToggle }
            Text(providerFootnote)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 4)
        }
    }

    private var providerFootnote: String {
        if !account.configured { return "계정 연결을 준비 중이에요. 기기 기록은 계속 이용할 수 있어요." }
        if !account.isOnline { return "로그인하려면 인터넷에 연결해 주세요. 기기 기록은 계속 이용할 수 있어요." }
        let ready = SocialProvider.allCases.filter { account.canSignIn(with: $0) }.map(\.title)
        let pending = SocialProvider.allCases.filter { !account.canSignIn(with: $0) }.map(\.title)
        if pending.isEmpty { return "\(ready.joined(separator: "·")) 로그인 창은 시스템 인증 화면으로 열려요." }
        return "\(pending.joined(separator: "·")) 로그인은 준비 중이에요.\n지금은 \((ready + ["이메일"]).joined(separator: "·"))로 시작할 수 있어요."
    }

    private func providerButton(_ provider: SocialProvider, symbol: String?) -> some View {
        let ready = account.canSignIn(with: provider)
        return Button {
            let importRecords = importDeviceRecords
            Task {
                await account.signIn(with: provider, importDeviceRecords: importRecords) { url in
                    try await webAuthenticationSession.authenticate(
                        using: url, callbackURLScheme: AuthClient.callbackScheme, preferredBrowserSession: .ephemeral)
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).font(.title3) }
                else { Text("G").font(.title3.bold()).accessibilityHidden(true) }
                Text("\(provider.title)로 계속하기").font(.body.weight(.semibold))
                Spacer(minLength: 4)
                if !ready {
                    Text(account.isOnline ? "준비 중" : "인터넷 필요")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(ready ? Color.primary : Color.secondary)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityHint(ready ? "시스템 인증 화면에서 \(provider.title) 계정으로 로그인합니다" : "아직 사용할 수 없는 로그인 방식입니다")
    }

    private var importToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("이 기기의 기록도 이어서 저장", isOn: $importDeviceRecords)
                .font(.subheadline.weight(.medium)).tint(.orange)
            Text("동의하면 운동·일상 기록을 계정에 추가해요. 원본은 보관하고, 연결이 끊기면 다음 연결 때 다시 저장해요. 동의하지 않으면 가져오지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let pending = account.pendingEmail {
                Text("\(pending)로 보낸 6자리 인증번호를 입력해 주세요.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("6자리 인증번호", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
                    .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                    .loginInput()
                primaryButton("확인하고 시작하기", disabled: code.count != 6 || !account.isOnline) {
                    let submitted = code
                    let importRecords = importDeviceRecords
                    focusedField = nil
                    Task { await account.verify(code: submitted, importDeviceRecords: importRecords) }
                }
                AccountResendButton(email: pending, createUser: createUser, consent: consent)
                Button("다른 이메일 사용") { account.resetCode() }.disabled(account.busy)
            } else {
                Picker("이메일 계정", selection: $createUser) {
                    Text("로그인").tag(false)
                    Text("회원가입").tag(true)
                }.pickerStyle(.segmented)
                TextField("이메일 주소", text: $email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.continue)
                    .loginInput()
                if createUser {
                    Toggle("이메일을 계정 인증에 사용하는 데 동의해요", isOn: $consent)
                        .font(.subheadline).tint(.orange)
                    Text("가입 후 계정의 기록은 서버에 저장됩니다. 기존 기기 기록은 아래에서 동의한 경우에만 가져옵니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = account.resendSeconds(at: context.date)
                    primaryButton(seconds > 0 ? "인증번호 받기 · \(seconds)초 후" : "인증번호 받기",
                                  disabled: !account.isOnline || email.isEmpty || (createUser && !consent) || seconds > 0) {
                        focusedField = nil
                        Task { await account.sendCode(email: email, createUser: createUser, consent: consent) }
                    }
                }
            }
            if account.hasGuestRecords { importToggle }
            if !account.isOnline {
                Label("인증번호를 받으려면 인터넷에 연결해 주세요", systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                account.resetCode()
                showingEmail = false
                focusedField = nil
            } label: {
                Label("다른 방법으로 로그인", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity).padding(.top, 6)
        }
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent).tint(.orange)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(disabled)
    }
}

private extension View {
    func loginInput() -> some View {
        self.padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1), lineWidth: 1))
    }
}

#Preview("로그인 선택") {
    let model = AppModel(previewData: .sample)
    LoginView(welcome: true)
        .environment(model.account)
}
