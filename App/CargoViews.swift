import SwiftUI

struct ShipmentListView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var showingNew = false
    @State private var showingLogisticsSettings = false
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
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                ($0.latestTrackingEvent?.detail.localizedCaseInsensitiveContains(searchText) ?? false)
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
                        .listRowBackground(rowBackground(for: shipment.effectiveColorState))
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(store.deleteShipment)
                    }
                }
            }
            .navigationTitle("货物手册")
            .searchable(text: $searchText, prompt: "搜索货物、人员、单号、物流进度")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshDueShipments(force: true) }
                    } label: {
                        if store.isRefreshingLogistics { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    Button { showingLogisticsSettings = true } label: { Image(systemName: "gearshape") }
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                ShipmentEditorView(mode: .new)
            }
            .sheet(isPresented: $showingLogisticsSettings) {
                LogisticsSettingsView()
            }
            .task {
                await store.refreshDueShipments()
            }
            .refreshable {
                await store.refreshDueShipments(force: true)
            }
        }
    }

    private func rowBackground(for state: ShipmentColorState) -> Color {
        switch state {
        case .completed: return Color.green.opacity(0.16)
        case .progressing: return Color.yellow.opacity(0.20)
        case .unfinished: return Color.red.opacity(0.14)
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

            if !shipment.holder.isEmpty {
                Text("在：\(shipment.holder)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !shipment.trackingNumber.isEmpty {
                Text("\(shipment.carrier.isEmpty ? "物流" : shipment.carrier) · \(shipment.trackingNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let latest = shipment.latestTrackingEvent {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "location.fill")
                    Text(latest.detail)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.primary)
            } else if !shipment.trackingNumber.isEmpty {
                Text(shipment.trackingError ?? "等待物流更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let reminder = shipment.reminderDate {
                Label(reminder.displayDateTime, systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
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
    @State private var selectedColorState: ShipmentColorState
    @State private var hasExpectedArrival: Bool
    @State private var hasReminder: Bool

    init(mode: ShipmentEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            let value = Shipment()
            _shipment = State(initialValue: value)
            _selectedColorState = State(initialValue: .unfinished)
            _hasExpectedArrival = State(initialValue: false)
            _hasReminder = State(initialValue: false)
        case .edit(let value):
            _shipment = State(initialValue: value)
            _selectedColorState = State(initialValue: value.effectiveColorState)
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
                    Picker("颜色状态", selection: $selectedColorState) {
                        Text("淡红 · 未完成").tag(ShipmentColorState.unfinished)
                        Text("淡黄 · 进行中").tag(ShipmentColorState.progressing)
                        Text("淡绿 · 已完成").tag(ShipmentColorState.completed)
                    }
                    Picker("详细状态", selection: $shipment.status) {
                        ForEach(ShipmentStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("货物在谁手上", text: $shipment.holder)
                    Toggle("重要 / 置顶", isOn: $shipment.isPinned)
                }

                Section("物流") {
                    TextField("快递公司，例如 顺丰、申通、中通", text: $shipment.carrier)
                    TextField("快递公司编码（识别失败时填写）", text: Binding(get: {
                        shipment.carrierCode ?? ""
                    }, set: { shipment.carrierCode = $0.isEmpty ? nil : $0 }))
                        .textInputAutocapitalization(.never)
                    TextField("运单号", text: $shipment.trackingNumber)
                        .textInputAutocapitalization(.characters)
                    TextField("查询手机号 / 尾号（顺丰、中通等）", text: $shipment.trackingPhoneSuffix)
                        .keyboardType(.numberPad)
                    Text("保存后，进入货物主页会自动查询物流；同一单号至少间隔 30 分钟自动刷新。")
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
                        shipment.colorState = selectedColorState
                        if !hasExpectedArrival { shipment.expectedArrival = nil }
                        if !hasReminder { shipment.reminderDate = nil }
                        if isNew { store.addShipment(shipment) } else { store.updateShipment(shipment) }
                        dismiss()
                        if !shipment.trackingNumber.isEmpty {
                            Task { await store.refreshShipment(id: shipment.id, force: true) }
                        }
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
                        LabeledContent("颜色状态", value: shipment.effectiveColorState.rawValue)
                        LabeledContent("详细状态", value: shipment.status.rawValue)
                        if !shipment.holder.isEmpty { LabeledContent("当前在", value: shipment.holder) }
                        if let expected = shipment.expectedArrival { LabeledContent("预计到货", value: expected.displayDateTime) }
                        if let reminder = shipment.reminderDate { LabeledContent("提醒", value: reminder.displayDateTime) }
                    }

                    Section("物流") {
                        LabeledContent("快递公司", value: shipment.carrier.isEmpty ? "未填写" : shipment.carrier)
                        LabeledContent("运单号", value: shipment.trackingNumber.isEmpty ? "未填写" : shipment.trackingNumber)
                        if !shipment.trackingPhoneSuffix.isEmpty {
                            LabeledContent("验证手机号", value: shipment.trackingPhoneSuffix)
                        }
                        LabeledContent("信息来源", value: shipment.trackingSource)
                        if let last = shipment.lastTrackingRefresh {
                            LabeledContent("上次查询", value: last.displayDateTime)
                        }
                        if let error = shipment.trackingError, !error.isEmpty {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        Button {
                            Task {
                                await store.refreshShipment(id: shipment.id, force: true)
                                logisticsMessage = store.shipments.first(where: { $0.id == shipment.id })?.trackingError ?? "物流已刷新。"
                                showingLogisticsAlert = true
                            }
                        } label: {
                            Label("立即刷新物流", systemImage: "arrow.clockwise")
                        }
                        .disabled(shipment.trackingNumber.isEmpty)
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
                                Text(shipment.effectiveColorState.rawValue).font(.caption).foregroundStyle(.secondary)
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
