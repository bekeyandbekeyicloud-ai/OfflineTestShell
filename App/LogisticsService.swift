import Foundation
import CryptoKit
import Security

struct LogisticsCredentials {
    let customer: String
    let key: String

    var isValid: Bool {
        !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LogisticsQueryResult {
    let events: [TrackingEvent]
    let carrierCode: String
    let carrierName: String
}

enum LogisticsError: LocalizedError {
    case missingCredentials
    case missingTrackingNumber
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "请先在物流设置中填写 customer 和授权 key。"
        case .missingTrackingNumber: return "请先填写运单号。"
        case .badResponse: return "物流接口返回了无法识别的数据。"
        case .api(let message): return message
        }
    }
}

enum CredentialStore {
    private static let service = "com.local.offlinetestshell.kuaidi100"
    private static let keyAccount = "api-key"
    private static let customerDefaultsKey = "kuaidi100.customer"

    static var customer: String {
        get { UserDefaults.standard.string(forKey: customerDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customerDefaultsKey) }
    }

    static var apiKey: String {
        get { readKeychain(account: keyAccount) ?? "" }
        set {
            if newValue.isEmpty { deleteKeychain(account: keyAccount) }
            else { saveKeychain(newValue, account: keyAccount) }
        }
    }

    static var credentials: LogisticsCredentials {
        LogisticsCredentials(customer: customer, key: apiKey)
    }

    private static func saveKeychain(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct Kuaidi100Service {
    private struct APIResponse: Decodable {
        let result: Bool?
        let returnCode: String?
        let message: String?
        let com: String?
        let nu: String?
        let data: [Trace]?
    }

    private struct Trace: Decodable {
        let time: String?
        let ftime: String?
        let context: String?
        let location: String?
        let areaName: String?
    }

    private struct RealtimeResult {
        let events: [TrackingEvent]
        let carrierCode: String
    }

    static func query(_ shipment: Shipment, credentials: LogisticsCredentials) async throws -> LogisticsQueryResult {
        guard credentials.isValid else { throw LogisticsError.missingCredentials }
        let number = shipment.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { throw LogisticsError.missingTrackingNumber }

        // Do not call Kuaidi100's separate intelligent-number API here.
        // Some trial accounts return code 601 (displayed as key expired) because that product is not enabled.
        // Prefer an already learned code, otherwise infer common carriers locally from the number format.
        let savedCode = shipment.carrierCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialCode = savedCode.isEmpty ? (localCarrierCode(for: number) ?? "") : savedCode.lowercased()

        let realtime = try await queryRealtime(
            number: number,
            carrierCode: initialCode,
            phone: shipment.trackingPhoneSuffix,
            credentials: credentials
        )

        let finalCode = realtime.carrierCode.isEmpty ? initialCode : realtime.carrierCode
        let finalName: String
        if !finalCode.isEmpty {
            finalName = displayName(for: finalCode)
        } else if !shipment.carrier.isEmpty {
            finalName = shipment.carrier
        } else {
            finalName = "自动识别"
        }

        return LogisticsQueryResult(
            events: realtime.events,
            carrierCode: finalCode,
            carrierName: finalName
        )
    }

    private static func queryRealtime(number: String, carrierCode: String, phone: String, credentials: LogisticsCredentials) async throws -> RealtimeResult {
        let paramObject: [String: String] = [
            "com": carrierCode,
            "num": number,
            "phone": phone,
            "from": "",
            "to": "",
            "resultv2": "4",
            "show": "0",
            "order": "desc"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: paramObject, options: [])
        guard let param = String(data: jsonData, encoding: .utf8) else { throw LogisticsError.badResponse }
        let sign = md5Uppercase(param + credentials.key + credentials.customer)

        var request = URLRequest(url: URL(string: "https://poll.kuaidi100.com/poll/query.do")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = formEncoded([
            "customer": credentials.customer,
            "sign": sign,
            "param": param
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LogisticsError.badResponse
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        if decoded.result == false {
            let message = decoded.message ?? "物流查询失败"
            // Avoid misleading the user when the old smart-number product error text says the key expired.
            if decoded.returnCode == "601" || message.localizedCaseInsensitiveContains("key已过期") || message.localizedCaseInsensitiveContains("key 已过期") {
                throw LogisticsError.api("当前账号未开通独立的智能单号识别服务。本版本已不再调用该服务；如果仍看到此提示，请重新打开 App 后再查询。")
            }
            throw LogisticsError.api(message)
        }

        guard let traces = decoded.data else { throw LogisticsError.badResponse }
        let events = traces.compactMap { trace -> TrackingEvent? in
            let detail = trace.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !detail.isEmpty else { return nil }
            return TrackingEvent(
                date: parseDate(trace.time ?? trace.ftime) ?? Date(),
                location: (trace.location ?? trace.areaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail
            )
        }

        return RealtimeResult(
            events: events,
            carrierCode: (decoded.com ?? carrierCode).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private static func localCarrierCode(for rawNumber: String) -> String? {
        let number = rawNumber.uppercased().replacingOccurrences(of: " ", with: "")

        if number.hasPrefix("SF") { return "shunfeng" }
        if number.hasPrefix("YT") { return "yuantong" }
        if number.hasPrefix("JT") { return "jtexpress" }
        if number.hasPrefix("JD") { return "jd" }

        // China Post / EMS international-style tracking numbers, e.g. EA123456789CN.
        if matches(number, pattern: "^[A-Z]{2}[0-9]{9}CN$") { return "ems" }

        // Common high-confidence numeric formats. These are deliberately conservative;
        // unknown formats are submitted to the realtime endpoint with an empty com field.
        if matches(number, pattern: "^7[5-9][0-9]{12}$") { return "zhongtong" }
        if matches(number, pattern: "^[2345689]68[0-9]{9}$") { return "shentong" }
        if matches(number, pattern: "^(43|45|46|48|50|53)[0-9]{11}$") { return "yunda" }

        return nil
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func displayName(for code: String) -> String {
        let map: [String: String] = [
            "shunfeng": "顺丰速运",
            "zhongtong": "中通快递",
            "shentong": "申通快递",
            "yuantong": "圆通速递",
            "yunda": "韵达快递",
            "jtexpress": "极兔速递",
            "jd": "京东物流",
            "ems": "EMS",
            "youzhengguonei": "邮政快递包裹",
            "debangwuliu": "德邦快递",
            "huitongkuaidi": "百世快递"
        ]
        return map[code.lowercased()] ?? code
    }

    private static func md5Uppercase(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private static func formEncoded(_ fields: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
