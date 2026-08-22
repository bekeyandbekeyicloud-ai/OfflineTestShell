import Foundation
import UserNotifications

@MainActor
final class LocalStore: ObservableObject {
    @Published var shipments: [Shipment] = [] { didSet { save() } }
    @Published var memos: [Memo] = [] { didSet { save() } }

    private let fileURL: URL
    private var isLoading = true

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OfflineTestShell", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        load()
        isLoading = false
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(AppData.self, from: data) else { return }
        shipments = decoded.shipments
        memos = decoded.memos
    }

    private func save() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(AppData(shipments: shipments, memos: memos)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addShipment(_ shipment: Shipment) {
        shipments.insert(shipment, at: 0)
        scheduleReminder(for: shipment)
    }

    func updateShipment(_ shipment: Shipment) {
        guard let index = shipments.firstIndex(where: { $0.id == shipment.id }) else { return }
        shipments[index] = shipment
        scheduleReminder(for: shipment)
    }

    func deleteShipment(_ shipment: Shipment) {
        shipments.removeAll { $0.id == shipment.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [shipment.id.uuidString])
    }

    func addMemo(_ memo: Memo) {
        memos.insert(memo, at: 0)
    }

    func deleteMemo(_ memo: Memo) {
        memos.removeAll { $0.id == memo.id }
    }

    private func scheduleReminder(for shipment: Shipment) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [shipment.id.uuidString])
        guard let date = shipment.reminderDate, date > Date(), !shipment.isArchived else { return }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "货物提醒"
            content.body = shipment.title.isEmpty ? "有一条货物记录需要处理" : shipment.title
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: shipment.id.uuidString, content: content, trigger: trigger)
            center.add(request)
        }
    }
}
