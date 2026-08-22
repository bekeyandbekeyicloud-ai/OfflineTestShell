import Foundation

enum ShipmentKind: String, Codable, CaseIterable, Identifiable {
    case business = "业务货物"
    case personal = "个人购买"
    var id: String { rawValue }
}

enum ShipmentStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "待处理"
    case held = "在他人手上"
    case waitingToShip = "待发出"
    case shipped = "已发出"
    case transit = "运输中"
    case arrived = "已到货"
    case completed = "已完成"
    var id: String { rawValue }
}

struct TrackingEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var location = ""
    var detail = ""
}

struct Shipment: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var kind: ShipmentKind = .business
    var status: ShipmentStatus = .pending
    var holder = ""
    var carrier = ""
    var trackingNumber = ""
    var trackingPhoneSuffix = ""
    var notes = ""
    var createdAt = Date()
    var expectedArrival: Date?
    var reminderDate: Date?
    var isPinned = false
    var isArchived = false
    var trackingEvents: [TrackingEvent] = []
    var trackingSource = "手动记录"
}

struct Memo: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var body = ""
    var createdAt = Date()
    var updatedAt = Date()
    var isPinned = false
}

struct AppData: Codable {
    var shipments: [Shipment] = []
    var memos: [Memo] = []
}
