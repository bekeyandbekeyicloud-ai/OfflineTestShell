import Foundation
import SwiftUI

enum PrivateSheetConfig {
    static let endpoint = "__SHEET_ENDPOINT__"
    static let accessKey = "__SHEET_ACCESS_KEY__"
}

struct SheetInfo: Codable, Equatable {
    let name: String
    let rows: Int
    let columns: Int
}

private struct MetadataResponse: Codable {
    let ok: Bool
    let title: String?
    let sheets: [SheetInfo]?
    let error: String?
}

private struct ReadResponse: Codable {
    let ok: Bool
    let values: [[String]]?
    let error: String?
}

private struct UpdateResponse: Codable {
    let ok: Bool
    let error: String?
}

@MainActor
final class SheetEditorModel: ObservableObject {
    static let pageRows = 20
    static let pageColumns = 8

    @Published var documentTitle = ""
    @Published var sheets: [SheetInfo] = []
    @Published var selectedSheetIndex = 0
    @Published var cells: [[String]] = []
    @Published var rowOffset = 1
    @Published var columnOffset = 1
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var endpoint: URL? { URL(string: PrivateSheetConfig.endpoint) }
    private var selectedSheet: SheetInfo? { sheets.indices.contains(selectedSheetIndex) ? sheets[selectedSheetIndex] : nil }
    var visibleRowIndices: [Int] { Array(rowOffset...lastVisibleRow) }
    var visibleColumnIndices: [Int] { Array(columnOffset...lastVisibleColumn) }
    var lastVisibleRow: Int { min(rowOffset + Self.pageRows - 1, max(selectedSheet?.rows ?? 1, rowOffset)) }
    var lastVisibleColumn: Int { min(columnOffset + Self.pageColumns - 1, max(selectedSheet?.columns ?? 1, columnOffset)) }
    var hasMoreRows: Bool { lastVisibleRow < (selectedSheet?.rows ?? 1) }
    var hasMoreColumns: Bool { lastVisibleColumn < (selectedSheet?.columns ?? 1) }

    func loadMetadata() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response: MetadataResponse = try await get(action: "metadata", parameters: [:])
            guard response.ok, let newSheets = response.sheets, !newSheets.isEmpty else {
                throw APIError.message(response.error ?? "没有可用工作表")
            }
            documentTitle = response.title ?? "表格"
            sheets = newSheets
            selectedSheetIndex = min(selectedSheetIndex, newSheets.count - 1)
            rowOffset = 1; columnOffset = 1
            try await loadPage()
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async {
        guard !sheets.isEmpty else { await loadMetadata(); return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { try await loadPage() } catch { errorMessage = error.localizedDescription }
    }

    func selectSheet(at index: Int) async {
        guard sheets.indices.contains(index) else { return }
        selectedSheetIndex = index; rowOffset = 1; columnOffset = 1
        await reload()
    }

    func nextRows() async { rowOffset += Self.pageRows; await reload() }
    func previousRows() async { rowOffset = max(1, rowOffset - Self.pageRows); await reload() }
    func nextColumns() async { columnOffset += Self.pageColumns; await reload() }
    func previousColumns() async { columnOffset = max(1, columnOffset - Self.pageColumns); await reload() }

    func binding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.value(row: row, column: column) ?? "" },
            set: { [weak self] newValue in self?.setLocal(row: row, column: column, value: newValue) }
        )
    }

    func update(row: Int, column: Int, value: String) async {
        guard let sheet = selectedSheet, let endpoint else { return }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "key": PrivateSheetConfig.accessKey, "action": "update", "sheet": sheet.name,
                "row": row, "column": column, "value": value
            ])
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(UpdateResponse.self, from: data)
            if !response.ok { throw APIError.message(response.error ?? "保存失败") }
        } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }

    func columnName(_ column: Int) -> String {
        var number = column; var result = ""
        while number > 0 {
            number -= 1
            result = String(UnicodeScalar(65 + number % 26)!) + result
            number /= 26
        }
        return result
    }

    private func loadPage() async throws {
        guard let sheet = selectedSheet else { return }
        let response: ReadResponse = try await get(action: "read", parameters: [
            "sheet": sheet.name, "row": String(rowOffset), "column": String(columnOffset),
            "rows": String(Self.pageRows), "columns": String(Self.pageColumns)
        ])
        guard response.ok else { throw APIError.message(response.error ?? "读取失败") }
        cells = response.values ?? []
    }

    private func value(row: Int, column: Int) -> String {
        let r = row - rowOffset, c = column - columnOffset
        guard cells.indices.contains(r), cells[r].indices.contains(c) else { return "" }
        return cells[r][c]
    }

    private func setLocal(row: Int, column: Int, value: String) {
        let r = row - rowOffset, c = column - columnOffset
        guard cells.indices.contains(r), cells[r].indices.contains(c) else { return }
        cells[r][c] = value
    }

    private func get<T: Decodable>(action: String, parameters: [String: String]) async throws -> T {
        guard let endpoint else { throw APIError.message("接口尚未配置") }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "key", value: PrivateSheetConfig.accessKey), URLQueryItem(name: "action", value: action)]
        items += parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return "未知错误" }
}

