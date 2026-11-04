import Foundation

public enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case groceries = "groceries"
    case eatingOut = "EatingOut"
    case transport = "transport"
    case housing = "housing"
    case shopping = "shopping"
    case health = "health"
    case entertainment = "entertainment"
    case subscriptions = "subscriptions"
    case transfers = "transfers"
    case salary = "salary"
    case other = "other"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .groceries: return "Продукты"
        case .eatingOut: return "Кафе и Еда"
        case .transport: return "Транспорт"
        case .housing: return "Жильё и ЖКХ"
        case .shopping: return "Покупки"
        case .health: return "Здоровье"
        case .entertainment: return "Развлечения"
        case .subscriptions: return "Подписки"
        case .transfers: return "Переводы"
        case .salary: return "Доход"
        case .other: return "Другое"
        }
    }

    public var emoji: String {
        switch self {
        case .groceries: return "🛒"
        case .eatingOut: return "☕"
        case .transport: return "🚕"
        case .housing: return "🏠"
        case .shopping: return "🛍️"
        case .health: return "💊"
        case .entertainment: return "🎬"
        case .subscriptions: return "🔄"
        case .transfers: return "💸"
        case .salary: return "💰"
        case .other: return "📦"
        }
    }
}

public struct ExpenseItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var amount: Double
    public var currency: String // "UZS" или "USD"
    public var category: ExpenseCategory
    public var isIncome: Bool
    public var rawTranscript: String
    public var paymentMethod: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        currency: String = "UZS",
        category: ExpenseCategory,
        isIncome: Bool = false,
        rawTranscript: String,
        paymentMethod: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currency = currency
        self.category = category
        self.isIncome = isIncome
        self.rawTranscript = rawTranscript
        self.paymentMethod = paymentMethod
        self.createdAt = createdAt
    }

    public var formattedAmount: String {
        return ExpenseItem.formatAmount(amount, currency: currency)
    }

    public static func formatAmount(_ value: Double, currency: String = "UZS") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        let numStr = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        if currency.uppercased() == "USD" {
            return "\(numStr) $"
        } else if currency.uppercased() == "EUR" {
            return "\(numStr) €"
        }
        return numStr
    }
}

public final class SharedExpenseStorage {
    public static let shared = SharedExpenseStorage()
    private let storageKey = "chattercash_native_ios_v2"

    public func loadExpenses() -> [ExpenseItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([ExpenseItem].self, from: data) else {
            return []
        }
        return items
    }

    public func saveExpenses(_ items: [ExpenseItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    public func todaySpentTotal(currency: String = "UZS") -> Double {
        let cal = Calendar.current
        return loadExpenses()
            .filter { !$0.isIncome && $0.currency.uppercased() == currency.uppercased() && cal.isDateInToday($0.createdAt) }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthSpentTotal(currency: String = "UZS") -> Double {
        let cal = Calendar.current
        let now = Date()
        return loadExpenses()
            .filter { !$0.isIncome && $0.currency.uppercased() == currency.uppercased() && cal.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }
}
