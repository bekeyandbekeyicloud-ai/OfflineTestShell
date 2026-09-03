import SwiftUI

struct CalculatorView: View {
    @EnvironmentObject private var session: AppSession
    @State private var display = "0"
    @State private var storedValue: Double?
    @State private var pendingOperation: Operation?
    @State private var startsNewNumber = true
    @State private var unlockSequence: [Key] = []

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let diameter = min((proxy.size.width - 5 * spacing) / 4, 88)

            VStack(spacing: spacing) {
                Spacer()
                Text(display)
                    .font(.system(size: display.count > 8 ? 52 : 76, weight: .light, design: .rounded))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("calculatorDisplay")

                VStack(spacing: spacing) {
                    keyRow([.clear, .sign, .percent, .operation(.divide)], diameter, spacing)
                    keyRow([.digit(7), .digit(8), .digit(9), .operation(.multiply)], diameter, spacing)
                    keyRow([.digit(4), .digit(5), .digit(6), .operation(.subtract)], diameter, spacing)
                    keyRow([.digit(1), .digit(2), .digit(3), .operation(.add)], diameter, spacing)
                    keyRow([.digit(0), .decimal, .equals], diameter, spacing)
                }
            }
            .padding(.horizontal, spacing)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
            .background(Color.black.ignoresSafeArea())
        }
    }

    private func keyRow(_ keys: [Key], _ diameter: CGFloat, _ spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(keys) { key in
                CalculatorButton(key: key, diameter: diameter) { handle(key) }
                    .frame(width: key == .digit(0) ? diameter * 2 + spacing : diameter)
            }
        }
    }

    private func handle(_ key: Key) {
        trackUnlock(key)
        switch key {
        case .digit(let number): inputDigit(number)
        case .decimal: inputDecimal()
        case .operation(let operation): setOperation(operation)
        case .equals: calculate()
        case .clear: reset()
        case .sign:
            if let value = Double(display), value != 0 { display = format(-value) }
        case .percent:
            if let value = Double(display) { display = format(value / 100) }
        }
    }

    private func trackUnlock(_ key: Key) {
        let target: [Key] = [.digit(1), .operation(.multiply), .digit(1), .equals]
        unlockSequence.append(key)
        if unlockSequence.count > target.count { unlockSequence.removeFirst() }
        if unlockSequence == target {
            unlockSequence.removeAll()
            session.unlock()
        } else if key == .clear {
            unlockSequence.removeAll()
        }
    }

    private func inputDigit(_ number: Int) {
        if startsNewNumber || display == "0" {
            display = String(number)
            startsNewNumber = false
        } else if display.count < 12 {
            display += String(number)
        }
    }

    private func inputDecimal() {
        if startsNewNumber { display = "0."; startsNewNumber = false }
        else if !display.contains(".") { display += "." }
    }

    private func setOperation(_ operation: Operation) {
        if let pendingOperation, let storedValue, !startsNewNumber, let current = Double(display) {
            display = format(pendingOperation.apply(storedValue, current))
        }
        storedValue = Double(display)
        pendingOperation = operation
        startsNewNumber = true
    }

    private func calculate() {
        guard let operation = pendingOperation,
              let lhs = storedValue,
              let rhs = Double(display) else { return }
        display = format(operation.apply(lhs, rhs))
        storedValue = nil
        pendingOperation = nil
        startsNewNumber = true
    }

    private func reset() {
        display = "0"
        storedValue = nil
        pendingOperation = nil
        startsNewNumber = true
    }

    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "错误" }
        if value.rounded() == value { return String(format: "%.0f", value) }
        return String(format: "%.9g", value)
    }
}

private struct CalculatorButton: View {
    let key: Key
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key.title)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(key.foreground)
                .frame(maxWidth: key == .digit(0) ? .infinity : diameter, minHeight: diameter)
                .background(key.background)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.accessibilityLabel)
    }
}

enum Operation: String, Equatable {
    case add, subtract, multiply, divide

    func apply(_ lhs: Double, _ rhs: Double) -> Double {
        switch self {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return rhs == 0 ? .nan : lhs / rhs
        }
    }
}

enum Key: Identifiable, Equatable {
    case digit(Int), decimal, equals, clear, sign, percent, operation(Operation)
    var id: String { title + accessibilityLabel }

    var title: String {
        switch self {
        case .digit(let number): return String(number)
        case .decimal: return "."
        case .equals: return "="
        case .clear: return "AC"
        case .sign: return "+/−"
        case .percent: return "%"
        case .operation(.add): return "+"
        case .operation(.subtract): return "−"
        case .operation(.multiply): return "×"
        case .operation(.divide): return "÷"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .digit(let number): return String(number)
        case .decimal: return "小数点"
        case .equals: return "等于"
        case .clear: return "清除"
        case .sign: return "正负号"
        case .percent: return "百分号"
        case .operation(.add): return "加"
        case .operation(.subtract): return "减"
        case .operation(.multiply): return "乘"
        case .operation(.divide): return "除"
        }
    }

    var background: Color {
        switch self {
        case .operation, .equals: return Color.orange
        case .clear, .sign, .percent: return Color(white: 0.65)
        default: return Color(white: 0.20)
        }
    }

    var foreground: Color {
        switch self {
        case .clear, .sign, .percent: return .black
        default: return .white
        }
    }
}
