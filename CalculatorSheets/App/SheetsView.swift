import SwiftUI

struct SheetsView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var model: SheetEditorModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.isLoading && model.sheets.isEmpty {
                Spacer(); ProgressView("正在读取表格…"); Spacer()
            } else if let error = model.errorMessage, model.sheets.isEmpty {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("无法读取表格").font(.headline)
                Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button("重试") { Task { await model.loadMetadata() } }.buttonStyle(.borderedProminent)
                Spacer()
            } else {
                sheetPicker
                pageControls
                spreadsheetGrid
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
                .accessibilityLabel("立即锁定")
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

    private var pageControls: some View {
        HStack(spacing: 12) {
            Button { Task { await model.previousRows() } } label: { Image(systemName: "chevron.up") }
                .disabled(model.rowOffset == 1 || model.isLoading)
            Button { Task { await model.nextRows() } } label: { Image(systemName: "chevron.down") }
                .disabled(!model.hasMoreRows || model.isLoading)
            Text("行 \(model.rowOffset)–\(model.lastVisibleRow)").font(.caption.monospacedDigit())
            Spacer()
            Button { Task { await model.previousColumns() } } label: { Image(systemName: "chevron.left") }
                .disabled(model.columnOffset == 1 || model.isLoading)
            Button { Task { await model.nextColumns() } } label: { Image(systemName: "chevron.right") }
                .disabled(!model.hasMoreColumns || model.isLoading)
            Text("列 \(model.columnName(model.columnOffset))–\(model.columnName(model.lastVisibleColumn))")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 14).frame(height: 40).foregroundStyle(.white).background(Color(white: 0.10))
    }

    private var spreadsheetGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    gridHeader("")
                    ForEach(model.visibleColumnIndices, id: \.self) { gridHeader(model.columnName($0)) }
                }
                ForEach(model.visibleRowIndices, id: \.self) { row in
                    HStack(spacing: 0) {
                        gridHeader(String(row))
                        ForEach(model.visibleColumnIndices, id: \.self) { column in
                            CellEditor(
                                value: model.binding(row: row, column: column),
                                save: { value in await model.update(row: row, column: column, value: value) }
                            )
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .overlay {
            if model.isLoading && !model.cells.isEmpty {
                ProgressView().padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func gridHeader(_ text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 82, height: 34)
            .background(Color(white: 0.92)).overlay(Rectangle().stroke(Color(white: 0.78), lineWidth: 0.5))
    }

    private var statusBar: some View {
        HStack {
            if model.isSaving { ProgressView().controlSize(.small); Text("正在保存…") }
            else if let error = model.errorMessage { Image(systemName: "exclamationmark.circle"); Text(error) }
            else { Image(systemName: "checkmark.circle"); Text("更改会立即同步") }
            Spacer()
        }
        .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
        .padding(.horizontal, 12).frame(height: 34).background(Color(white: 0.95))
    }
}

private struct CellEditor: View {
    @Binding var value: String
    let save: (String) async -> Void
    @FocusState private var focused: Bool
    @State private var original = ""

    var body: some View {
        TextField("", text: $value)
            .focused($focused).font(.system(size: 14)).foregroundStyle(.black).padding(.horizontal, 6)
            .frame(width: 122, height: 38).background(Color.white)
            .overlay(Rectangle().stroke(focused ? Color.green : Color(white: 0.82), lineWidth: focused ? 1.5 : 0.5))
            .onChange(of: focused) { isFocused in
                if isFocused { original = value }
                else if value != original { Task { await save(value) } }
            }
            .submitLabel(.done).onSubmit { focused = false }
    }
}
