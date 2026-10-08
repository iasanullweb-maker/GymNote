import SwiftUI

struct AccountView: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var code = ""
    @State private var createUser = false
    @State private var consent = false
    @State private var confirmLogout = false
    @State private var confirmImport = false
    @State private var confirmDelete = false
    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = account.user {
                    Section("내 계정") {
                        Label(user.email ?? "로그인됨", systemImage: "person.crop.circle.fill")
                        Text(account.syncStatus).font(.footnote).foregroundStyle(.secondary)
                        Button("지금 동기화") { Task { await account.synchronize() } }
                            .disabled(account.needsLogin || account.isReauthenticating || account.conflict != nil)
                        if account.canImport {
                            Button("이 기기의 게스트 기록 가져오기") { confirmImport = true }
                                .disabled(account.needsLogin || account.isReauthenticating || account.conflict != nil)
                        }
                        Button("로그아웃", role: .destructive) { confirmLogout = true }
                    }
                } else {
                    Section {
                        Label("로그인 없이도 운동할 수 있어요", systemImage: "iphone")
                        Text("현재 기록은 이 기기에 저장됩니다. 로그인하면 내 계정으로 기록을 백업하고 다른 기기에서 복원할 수 있어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !account.configured {
                    Section { Text("계정 연결을 준비 중입니다. 지금은 기기에 기록을 저장할 수 있어요.").foregroundStyle(.secondary) }
                } else if account.user == nil || account.isReauthenticating {
                    loginSection
                }

                if account.conflict != nil {
                    Section("다른 기기에서 기록이 바뀌었어요") {
                        Text("자동 덮어쓰기를 멈췄어요. 서버 기록을 불러오면 현재 기기의 기록은 복구용 사본으로 보관합니다. 이 기기 기록으로 교체하면 다른 기기의 변경이 서버에서 대체됩니다.")
                            .font(.footnote)
                        Button("서버 기록 불러오기") { Task { await account.resolveConflict(useCloud: true) } }
                        Button("이 기기 기록으로 서버 교체", role: .destructive) { confirmReplace = true }
                    }
                }

                if let message = account.message {
                    Section { Text(message).font(.footnote).accessibilityLabel(message) }
                }
                if account.busy { Section { ProgressView("처리 중…") } }

                if account.user != nil {
                    Section {
                        if account.readyToDelete {
                            Button("계정과 서버 기록 영구 삭제", role: .destructive) { confirmDelete = true }
                        } else if !account.isReauthenticating {
                            Button("계정 삭제를 위한 본인 확인", role: .destructive) {
                                email = account.user?.email ?? ""
                                code = ""
                                createUser = false
                                account.beginDeletion()
                            }
                        }
                        if account.isReauthenticating && !account.needsLogin {
                            Button("계정 삭제 취소", role: .cancel) { account.cancelDeletion(); code = "" }
                        }
                    } footer: {
                        Text("로그아웃하면 계정 기록은 숨겨지고 게스트 기록으로 돌아갑니다. 계정 삭제는 서버 기록과 이 기기의 계정 사본을 삭제합니다.")
                    }
                }
            }
            .disabled(account.busy || !account.initialized)
            .navigationTitle("계정")
            .confirmationDialog("기기 기록을 계정으로 가져올까요?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("가져오기") { Task { await account.importGuest() } }
            } message: { Text("원본을 보관하고 현재 계정에 추가합니다. 가져온 운동 기록은 서버에 저장됩니다.") }
            .confirmationDialog("로그아웃할까요?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("로그아웃", role: .destructive) { Task { await account.signOut() }; code = "" }
            } message: { Text("동기화되지 않은 기록도 기기에 보관하며, 같은 계정으로 다시 로그인한 뒤 확인할 수 있습니다.") }
            .confirmationDialog("서버 기록을 이 기기 기록으로 교체할까요?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("서버 기록 교체", role: .destructive) { Task { await account.resolveConflict(useCloud: false) } }
            } message: { Text("다른 기기의 변경을 대체합니다. 교체 전 서버 기록의 복구용 사본을 이 기기에 보관합니다.") }
            .confirmationDialog("계정을 영구 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("계정 영구 삭제", role: .destructive) { Task { await account.deleteAccount() }; code = "" }
            } message: { Text("계정, 서버의 운동 기록, 이 기기의 계정 사본이 삭제됩니다. 다른 기기의 오프라인 사본과 게스트 원본 기록은 별도로 남을 수 있습니다.") }
            .onChange(of: account.pendingEmail) { _, _ in code = "" }
        }
    }

    private var loginSection: some View {
        Section(account.isReauthenticating ? "본인 확인" : "이메일로 로그인") {
            if let pending = account.pendingEmail {
                Text(pending).font(.footnote).foregroundStyle(.secondary)
                TextField("6자리 인증번호", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                Button("인증번호 확인") {
                    let submitted = code
                    code = ""
                    Task { await account.verify(code: submitted) }
                }
                    .disabled(code.count != 6)
                Button("인증번호 다시 받기") { Task { await account.sendCode(email: pending, createUser: createUser, consent: consent) } }
                Button("이메일 다시 입력") { account.resetCode(); code = "" }
            } else {
                TextField("이메일", text: $email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !account.isReauthenticating {
                    Toggle("처음 사용해요 · 새 계정 만들기", isOn: $createUser)
                    if createUser {
                        Toggle("이메일을 계정 인증에 사용하는 데 동의합니다", isOn: $consent)
                        Text("로그인 후 해당 계정에서 만드는 운동 기록은 Supabase 서버에 저장됩니다. 기존 게스트 기록은 가져오기를 선택할 때만 업로드됩니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("인증번호 받기") {
                    Task { await account.sendCode(email: email, createUser: createUser, consent: consent) }
                }
                .disabled(email.isEmpty || (createUser && !consent))
            }
        } footer: {
            Text("비밀번호 없이 일회용 이메일 인증번호로 로그인합니다. 인증번호는 누구에게도 알려주지 마세요.")
        }
    }
}
