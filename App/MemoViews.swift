import SwiftUI

struct MemoListView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var showingNew = false
    @State private var searchText = ""

    private var filtered: [Memo] {
        store.memos
            .filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.body.localizedCaseInsensitiveContains(searchText) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    EmptyStateView(title: "暂无备忘", systemImage: "note.text", message: "点右上角 + 记录信息")
                } else {
                    ForEach(filtered) { memo in
                        NavigationLink {
                            MemoDetailView(memoID: memo.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    if memo.isPinned { Image(systemName: "pin.fill").foregroundColor(.orange) }
                                    Text(memo.title.isEmpty ? "未命名备忘" : memo.title).font(.headline)
                                }
                                if !memo.body.isEmpty {
                                    Text(memo.body).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                                }
                                Text(memo.updatedAt.displayDateTime).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(store.deleteMemo)
                    }
                }
            }
            .navigationTitle("离线备忘录")
            .searchable(text: $searchText, prompt: "搜索备忘")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) { MemoEditorView(existing: nil) }
        }
    }
}

struct MemoDetailView: View {
    @EnvironmentObject private var store: LocalStore
    let memoID: UUID
    @State private var showingEdit = false

    private var memo: Memo? { store.memos.first { $0.id == memoID } }

    var body: some View {
        Group {
            if let memo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(memo.body.isEmpty ? "（无正文）" : memo.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        Text("最后更新：\(memo.updatedAt.displayDateTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .navigationTitle(memo.title.isEmpty ? "备忘" : memo.title)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) { Button("编辑") { showingEdit = true } }
                }
                .sheet(isPresented: $showingEdit) { MemoEditorView(existing: memo) }
            } else {
                EmptyStateView(title: "备忘不存在", systemImage: "exclamationmark.triangle", message: "这条记录可能已被删除")
            }
        }
    }
}

struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LocalStore
    let existing: Memo?
    @State private var title: String
    @State private var bodyText: String
    @State private var pinned: Bool

    init(existing: Memo?) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _bodyText = State(initialValue: existing?.body ?? "")
        _pinned = State(initialValue: existing?.isPinned ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                Toggle("置顶", isOn: $pinned)
                Section("正文") {
                    TextEditor(text: $bodyText).frame(minHeight: 260)
                }
            }
            .navigationTitle(existing == nil ? "新建备忘" : "编辑备忘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if var memo = existing {
                            memo.title = title
                            memo.body = bodyText
                            memo.isPinned = pinned
                            memo.updatedAt = Date()
                            if let index = store.memos.firstIndex(where: { $0.id == memo.id }) {
                                store.memos[index] = memo
                            }
                        } else {
                            store.addMemo(Memo(title: title, body: bodyText, createdAt: Date(), updatedAt: Date(), isPinned: pinned))
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
