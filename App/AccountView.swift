import AuthenticationServices
import SwiftUI

struct AccountView: View {
    var welcome = false
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var confirmImport = false
    @State private var confirmReplace = false
    @State private var showingDeletion = false

    var body: some View {
        NavigationStack {
            Group {
                if !account.initialized {
                    ProgressView(account.operationTitle)
                } else if account.user == nil {
                    LoginView(welcome: welcome)
                } else {
                    Form {
                        if account.needsLogin {
                            Section {
                                Label("기록을 백업하려면 다시 로그인해 주세요", systemImage: "person.crop.circle.badge.exclamationmark")
                                Text("운동 기록은 기기에 계속 저장돼요.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            AccountAuthenticationSection(deletion: false)
                        }
                        Section("내 계정") {
                            Label(account.user?.email ?? "로그인됨", systemImage: "person.crop.circle.fill")
                            LabeledContent("로그인 방법", value: account.accountProviders.map {
                                $0 == "email" ? "이메일" : (SocialProvider(rawValue: $0)?.title ?? $0)
                            }.joined(separator: ", "))
                        }
                        backupSection
                        Section {
                            Button("로그아웃") { confirmLogout = true }
                                .disabled(account.busy)
                            Button("계정 삭제", role: .destructive) {
                                account.clearMessage()
                                showingDeletion = true
                            }
                            .disabled(account.busy || !account.isOnline || account.needsLogin)
                            if account.needsLogin {
                                Text("계정 삭제는 다시 로그인한 뒤 이용할 수 있어요.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if !account.isOnline {
                                Text("계정 삭제는 인터넷 연결이 필요해요.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            AccountOperationFeedback(context: .management)
                        } header: { Text("계정 관리") } footer: { Text("로그아웃해도 계정 기록은 기기에 보관돼요. 같은 계정으로 다시 로그인하면 이어서 사용할 수 있어요.") }
                    }
                }
            }
            .navigationTitle(account.user == nil ? "" : "계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !welcome {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { account.closeAccountScreen(); dismiss() }
                            .disabled(account.blocksDismissal)
                    }
                }
            }
            .interactiveDismissDisabled(account.blocksDismissal)
            .sheet(isPresented: $showingDeletion, onDismiss: { account.cancelDeletion() }) {
                AccountDeletionView()
            }
            .confirmationDialog("기기 기록을 계정으로 가져올까요?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("가져오기") { Task { await account.importGuest() } }
            } message: { Text("원본을 보관하고 현재 계정에 추가합니다. 가져온 운동·일상 기록은 서버에 저장됩니다.") }
            .confirmationDialog("로그아웃할까요?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("로그아웃", role: .destructive) { Task { await account.signOut() } }
            } message: { Text("동기화되지 않은 기록도 기기에 보관하며, 같은 계정으로 다시 로그인한 뒤 확인할 수 있습니다.") }
            .confirmationDialog("서버 기록을 이 기기 기록으로 교체할까요?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("서버 기록 교체", role: .destructive) { Task { await account.resolveConflict(useCloud: false) } }
            } message: { Text("다른 기기의 변경을 대체합니다. 교체 전 서버 기록의 복구용 사본을 이 기기에 보관합니다.") }
            .onAppear { account.closeAccountScreen() }
            .onDisappear { if !showingDeletion { account.closeAccountScreen() } }
        }
    }

    private var backupSection: some View {
        Section {
            Label(account.modeDescription, systemImage: account.isOnline ? "icloud" : "wifi.slash")
            if let date = account.lastSyncedAt {
                LabeledContent("마지막 동기화", value: date.formatted(.dateTime.month().day().hour().minute()))
            } else {
                Text("아직 동기화한 기록이 없어요.").font(.footnote).foregroundStyle(.secondary)
            }
            Button("지금 동기화") { Task { await account.synchronize() } }
                .disabled(account.busy || !account.isOnline || account.needsLogin || account.conflict != nil)
            if account.canImport && account.hasGuestRecords {
                Button("이 기기의 게스트 기록 가져오기") { confirmImport = true }
                    .disabled(account.busy || account.needsLogin || account.conflict != nil)
            }
            if account.conflict != nil {
                Label("다른 기기의 기록을 확인해 주세요", systemImage: "exclamationmark.triangle")
                Text("서버 기록을 불러오면 현재 기기 기록은 복구용 사본으로 보관해요. 기기 기록으로 교체하면 다른 기기의 변경을 대체해요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("서버 기록 불러오기") { Task { await account.resolveConflict(useCloud: true) } }
                    .disabled(account.busy || !account.isOnline || account.needsLogin)
                Button("이 기기 기록으로 서버 교체", role: .destructive) { confirmReplace = true }
                    .disabled(account.busy || !account.isOnline || account.needsLogin)
            } else if account.needsLogin {
                Text("다시 로그인하면 백업을 이어서 진행해요.").font(.footnote).foregroundStyle(.secondary)
            } else if !account.isOnline {
                Text("인터넷에 연결되면 기기의 변경 사항을 자동으로 백업해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            AccountOperationFeedback(context: .backup)
        } header: { Text("기록 백업") } footer: { Text("연결이 끊겨도 운동·일상 기록은 이 기기에 계속 저장돼요.") }
    }
}

struct AccountOperationFeedback: View {
    @Environment(AccountModel.self) private var account
    let context: AccountMessageContext

    var body: some View {
        if account.messageContext == context {
            if account.busy { ProgressView(account.operationTitle) }
            if let message = account.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

struct AccountAuthenticationSection: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let deletion: Bool
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focusedCode: Bool

    var body: some View {
        Section {
            ForEach(SocialProvider.allCases) { provider in
                if account.accountProviders.contains(provider.rawValue) || !deletion {
                    Button("\(provider.title)로 \(deletion ? "본인 확인" : "다시 로그인")") {
                        Task {
                            await account.signIn(with: provider) { url in
                                try await webAuthenticationSession.authenticate(using: url,
                                    callbackURLScheme: AuthClient.callbackScheme, preferredBrowserSession: .ephemeral)
                            }
                        }
                    }.disabled(account.busy || !account.canSignIn(with: provider))
                    if account.isOnline && !account.canSignIn(with: provider) {
                        Text("\(provider.title) 로그인을 지금 사용할 수 없어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if account.canUseEmailForReauthentication {
                if let pending = account.pendingEmail {
                    Text(pending).font(.footnote).foregroundStyle(.secondary)
                    TextField("6자리 인증번호", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focusedCode)
                        .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                        .disabled(account.busy)
                    Button("인증번호 확인") {
                        let submitted = code
                        Task { await account.verify(code: submitted) }
                    }.disabled(account.busy || code.count != 6 || !account.isOnline)
                    AccountResendButton(email: pending)
                    if !deletion {
                        Button("이메일 다시 입력") { account.resetCode(); code = "" }
                            .disabled(account.busy)
                    }
                } else {
                    if deletion {
                        LabeledContent("확인할 이메일", value: account.user?.email ?? "")
                    } else {
                        TextField("이메일", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(account.busy)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = account.resendSeconds(at: context.date)
                        Button(seconds > 0 ? "인증번호 받기 · \(seconds)초 후" : "인증번호 받기") {
                            Task { await account.sendCode(email: deletion ? account.user?.email ?? "" : email,
                                                          createUser: false, consent: false) }
                        }.disabled(account.busy || !account.isOnline || seconds > 0 || (deletion ? account.user?.email?.isEmpty != false : email.isEmpty))
                    }
                }
            }
            if !account.isOnline {
                Text("인증하려면 인터넷에 연결해 주세요.").font(.footnote).foregroundStyle(.secondary)
            } else if !account.canUseEmailForReauthentication && !SocialProvider.allCases.contains(where: { account.canSignIn(with: $0) }) {
                Text("연결된 로그인 방법을 지금 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            AccountOperationFeedback(context: .authentication)
        } header: { Text(deletion ? "2. 본인 확인" : "다시 로그인") } footer: { Text(deletion ? "현재 계정에 연결된 방법으로 본인 확인을 해 주세요. 인증만으로 계정이 삭제되지는 않아요."
                                  : "기록 백업을 계속하려면 다시 로그인해 주세요.") }
        .onAppear { email = account.user?.email ?? "" }
        .onChange(of: account.pendingEmail) { _, pending in code = ""; focusedCode = pending != nil }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct AccountResendButton: View {
    @Environment(AccountModel.self) private var account
    let email: String
    var createUser = false
    var consent = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = account.resendSeconds(at: context.date)
            Button(seconds > 0 ? "다시 받기 · \(seconds)초 후" : "인증번호 다시 받기") {
                Task { await account.sendCode(email: email, createUser: createUser, consent: consent) }
            }.disabled(account.busy || !account.isOnline || seconds > 0)
        }
    }
}

struct AccountDeletionView: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(account.user?.email ?? "내 계정", systemImage: "person.crop.circle")
                    Text("계정과 서버의 운동·일상 기록, 이 기기의 계정 사본을 영구 삭제해요.")
                    Text("삭제한 기록은 되돌릴 수 없어요. 게스트 원본과 다른 기기의 오프라인 사본은 별도로 남을 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("1. 삭제 안내") }
                if !started {
                    Section {
                        Button("본인 확인으로 계속") { account.beginDeletion(); started = account.isDeleting }
                            .disabled(account.busy || !account.isOnline || account.needsLogin)
                        if !account.isOnline { Text("본인 확인은 인터넷 연결이 필요해요.").font(.footnote) }
                        if account.needsLogin { Text("계정 화면에서 다시 로그인한 뒤 진행해 주세요.").font(.footnote) }
                    }
                } else if account.readyToDelete {
                    Section {
                        Label("본인 확인을 마쳤어요", systemImage: "checkmark.shield")
                        Text("아래 버튼을 누르면 마지막으로 삭제 여부를 확인해요.").font(.footnote)
                        Button("계정 영구 삭제", role: .destructive) { confirmDelete = true }
                            .disabled(account.busy || !account.isOnline)
                        if !account.isOnline { Text("삭제하려면 인터넷에 연결해 주세요.").font(.footnote) }
                        AccountOperationFeedback(context: .authentication)
                    } header: { Text("3. 최종 확인") }
                } else {
                    AccountAuthenticationSection(deletion: true)
                }
            }
            .navigationTitle("계정 삭제").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { account.cancelDeletion(); dismiss() }.disabled(account.busy)
                }
            }
            .interactiveDismissDisabled(account.busy)
            .confirmationDialog("계정을 영구 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("계정 영구 삭제", role: .destructive) {
                    Task { await account.deleteAccount(); if account.user == nil { dismiss() } }
                }
            } message: { Text("계정과 서버 기록, 이 기기의 계정 사본이 삭제됩니다. 이 작업은 되돌릴 수 없습니다.") }
            .task {
                while !Task.isCancelled {
                    account.expireDeletionVerification()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                }
            }
            .onDisappear { account.cancelDeletion() }
        }
    }
}
