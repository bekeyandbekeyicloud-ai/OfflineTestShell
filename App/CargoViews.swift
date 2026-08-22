import SwiftUI

struct ShipmentListView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var showingNew = false
    @State private var searchText = ""
    @State private var kindFilter = "全部"
    @State private var showArchived = false

    private var filtered: [Shipment] {
        store.shipments
            .filter { showArchived ? $0.isArchived : !$0.isArchived }
            .filter { kindFilter == "全部" || $0.kind.rawValue == kindFilter }
            .filter {
                searchText.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.holder.localizedCaseInsensitiveContains(searchText) ||
                $0.trackingNumber.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.createdAt > $1.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("类型", selection: $kindFilter) {
                    Text("全部").tag("全部")
                    ForEach(ShipmentKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                Toggle("查看已归档", isOn: $showArchived)

                if filtered.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "shippingbox", description: Text("点右上角 + 新建第一条货物记录"))
                } else {
                    ForEach(filtered) { shipment in
                        NavigationLink {
                            ShipmentDetailView(shipmentID: shipment.id)
                        } label: {
                            ShipmentRow(shipment: shipment)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(store.deleteShipment)
                    }
                }
            }
            .navigationTitle("货物手册")
            .searchable(text: $searchText, prompt: "搜索货物、人员、单号")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                ShipmentEditorView(mode: .new)
            }
        }
    }
}

