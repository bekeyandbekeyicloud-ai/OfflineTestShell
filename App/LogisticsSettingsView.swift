import SwiftUI

struct LogisticsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customer = ""
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("快递100授权") {
                    TextField("customer", text: $customer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("授权 key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("授权 key 只保存在本机 Keychain，不会写入货物数据库，也不会上传到 GitHub。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("自动查询") {
                    Label("进入货物主页时会检查需要刷新的运单", systemImage: "arrow.clockwise")
                    Text("同一运单自动查询间隔不少于 30 分钟。顺丰、中通等需要手机号验证的运单，请在货物编辑页填写查询手机号或尾号。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if saved {
                    Section { Label("已保存到本机", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("物流设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        CredentialStore.customer = customer.trimmingCharacters(in: .whitespacesAndNewlines)
                        CredentialStore.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                    }
                    .disabled(customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                customer = CredentialStore.customer
                key = CredentialStore.apiKey
            }
        }
    }
}
