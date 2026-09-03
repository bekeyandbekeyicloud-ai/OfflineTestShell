import Foundation
import SwiftUI

enum PrivateSheetConfig {
    static let endpoint = "__SHEET_ENDPOINT__"
    static let accessKey = "__SHEET_ACCESS_KEY__"
}

struct SheetInfo: Codable, Equatable { let name: String; let rows: Int; let columns: Int }
struct CellAddress: Equatable { let row: Int; let column: Int }

struct SheetCell: Equatable {
    var value = ""
    var background = "#ffffff"
    var foreground = "#000000"
    var bold = false
    var fontSize = 10.0
    var alignment = "left"
}

private struct MetadataResponse: Codable { let ok: Bool; let title: String?; let sheets: [SheetInfo]?; let error: String? }
private struct ReadResponse: Codable {
    let ok: Bool; let values: [[String]]?; let backgrounds: [[String]]?; let fontColors: [[String]]?
    let fontWeights: [[String]]?; let fontSizes: [[Double]]?; let alignments: [[String]]?; let error: String?
}
private struct BasicResponse: Codable { let ok: Bool; let error: String? }
private struct DimensionsResponse: Codable { let ok: Bool; let rowHeights: [Int]?; let columnWidths: [Int]?; let error: String? }

@MainActor
final class SheetEditorModel: ObservableObject {
    private static let chunkRows = 100
    @Published var documentTitle = ""
    @Published var sheets: [SheetInfo] = []
    @Published var selectedSheetIndex = 0
    @Published var cells: [[SheetCell]] = []
    @Published var rowHeights: [Int] = []
    @Published var columnWidths: [Int] = []
    @Published var selectedStart: CellAddress?
    @Published var selectedEnd: CellAddress?
    @Published var rangeMode = false
    @Published var editorText = ""
    @Published var isLoading = false
    @Published var isBackgroundLoading = false
    @Published var loadingProgress = 0.0
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var endpoint: URL? { URL(string: PrivateSheetConfig.endpoint) }
    var selectedSheet: SheetInfo? { sheets.indices.contains(selectedSheetIndex) ? sheets[selectedSheetIndex] : nil }
    var rowIndices: [Int] { Array(1...(selectedSheet?.rows ?? 1)) }
    var columnIndices: [Int] { Array(1...(selectedSheet?.columns ?? 1)) }
    var selectionLabel: String {
        guard let a = selectedStart else { return "未选择" }
        let first = "\(columnName(a.column))\(a.row)"
        guard let b = selectedEnd, b != a else { return first }
        return "\(first):\(columnName(b.column))\(b.row)"
    }

