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
            .filter { shipment in
                searchText.isEmpty ||
                shipment.title.localizedCaseInsensitiveContains(searchText) ||
                shipment.holder.localizedCaseInsensitiveContains(searchText) ||
                shipment.trackingNumber.localizedCaseInsensitiveContains(searchText) ||
                shipment.notes.localizedCaseInsensitiveContains(searchText) ||
                (shipment.latestTrackingEvent?.detail.localizedCaseInsensitiveContains(searchText) ?? false)
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
                    ForEach(ShipmentKind.allCases) { item in
                        Text(item.rawValue).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("查看已归档", isOn: $showArchived)

                if filtered.isEmpty {
                    EmptyStateView(
                        title: "暂无记录",
                        systemImage: "shippingbox",
                        message: "点右上角 + 新建第一条货物记录"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { shipment in
                        NavigationLink(destination: ShipmentDetailView(shipmentID: shipment.id)) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button(action: refreshAll) {
                            if store.isRefreshingLogistics {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        Button(action: { showingLogisticsSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        Button(action: { showingNew = true }) {
                            Image(systemName: "plus")
                        }
                    }
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

    private func refreshAll() {
        Task { await store.refreshDueShipments(force: true) }
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
                if shipment.isPinned {
                    Image(systemName: "pin.fill").foregroundColor(.orange)
                }
                Text(shipment.title.isEmpty ? "未命名货物" : shipment.title)
                    .font(.headline)
                Spacer()
                Text(shipment.kind.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !shipment.holder.isEmpty {
                Text("在：\(shipment.holder)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !shipment.trackingNumber.isEmpty {
                Text("\(shipment.carrier.isEmpty ? "自动识别中" : shipment.carrier) · \(shipment.trackingNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            trackingSummary

            if let reminder = shipment.reminderDate {
                Label(reminder.displayDateTime, systemImage: "bell")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var trackingSummary: some View {
        if let latest = shipment.latestTrackingEvent {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "location.fill")
                Text(latest.detail).lineLimit(2)
            }
            .font(.caption)
            .foregroundColor(.primary)
        } else if !shipment.trackingNumber.isEmpty {
            Text(shipment.trackingError ?? "正在自动识别并查询物流")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
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
                basicSection
                logisticsSection
                dateSection
                notesSection
            }
            .navigationTitle(isNew ? "新建记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(shipment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var basicSection: some View {
        Section("基本信息") {
            TextField("标题 / 记号，例如 A001、淘宝耳机", text: $shipment.title)
            Picker("类型", selection: $shipment.kind) {
                ForEach(ShipmentKind.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            Picker("颜色状态", selection: $selectedColorState) {
                Text("淡红 · 未完成").tag(ShipmentColorState.unfinished)
                Text("淡黄 · 进行中").tag(ShipmentColorState.progressing)
                Text("淡绿 · 已完成").tag(ShipmentColorState.completed)
            }
            Picker("详细状态", selection: $shipment.status) {
                ForEach(ShipmentStatus.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            TextField("货物在谁手上", text: $shipment.holder)
            Toggle("重要 / 置顶", isOn: $shipment.isPinned)
        }
    }

    private var logisticsSection: some View {
        Section("物流") {
            TextField("只输入运单号", text: $shipment.trackingNumber)
                .textInputAutocapitalization(.characters)
                .onChange(of: shipment.trackingNumber) { _ in
                    shipment.carrier = ""
                    shipment.carrierCode = nil
                    shipment.trackingPhoneSuffix = ""
                    shipment.lastTrackingRefresh = nil
                    shipment.trackingError = nil
                }
            Text("保存后会自动识别快递公司并查询物流，不需要填写快递公司或识别编码。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var dateSection: some View {
        Section("日期") {
            Toggle("预计到货日期", isOn: $hasExpectedArrival)
            if hasExpectedArrival {
                DatePicker("预计到货", selection: expectedArrivalBinding, displayedComponents: [.date, .hourAndMinute])
            }
            Toggle("设置本地提醒", isOn: $hasReminder)
            if hasReminder {
                DatePicker("提醒时间", selection: reminderBinding)
            }
        }
    }

    private var notesSection: some View {
        Section("备注") {
            TextEditor(text: $shipment.notes)
                .frame(minHeight: 120)
        }
    }

    private var expectedArrivalBinding: Binding<Date> {
        Binding(get: { shipment.expectedArrival ?? Date() }, set: { shipment.expectedArrival = $0 })
    }

    private var reminderBinding: Binding<Date> {
        Binding(get: { shipment.reminderDate ?? Date().addingTimeInterval(3600) }, set: { shipment.reminderDate = $0 })
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func save() {
        shipment.colorState = selectedColorState
        if !hasExpectedArrival { shipment.expectedArrival = nil }
        if !hasReminder { shipment.reminderDate = nil }
        if isNew { store.addShipment(shipment) } else { store.updateShipment(shipment) }
        let shipmentID = shipment.id
        let hasTracking = !shipment.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        dismiss()
        if hasTracking {
            Task { await store.refreshShipment(id: shipmentID, force: true) }
        }
    }
}

struct ShipmentDetailView: View {
    @EnvironmentObject private var store: LocalStore
    let shipmentID: UUID
    @State private var showingEdit = false
    @State private var showingAddEvent = false
    @State private var logisticsMessage = ""
    @State private var showingLogisticsAlert = false

    private var shipment: Shipment? {
        store.shipments.first { $0.id == shipmentID }
    }

    @ViewBuilder
    var body: some View {
        if let current = shipment {
            shipmentContent(current)
        } else {
            EmptyStateView(
                title: "记录不存在",
                systemImage: "exclamationmark.triangle",
                message: "这条记录可能已经被删除"
            )
        }
    }

    private func shipmentContent(_ shipment: Shipment) -> some View {
        List {
            ShipmentInfoSection(shipment: shipment)
            ShipmentLogisticsSection(shipment: shipment, refreshAction: { refresh(shipment) })
            ShipmentTimelineSection(shipment: shipment, addAction: { showingAddEvent = true })
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            ShipmentEditorView(mode: .edit(shipment))
        }
        .sheet(isPresented: $showingAddEvent) {
            AddTrackingEventView(shipment: shipment)
        }
        .alert("物流查询", isPresented: $showingLogisticsAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(logisticsMessage)
        }
    }

    private func refresh(_ shipment: Shipment) {
        Task {
            await store.refreshShipment(id: shipment.id, force: true)
            logisticsMessage = store.shipments.first(where: { $0.id == shipment.id })?.trackingError ?? "物流已刷新。"
            showingLogisticsAlert = true
        }
    }
}

struct ShipmentInfoSection: View {
    let shipment: Shipment

    var body: some View {
        Section("货物信息") {
            LabeledContent("类型", value: shipment.kind.rawValue)
            if !shipment.holder.isEmpty {
                LabeledContent("当前在", value: shipment.holder)
            }
            if let expected = shipment.expectedArrival {
                LabeledContent("预计到货", value: expected.displayDateTime)
            }
            if let reminder = shipment.reminderDate {
                LabeledContent("提醒", value: reminder.displayDateTime)
            }
        }
    }
}

struct ShipmentLogisticsSection: View {
    let shipment: Shipment
    let refreshAction: () -> Void

    var body: some View {
        Section("物流") {
            LabeledContent("运单号", value: shipment.trackingNumber.isEmpty ? "未填写" : shipment.trackingNumber)
            LabeledContent("快递公司", value: shipment.carrier.isEmpty ? "自动识别中" : shipment.carrier)
            LabeledContent("信息来源", value: shipment.trackingSource)
            if let last = shipment.lastTrackingRefresh {
                LabeledContent("上次查询", value: last.displayDateTime)
            }
            if let error = shipment.trackingError, !error.isEmpty {
                Text(error).font(.caption).foregroundColor(.red)
            }
            Button(action: refreshAction) {
                Label("立即刷新物流", systemImage: "arrow.clockwise")
            }
            .disabled(shipment.trackingNumber.isEmpty)
        }
    }
}

struct ShipmentTimelineSection: View {
    let shipment: Shipment
    let addAction: () -> Void

    private var sortedEvents: [TrackingEvent] {
        shipment.trackingEvents.sorted { $0.date > $1.date }
    }

    var body: some View {
        Section("物流时间线") {
            Button(action: addAction) {
                Label("添加物流进度", systemImage: "plus.circle")
            }
            if sortedEvents.isEmpty {
                Text("还没有物流节点").foregroundColor(.secondary)
            } else {
                ForEach(sortedEvents) { event in
                    TrackingEventRow(event: event)
                }
            }
        }
    }
}

struct TrackingEventRow: View {
    let event: TrackingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.detail)
            HStack {
                if !event.location.isEmpty { Text(event.location) }
                Text(event.date.displayDateTime)
            }
            .font(.caption)
            .foregroundColor(.secondary)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = shipment
        updated.trackingEvents.append(TrackingEvent(date: date, location: location, detail: detail))
        updated.trackingSource = "手动记录"
        store.updateShipment(updated)
        dismiss()
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
                    EmptyStateView(
                        title: "暂无提醒",
                        systemImage: "bell",
                        message: "在货物记录中设置提醒日期即可"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(reminders) { shipment in
                        NavigationLink(destination: ShipmentDetailView(shipmentID: shipment.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shipment.title).font(.headline)
                                if let date = shipment.reminderDate {
                                    Text(date.displayDateTime)
                                        .font(.subheadline)
                                        .foregroundColor(date < Date() ? .red : .secondary)
                                }
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: self)
    }
}
