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
    case unknownCarrier
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "请先在物流设置中填写 customer 和授权 key。"
        case .missingTrackingNumber: return "请先填写运单号。"
        case .unknownCarrier: return "无法根据这个运单号自动识别快递公司。"
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

    private struct CarrierGuess: Decodable {
        let comCode: String
        let name: String
    }

    static func query(_ shipment: Shipment, credentials: LogisticsCredentials) async throws -> LogisticsQueryResult {
        guard credentials.isValid else { throw LogisticsError.missingCredentials }
        let number = shipment.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { throw LogisticsError.missingTrackingNumber }

        let carrier: CarrierGuess
        if let code = shipment.carrierCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            carrier = CarrierGuess(comCode: code.lowercased(), name: shipment.carrier.isEmpty ? displayName(for: code) : shipment.carrier)
        } else {
            carrier = try await identifyCarrier(number: number, key: credentials.key)
        }

        let events = try await queryRealtime(
            number: number,
            carrierCode: carrier.comCode,
            phone: shipment.trackingPhoneSuffix,
            credentials: credentials
        )

        return LogisticsQueryResult(events: events, carrierCode: carrier.comCode, carrierName: carrier.name)
    }

    private static func identifyCarrier(number: String, key: String) async throws -> CarrierGuess {
        var components = URLComponents(string: "https://www.kuaidi100.com/autonumber/auto")!
        components.queryItems = [
            URLQueryItem(name: "num", value: number),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = components.url else { throw LogisticsError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LogisticsError.badResponse
        }

        if let guesses = try? JSONDecoder().decode([CarrierGuess].self, from: data), let first = guesses.first {
            return first
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            throw LogisticsError.api(message)
        }

        throw LogisticsError.unknownCarrier
    }

    private static func queryRealtime(number: String, carrierCode: String, phone: String, credentials: LogisticsCredentials) async throws -> [TrackingEvent] {
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

    private static func displayName(for code: String) -> String {
        let map: [String: String] = [
            "shunfeng": "顺丰速运", "zhongtong": "中通快递", "shentong": "申通快递",
            "yuantong": "圆通速递", "yunda": "韵达快递", "jtexpress": "极兔速递",
            "jd": "京东物流", "ems": "EMS", "youzhengguonei": "邮政快递包裹",
            "debangwuliu": "德邦快递", "huitongkuaidi": "百世快递"
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