    func loadMetadata() async {
        isLoading = true; loadingProgress = 0; errorMessage = nil
        defer { isLoading = false }
        do {
            let response: MetadataResponse = try await get(action: "metadata", parameters: [:])
            guard response.ok, let list = response.sheets, !list.isEmpty else { throw APIError.message(response.error ?? "没有可用工作表") }
            documentTitle = response.title ?? "表格"; sheets = list
            selectedSheetIndex = min(selectedSheetIndex, list.count - 1)
            try await loadFirstScreen()
            Task { await loadRemainingData() }
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async {
        guard !sheets.isEmpty else { await loadMetadata(); return }
        isLoading = true; loadingProgress = 0; errorMessage = nil
        defer { isLoading = false }
        do { try await loadFirstScreen(); Task { await loadRemainingData() } }
        catch { errorMessage = error.localizedDescription }
    }

    func selectSheet(at index: Int) async {
        guard sheets.indices.contains(index), index != selectedSheetIndex else { return }
        selectedSheetIndex = index; clearSelection(); await reload()
    }

    func cell(row: Int, column: Int) -> SheetCell {
        guard cells.indices.contains(row - 1), cells[row - 1].indices.contains(column - 1) else { return SheetCell() }
        return cells[row - 1][column - 1]
    }

    func tap(row: Int, column: Int) {
        let address = CellAddress(row: row, column: column)
        if rangeMode, selectedStart != nil, selectedEnd == nil { selectedEnd = address }
        else { selectedStart = address; selectedEnd = rangeMode ? nil : address }
        editorText = cell(row: row, column: column).value
    }

    func clearSelection() { selectedStart = nil; selectedEnd = nil; editorText = "" }
    func isSelected(row: Int, column: Int) -> Bool {
        guard let a = selectedStart else { return false }; let b = selectedEnd ?? a
        return row >= min(a.row,b.row) && row <= max(a.row,b.row) && column >= min(a.column,b.column) && column <= max(a.column,b.column)
    }

    func saveEditorText() async {
        guard let a = selectedStart else { return }
        cells[a.row - 1][a.column - 1].value = editorText
        await post(["action":"update", "sheet":selectedSheet?.name ?? "", "row":a.row, "column":a.column, "value":editorText])
    }

    func applyBackground(_ hex: String) async { await applyFormat(["background": hex]) { $0.background = hex } }
    func applyForeground(_ hex: String) async { await applyFormat(["foreground": hex]) { $0.foreground = hex } }
    func toggleBold() async {
        guard let a = selectedStart else { return }; let value = !cell(row:a.row,column:a.column).bold
        await applyFormat(["bold": value]) { $0.bold = value }
    }
    func applyFontSize(_ size: Double) async { await applyFormat(["fontSize": size]) { $0.fontSize = size } }
    func applyAlignment(_ value: String) async { await applyFormat(["alignment": value]) { $0.alignment = value } }
    func merge() async { await rangeCommand("merge") }
    func unmerge() async { await rangeCommand("unmerge") }
    func resizeRow(delta: Int) async {
        guard let a = selectedStart else { return }
        if rowHeights.indices.contains(a.row - 1) { rowHeights[a.row - 1] = max(20, rowHeights[a.row - 1] + delta) }
        await post(["action":"dimension", "sheet":selectedSheet?.name ?? "", "kind":"row", "index":a.row, "delta":delta])
    }
    func resizeColumn(delta: Int) async {
        guard let a = selectedStart else { return }
        if columnWidths.indices.contains(a.column - 1) { columnWidths[a.column - 1] = max(40, columnWidths[a.column - 1] + delta) }
        await post(["action":"dimension", "sheet":selectedSheet?.name ?? "", "kind":"column", "index":a.column, "delta":delta])
    }

    func rowHeight(_ row: Int) -> CGFloat { CGFloat(rowHeights.indices.contains(row - 1) ? rowHeights[row - 1] : 38) }
    func columnWidth(_ column: Int) -> CGFloat { CGFloat(columnWidths.indices.contains(column - 1) ? columnWidths[column - 1] : 108) }

    func columnName(_ column: Int) -> String {
        var number = column, result = ""
        while number > 0 { number -= 1; result = String(UnicodeScalar(65 + number % 26)!) + result; number /= 26 }
        return result
    }

    private func bounds() -> (Int,Int,Int,Int)? {
        guard let a = selectedStart else { return nil }; let b = selectedEnd ?? a
        return (min(a.row,b.row), min(a.column,b.column), max(a.row,b.row), max(a.column,b.column))
    }

    private func applyFormat(_ format: [String:Any], local: (inout SheetCell) -> Void) async {
        guard let (r1,c1,r2,c2) = bounds() else { return }
        for r in r1...r2 { for c in c1...c2 { local(&cells[r-1][c-1]) } }
        await post(["action":"format", "sheet":selectedSheet?.name ?? "", "r1":r1, "c1":c1, "r2":r2, "c2":c2, "format":format])
    }

    private func rangeCommand(_ action: String) async {
        guard let (r1,c1,r2,c2) = bounds() else { return }
        await post(["action":action, "sheet":selectedSheet?.name ?? "", "r1":r1, "c1":c1, "r2":r2, "c2":c2])
        await reload()
    }

    private func post(_ body: [String:Any]) async {
        guard let endpoint else { return }
        isSaving = true; errorMessage = nil; defer { isSaving = false }
        do {
            var payload = body; payload["key"] = PrivateSheetConfig.accessKey
            var request = URLRequest(url:endpoint); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField:"Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject:payload)
            let (data,_) = try await URLSession.shared.data(for:request)
            let response = try JSONDecoder().decode(BasicResponse.self, from:data)
            if !response.ok { throw APIError.message(response.error ?? "操作失败") }
        } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }

    private func loadFirstScreen() async throws {
        guard let sheet = selectedSheet else { return }
        rowHeights = Array(repeating:38,count:sheet.rows)
        columnWidths = Array(repeating:108,count:sheet.columns)
        cells = Array(repeating:Array(repeating:SheetCell(),count:sheet.columns),count:sheet.rows)
        try await loadChunk(start:1,count:min(60,sheet.rows))
        loadingProgress = 1
    }

    private func loadRemainingData() async {
        guard let sheet = selectedSheet, sheet.rows > 60 else { return }
        let sheetName = sheet.name
        isBackgroundLoading = true; defer { isBackgroundLoading = false }
        var start = 61
        while start <= sheet.rows {
            guard selectedSheet?.name == sheetName else { return }
            do { try await loadChunk(start:start,count:min(Self.chunkRows,sheet.rows-start+1)) }
            catch { errorMessage = error.localizedDescription; return }
            start += Self.chunkRows
        }
        Task { await loadDimensionsInBackground(for: sheetName) }
    }

    private func loadDimensionsInBackground(for sheetName:String) async {
        guard selectedSheet?.name == sheetName else { return }
        do {
            let response:DimensionsResponse = try await get(action:"dimensions",parameters:["sheet":sheetName])
            guard response.ok, selectedSheet?.name == sheetName else { return }
            if let rows=response.rowHeights { rowHeights=rows }
            if let columns=response.columnWidths { columnWidths=columns }
        } catch { /* 尺寸读取不阻塞内容显示 */ }
    }

    private func loadChunk(start:Int,count:Int) async throws {
        guard let sheet=selectedSheet else { return }
        let response:ReadResponse = try await get(action:"read",parameters:["sheet":sheet.name,"row":String(start),"column":"1","rows":String(count),"columns":String(sheet.columns)])
        guard response.ok else { throw APIError.message(response.error ?? "读取失败") }
        let values=response.values ?? [],bg=response.backgrounds ?? [],fg=response.fontColors ?? []
        let weights=response.fontWeights ?? [],sizes=response.fontSizes ?? [],aligns=response.alignments ?? []
        var updated=cells
        for r in values.indices where updated.indices.contains(start-1+r) { for c in 0..<sheet.columns {
            updated[start-1+r][c]=SheetCell(value:values[r].indices.contains(c) ? values[r][c]:"",background:bg.indices.contains(r)&&bg[r].indices.contains(c) ? bg[r][c]:"#ffffff",foreground:fg.indices.contains(r)&&fg[r].indices.contains(c) ? fg[r][c]:"#000000",bold:weights.indices.contains(r)&&weights[r].indices.contains(c)&&weights[r][c]=="bold",fontSize:sizes.indices.contains(r)&&sizes[r].indices.contains(c) ? sizes[r][c]:10,alignment:aligns.indices.contains(r)&&aligns[r].indices.contains(c) ? aligns[r][c]:"left")
        }}
        cells=updated
    }

    private func get<T:Decodable>(action:String, parameters:[String:String]) async throws -> T {
        guard let endpoint else { throw APIError.message("接口尚未配置") }
        var parts=URLComponents(url:endpoint,resolvingAgainstBaseURL:false)!
        var items=[URLQueryItem(name:"key",value:PrivateSheetConfig.accessKey),URLQueryItem(name:"action",value:action)]
        items += parameters.map { URLQueryItem(name:$0.key,value:$0.value) }; parts.queryItems=items
        let (data,_)=try await URLSession.shared.data(from:parts.url!); return try JSONDecoder().decode(T.self,from:data)
    }
}

private enum APIError: LocalizedError { case message(String); var errorDescription:String? { if case .message(let v)=self{return v};return "未知错误" } }

