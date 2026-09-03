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

struct SheetCell: Equatable {
    var value: String
    var background: String
    var foreground: String
}

private struct MetadataResponse: Codable {
    let ok: Bool
    let title: String?
    let sheets: [SheetInfo]?
    let error: String?
}

private struct ReadResponse: Codable {
    let ok: Bool
    let startRow: Int?
    let values: [[String]]?
    let backgrounds: [[String]]?
    let fontColors: [[String]]?
    let error: String?
}

private struct UpdateResponse: Codable {
    let ok: Bool
    let error: String?
}

@MainActor
final class SheetEditorModel: ObservableObject {
    private static let chunkRows = 100

    @Published var documentTitle = ""
    @Published var sheets: [SheetInfo] = []
    @Published var selectedSheetIndex = 0
    @Published var cells: [[SheetCell]] = []
    @Published var isLoading = false
    @Published var loadingProgress = 0.0
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var endpoint: URL? { URL(string: PrivateSheetConfig.endpoint) }
    var selectedSheet: SheetInfo? { sheets.indices.contains(selectedSheetIndex) ? sheets[selectedSheetIndex] : nil }
    var rowIndices: [Int] { Array(1...(selectedSheet?.rows ?? 1)) }
    var columnIndices: [Int] { Array(1...(selectedSheet?.columns ?? 1)) }

    func loadMetadata() async {
        isLoading = true; loadingProgress = 0; errorMessage = nil
        defer { isLoading = false }
        do {
            let response: MetadataResponse = try await get(action: "metadata", parameters: [:])
            guard response.ok, let newSheets = response.sheets, !newSheets.isEmpty else {
                throw APIError.message(response.error ?? "没有可用工作表")
            }
            documentTitle = response.title ?? "表格"
            sheets = newSheets
            selectedSheetIndex = min(selectedSheetIndex, newSheets.count - 1)
            try await loadEntireSheet()
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() async {
        guard !sheets.isEmpty else { await loadMetadata(); return }
        isLoading = true; loadingProgress = 0; errorMessage = nil
        defer { isLoading = false }
        do { try await loadEntireSheet() } catch { errorMessage = error.localizedDescription }
    }

    func selectSheet(at index: Int) async {
        guard sheets.indices.contains(index), index != selectedSheetIndex else { return }
        selectedSheetIndex = index
        await reload()
    }

    func binding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.cell(row: row, column: column).value ?? "" },
            set: { [weak self] newValue in self?.setLocal(row: row, column: column, value: newValue) }
        )
    }

    func cell(row: Int, column: Int) -> SheetCell {
        let r = row - 1, c = column - 1
        guard cells.indices.contains(r), cells[r].indices.contains(c) else {
            return SheetCell(value: "", background: "#ffffff", foreground: "#000000")
        }
        return cells[r][c]
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

    private func loadEntireSheet() async throws {
        guard let sheet = selectedSheet else { return }
        let blank = SheetCell(value: "", background: "#ffffff", foreground: "#000000")
        cells = Array(repeating: Array(repeating: blank, count: sheet.columns), count: sheet.rows)
        let chunkCount = max(1, Int(ceil(Double(sheet.rows) / Double(Self.chunkRows))))

        for chunk in 0..<chunkCount {
            let startRow = chunk * Self.chunkRows + 1
            let rowCount = min(Self.chunkRows, sheet.rows - startRow + 1)
            let response: ReadResponse = try await get(action: "read", parameters: [
                "sheet": sheet.name, "row": String(startRow), "column": "1",
                "rows": String(rowCount), "columns": String(sheet.columns)
            ])
            guard response.ok else { throw APIError.message(response.error ?? "读取失败") }
            let values = response.values ?? []
            let backgrounds = response.backgrounds ?? []
            let fontColors = response.fontColors ?? []
            for r in values.indices where cells.indices.contains(startRow - 1 + r) {
                for c in 0..<sheet.columns {
                    cells[startRow - 1 + r][c] = SheetCell(
                        value: values[r].indices.contains(c) ? values[r][c] : "",
                        background: backgrounds.indices.contains(r) && backgrounds[r].indices.contains(c) ? backgrounds[r][c] : "#ffffff",
                        foreground: fontColors.indices.contains(r) && fontColors[r].indices.contains(c) ? fontColors[r][c] : "#000000"
                    )
                }
            }
            loadingProgress = Double(chunk + 1) / Double(chunkCount)
        }
    }

    private func setLocal(row: Int, column: Int, value: String) {
        let r = row - 1, c = column - 1
        guard cells.indices.contains(r), cells[r].indices.contains(c) else { return }
        cells[r][c].value = value
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