struct ShipmentRow: View {
    let shipment: Shipment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if shipment.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Text(shipment.title.isEmpty ? "未命名货物" : shipment.title).font(.headline)
                Spacer()
                Text(shipment.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(shipment.status.rawValue)
                if !shipment.holder.isEmpty { Text("在：\(shipment.holder)") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !shipment.trackingNumber.isEmpty {
                Text("\(shipment.carrier.isEmpty ? "物流" : shipment.carrier) · \(shipment.trackingNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let reminder = shipment.reminderDate {
                Label(reminder.displayDateTime, systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

enum ShipmentEditorMode {
    case new
    case edit(Shipment)
}

struct ShipmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LocalStore

    let mode: ShipmentEditorMode
    @State private var shipment: Shipment
    @State private var hasExpectedArrival: Bool
    @State private var hasReminder: Bool

    init(mode: ShipmentEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            let value = Shipment()
            _shipment = State(initialValue: value)
            _hasExpectedArrival = State(initialValue: false)
            _hasReminder = State(initialValue: false)
        case .edit(let value):
            _shipment = State(initialValue: value)
            _hasExpectedArrival = State(initialValue: value.expectedArrival != nil)
            _hasReminder = State(initialValue: value.reminderDate != nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题 / 记号，例如 A001、淘宝耳机", text: $shipment.title)
                    Picker("类型", selection: $shipment.kind) {
                        ForEach(ShipmentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("状态", selection: $shipment.status) {
                        ForEach(ShipmentStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("货物在谁手上", text: $shipment.holder)
                    Toggle("重要 / 置顶", isOn: $shipment.isPinned)
                }

                Section("物流") {
                    TextField("快递公司，例如 顺丰、申通", text: $shipment.carrier)
                    TextField("运单号", text: $shipment.trackingNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("查询验证手机号尾号（顺丰等）", text: $shipment.trackingPhoneSuffix)
                        .keyboardType(.numberPad)
                    Text("联网物流查询接口已预留；当前版本先保存单号和验证尾号，物流节点可手动添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("日期") {
                    Toggle("预计到货日期", isOn: $hasExpectedArrival)
                    if hasExpectedArrival {
                        DatePicker("预计到货", selection: Binding(get: {
                            shipment.expectedArrival ?? Date()
                        }, set: { shipment.expectedArrival = $0 }), displayedComponents: [.date, .hourAndMinute])
                    }

                    Toggle("设置本地提醒", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("提醒时间", selection: Binding(get: {
                            shipment.reminderDate ?? Date().addingTimeInterval(3600)
                        }, set: { shipment.reminderDate = $0 }))
                    }
                }

                Section("备注") {
                    TextEditor(text: $shipment.notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(isNew ? "新建记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if !hasExpectedArrival { shipment.expectedArrival = nil }
                        if !hasReminder { shipment.reminderDate = nil }
                        if isNew { store.addShipment(shipment) } else { store.updateShipment(shipment) }
                        dismiss()
                    }
                    .disabled(shipment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }
}

struct ShipmentDetailView: View {
    @EnvironmentObject private var store: LocalStore
    let shipmentID: UUID
    @State private var showingEdit = false
    @State private var showingAddEvent = false
    @State private var logisticsMessage = ""
    @State private var showingLogisticsAlert = false

    private var shipment: Shipment? { store.shipments.first { $0.id == shipmentID } }

    var body: some View {
        Group {
            if let shipment {
                List {
                    Section {
                        LabeledContent("类型", value: shipment.kind.rawValue)
                        LabeledContent("状态", value: shipment.status.rawValue)
                        if !shipment.holder.isEmpty { LabeledContent("当前在", value: shipment.holder) }
                        if let expected = shipment.expectedArrival { LabeledContent("预计到货", value: expected.displayDateTime) }
                        if let reminder = shipment.reminderDate { LabeledContent("提醒", value: reminder.displayDateTime) }
                    }

                    Section("物流") {
                        LabeledContent("快递公司", value: shipment.carrier.isEmpty ? "未填写" : shipment.carrier)
                        LabeledContent("运单号", value: shipment.trackingNumber.isEmpty ? "未填写" : shipment.trackingNumber)
                        if !shipment.trackingPhoneSuffix.isEmpty {
                            LabeledContent("验证尾号", value: shipment.trackingPhoneSuffix)
                        }
                        LabeledContent("信息来源", value: shipment.trackingSource)
                        Button {
                            logisticsMessage = shipment.trackingNumber.isEmpty
                            ? "请先填写运单号。"
                            : "物流联网查询入口已经预留。下一步接入查询服务后，这里会自动刷新当前位置和轨迹；当前请先用“添加物流进度”手动记录。"
                            showingLogisticsAlert = true
                        } label: {
                            Label("刷新物流", systemImage: "arrow.clockwise")
                        }
                    }

                    Section("物流时间线") {
                        Button { showingAddEvent = true } label: {
                            Label("添加物流进度", systemImage: "plus.circle")
                        }
                        if shipment.trackingEvents.isEmpty {
                            Text("还没有物流节点").foregroundStyle(.secondary)
                        } else {
                            ForEach(shipment.trackingEvents.sorted { $0.date > $1.date }) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.detail).font(.body)
                                    HStack {
                                        if !event.location.isEmpty { Text(event.location) }
                                        Text(event.date.displayDateTime)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !shipment.notes.isEmpty {
                        Section("备注") { Text(shipment.notes) }
                    }

                    Section {
                        Button(shipment.isArchived ? "取消归档" : "归档此记录") {
                            var updated = shipment
                            updated.isArchived.toggle()
                            store.updateShipment(updated)
                        }
                    }
                }
                .navigationTitle(shipment.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("编辑") { showingEdit = true }
                    }
                }
                .sheet(isPresented: $showingEdit) { ShipmentEditorView(mode: .edit(shipment)) }
                .sheet(isPresented: $showingAddEvent) { AddTrackingEventView(shipment: shipment) }
                .alert("物流查询", isPresented: $showingLogisticsAlert) { Button("好") {} } message: { Text(logisticsMessage) }
            } else {
                ContentUnavailableView("记录不存在", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

struct AddTrackingEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LocalStore
    let shipment: Shipment
    @State private var date = Date()
    @State private var location = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("时间", selection: $date)
                TextField("位置，例如 深圳转运中心", text: $location)
                TextField("进度，例如 已揽收 / 派送中", text: $detail)
            }
            .navigationTitle("添加物流进度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = shipment
                        updated.trackingEvents.append(TrackingEvent(date: date, location: location, detail: detail))
                        updated.trackingSource = "手动记录"
                        store.updateShipment(updated)
                        dismiss()
                    }
                    .disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ReminderListView: View {
    @EnvironmentObject private var store: LocalStore

    private var reminders: [Shipment] {
        store.shipments
            .filter { !$0.isArchived && $0.reminderDate != nil }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                if reminders.isEmpty {
                    ContentUnavailableView("暂无提醒", systemImage: "bell", description: Text("在货物记录中设置提醒日期即可"))
                } else {
                    ForEach(reminders) { shipment in
                        NavigationLink {
                            ShipmentDetailView(shipmentID: shipment.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shipment.title).font(.headline)
                                if let date = shipment.reminderDate {
                                    Text(date.displayDateTime)
                                        .font(.subheadline)
                                        .foregroundStyle(date < Date() ? .red : .secondary)
                                }
                                Text(shipment.status.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("日期提醒")
        }
    }
}

extension Date {
    var displayDateTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: self)
    }
}
