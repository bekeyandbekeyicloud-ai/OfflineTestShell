import SwiftUI

struct SheetsView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var model: SheetEditorModel

    private let rowHeaderWidth: CGFloat = 46
    private let cellWidth: CGFloat = 112
    private let cellHeight: CGFloat = 40
    @State private var gridMinX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.isLoading {
                Spacer()
                ProgressView(value: model.loadingProgress) { Text("正在读取完整表格与色块…") }
                    .progressViewStyle(.linear).padding(32)
                Spacer()
            } else if let error = model.errorMessage, model.sheets.isEmpty {
                errorView(error)
            } else {
                sheetPicker
                continuousGrid
                statusBar
            }
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .task { if model.sheets.isEmpty { await model.loadMetadata() } }
    }

    private var toolbar: some View {
        HStack {
            Image(systemName: "tablecells")
            Text(model.documentTitle.isEmpty ? "表格" : model.documentTitle).font(.headline).lineLimit(1)
            Spacer()
            Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading)
            Button { session.lock() } label: { Image(systemName: "lock.fill") }
        }
        .padding(.horizontal, 16).frame(height: 48).foregroundStyle(.white).background(Color.black)
    }

    private var sheetPicker: some View {
        Picker("工作表", selection: Binding(
            get: { model.selectedSheetIndex },
            set: { index in Task { await model.selectSheet(at: index) } }
        )) {
            ForEach(Array(model.sheets.enumerated()), id: \.offset) { index, sheet in
                Text(sheet.name).tag(index)
            }
        }
        .pickerStyle(.menu).tint(.green).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).frame(height: 42).background(Color(white: 0.13))
    }

    private var continuousGrid: some View {
        GeometryReader { outer in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(model.rowIndices, id: \.self) { row in
                            HStack(spacing: 0) {
                                gridHeader(String(row), width: rowHeaderWidth)
                                    .offset(x: max(0, -gridMinX)).zIndex(2)
                                ForEach(model.columnIndices, id: \.self) { column in
                                    let style = model.cell(row: row, column: column)
                                    CellEditor(
                                        value: model.binding(row: row, column: column),
                                        background: Color(hex: style.background),
                                        foreground: Color(hex: style.foreground),
                                        width: cellWidth,
                                        height: cellHeight,
                                        save: { value in await model.update(row: row, column: column, value: value) }
                                    )
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            gridHeader("", width: rowHeaderWidth)
                                .offset(x: max(0, -gridMinX)).zIndex(4)
                            ForEach(model.columnIndices, id: \.self) { column in
                                gridHeader(model.columnName(column), width: cellWidth)
                            }
                        }
                        .zIndex(3)
                    }
                }
                .frame(minWidth: outer.size.width, alignment: .topLeading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: GridXPreferenceKey.self,
                                           value: proxy.frame(in: .named("sheetGrid")).minX)
                })
            }
            .coordinateSpace(name: "sheetGrid")
            .onPreferenceChange(GridXPreferenceKey.self) { gridMinX = $0 }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white)
        }
    }

    private func gridHeader(_ text: String, width: CGFloat) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(.secondary).frame(width: width, height: 34)
            .background(Color(white: 0.92)).overlay(Rectangle().stroke(Color(white: 0.76), lineWidth: 0.5))
    }

    private var statusBar: some View {
        HStack {
            if model.isSaving { ProgressView().controlSize(.small); Text("正在保存…") }
            else if let error = model.errorMessage { Image(systemName: "exclamationmark.circle"); Text(error) }
            else { Image(systemName: "checkmark.circle"); Text("连续滑动 · 色块已同步") }
            Spacer()
        }
        .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
        .padding(.horizontal, 12).frame(height: 34).background(Color(white: 0.95))
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("无法读取表格").font(.headline)
            Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("重试") { Task { await model.loadMetadata() } }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

private struct GridXPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CellEditor: View {
    @Binding var value: String
    let background: Color
    let foreground: Color
    let width: CGFloat
    let height: CGFloat
    let save: (String) async -> Void
    @FocusState private var focused: Bool
    @State private var original = ""

    var body: some View {
        TextField("", text: $value)
            .focused($focused).font(.system(size: 14)).foregroundStyle(foreground).padding(.horizontal, 6)
            .frame(width: width, height: height).background(background)
            .overlay(Rectangle().stroke(focused ? Color.green : Color(white: 0.78), lineWidth: focused ? 2 : 0.5))
            .onChange(of: focused) { isFocused in
                if isFocused { original = value }
                else if value != original { Task { await save(value) } }
            }
            .submitLabel(.done).onSubmit { focused = false }
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: UInt64
        if cleaned.count == 6 {
            red = value >> 16; green = (value >> 8) & 0xff; blue = value & 0xff
        } else {
            red = 255; green = 255; blue = 255
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }
}

