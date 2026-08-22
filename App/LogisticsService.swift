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

enum LogisticsError: LocalizedError {
    case missingCredentials
    case missingTrackingNumber
    case unknownCarrier
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "请先在物流设置中填写 customer 和授权 key。"
        case .missingTrackingNumber: return "请先填写运单号。"
        case .unknownCarrier: return "无法识别快递公司，请在编辑页填写快递公司编码。"
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
        let data: [Trace]?
    }

    private struct Trace: Decodable {
        let time: String?
        let ftime: String?
        let context: String?
        let location: String?
        let areaName: String?
    }

    static func query(_ shipment: Shipment, credentials: LogisticsCredentials) async throws -> [TrackingEvent] {
        guard credentials.isValid else { throw LogisticsError.missingCredentials }
        guard !shipment.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogisticsError.missingTrackingNumber
        }
        guard let com = carrierCode(for: shipment) else { throw LogisticsError.unknownCarrier }

        var paramObject: [String: String] = [
            "com": com,
            "num": shipment.trackingNumber,
            "phone": shipment.trackingPhoneSuffix,
            "from": "",
            "to": "",
            "resultv2": "4",
            "show": "0",
            "order": "desc"
        ]
        if shipment.trackingPhoneSuffix.isEmpty { paramObject["phone"] = "" }

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
            throw LogisticsError.api(decoded.message ?? "物流查询失败")
        }
        guard let traces = decoded.data else { throw LogisticsError.badResponse }
        return traces.compactMap { trace in
            let detail = trace.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !detail.isEmpty else { return nil }
            return TrackingEvent(
                date: parseDate(trace.time ?? trace.ftime) ?? Date(),
                location: (trace.location ?? trace.areaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail
            )
        }
    }

    static func carrierCode(for shipment: Shipment) -> String? {
        if let code = shipment.carrierCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code.lowercased()
        }
        let name = shipment.carrier.lowercased()
        let map: [(String, String)] = [
            ("顺丰", "shunfeng"), ("sf", "shunfeng"),
            ("中通", "zhongtong"), ("申通", "shentong"),
            ("圆通", "yuantong"), ("韵达", "yunda"),
            ("极兔", "jtexpress"), ("京东", "jd"),
            ("邮政", "youzhengguonei"), ("ems", "ems"),
            ("德邦", "debangwuliu"), ("百世", "huitongkuaidi")
        ]
        for (needle, code) in map where name.contains(needle.lowercased()) { return code }
        return nil
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
