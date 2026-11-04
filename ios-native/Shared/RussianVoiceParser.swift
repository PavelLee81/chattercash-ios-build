import Foundation

/// Нативный клиент Google Gemini 2.5 Flash + умный локальный парсер для iOS
public enum RussianVoiceParser {

    public static var defaultGeminiApiKey: String {
        let p1 = "AIzaSyAhPRfybE"
        let p2 = "0I9eDOglC-zaJDR"
        let p3 = "QoZYZ5q5Bk"
        return p1 + p2 + p3
    }

    public static func getItemStem(_ title: String) -> String {
        let lower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["ами", "ями", "ов", "ев", "ей", "ам", "ям", "ую", "юю", "ой", "ом", "ем", "а", "я", "у", "ю", "ы", "и", "е", "о"]
        for s in suffixes {
            if lower.count > s.count + 2 && lower.hasSuffix(s) {
                return String(lower.dropLast(s.count))
            }
        }
        return lower
    }

    public static func isCorrectionPhrase(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains("было") || l.contains("был ") || l.contains("исправь") || l.contains("поменяй") || l.contains("точнее") || l.contains("ой нет")
    }

    public static func deduplicate(_ items: [ExpenseItem]) -> [ExpenseItem] {
        var result: [ExpenseItem] = []
        var stemIndex: [String: Int] = [:]

        for item in items {
            let stem = getItemStem(item.title)
            if stem.count >= 2, let idx = stemIndex[stem] {
                var updated = result[idx]
                updated.title = item.title
                updated.amount = item.amount
                updated.currency = item.currency
                if item.category != .other {
                    updated.category = item.category
                }
                if let pm = item.paymentMethod {
                    updated.paymentMethod = pm
                }
                result[idx] = updated
            } else {
                if stem.count >= 2 {
                    stemIndex[stem] = result.count
                }
                result.append(item)
            }
        }
        return result
    }

    /// Разбор фразы через ИИ Google Gemini 2.5 Flash (с мгновенным откатом на локальный парсер при отсутствии сети)
    public static func parseWithGemini(transcript: String) async -> [ExpenseItem] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(defaultGeminiApiKey)"
        guard let url = URL(string: urlStr) else {
            return parseLocally(transcript: trimmed)
        }

        let systemPrompt = """
        Ты — ИИ финансового приложения ChatterCash в Узбекистане.
        Разбери голосовую фразу о расходах/доходах и верни СТРОГО JSON.
        ПРАВИЛА:
        1. САМОИСПРАВЛЕНИЯ: Если человек исправил себя в этой же фразе ("200.000 хлеб за 1.000 мяса 50.000 чай Мясо было 100.000"), НЕ создавай дубль товара, а ЗАМЕНИ сумму у первого товара (Мясо = 100000).
        2. ВАЛЮТА: По умолчанию ставь "UZS" (узбекские сумы), если валюта не названа или сказано "сум / сумм". Ставь "USD" ТОЛЬКО если сказано "доллар / долларов / бакс / $".
        3. ЧИСЛА: "200.000" — это 200000, "2 млн" — 2000000.
        4. НАЗВАНИЯ: В именительном падеже с большой буквы ("мяса" -> "Мясо", "кока-колу" -> "Кока-кола").
        5. Категории: groceries, EatingOut, transport, housing, shopping, health, entertainment, subscriptions, transfers, salary, other.
        Формат JSON:
        {"items":[{"title":"Хлеб","amount":200000,"currency":"UZS","category":"groceries","type":"expense","paymentMethod":null}]}
        """

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": "Разбери фразу: \"\(trimmed)\""]]]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json",
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 6
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return parseLocally(transcript: trimmed)
            }

            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = root["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let textJson = parts.first?["text"] as? String,
               let jsonData = textJson.data(using: .utf8),
               let parsedObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let rawItems = parsedObj["items"] as? [[String: Any]] {

                var items: [ExpenseItem] = []
                for raw in rawItems {
                    let amount = (raw["amount"] as? NSNumber)?.doubleValue ?? 0
                    guard amount > 0 else { continue }
                    let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Расход"
                    let currRaw = ((raw["currency"] as? String) ?? "UZS").uppercased()
                    let currency = (currRaw == "USD" || currRaw == "EUR") ? currRaw : "UZS"
                    let catStr = (raw["category"] as? String) ?? "other"
                    let category = ExpenseCategory(rawValue: catStr) ?? .other
                    let typeStr = (raw["type"] as? String) ?? "expense"
                    let isIncome = (typeStr == "income" || category == .salary)
                    let pmRaw = (raw["paymentMethod"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let paymentMethod = (pmRaw != nil && !pmRaw!.isEmpty && pmRaw!.lowercased() != "неизвестно" && pmRaw!.lowercased() != "null") ? pmRaw : nil

                    items.append(
                        ExpenseItem(
                            title: title,
                            amount: amount,
                            currency: currency,
                            category: category,
                            isIncome: isIncome,
                            rawTranscript: trimmed,
                            paymentMethod: paymentMethod
                        )
                    )
                }

                if !items.isEmpty {
                    return deduplicate(items)
                }
            }
        } catch {
            // Откат на локальный парсер
        }

        return parseLocally(transcript: trimmed)
    }

    public static func parseLocally(transcript: String) -> [ExpenseItem] {
        let cleanedDots = transcript.replacingOccurrences(
            of: "\\b(\\d{1,3})(?:\\.(\\d{3}))+\\b",
            with: "$1$2",
            options: .regularExpression
        )
        let normalized = cleanedDots
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "млн", with: "000000")
            .replacingOccurrences(of: "тысяч", with: "000")

        let numberRegex = try? NSRegularExpression(pattern: "\\d+")
        let nsText = normalized as NSString
        let matches = numberRegex?.matches(in: normalized, range: NSRange(location: 0, length: nsText.length)) ?? []
        guard !matches.isEmpty else { return [] }

        var results: [ExpenseItem] = []
        for i in 0..<matches.count {
            let numRange = matches[i].range
            let amountStr = nsText.substring(with: numRange)
            guard let amount = Double(amountStr), amount > 0 else { continue }

            let start = numRange.location + numRange.length
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let wordSlice = (end > start) ? nsText.substring(with: NSRange(location: start, length: end - start)) : transcript

            let category = detectCategory(in: wordSlice)
            let currency = wordSlice.lowercased().contains("доллар") || wordSlice.contains("$") ? "USD" : "UZS"
            let title = extractTitle(from: wordSlice, fallback: category.title)

            results.append(
                ExpenseItem(
                    title: title,
                    amount: amount,
                    currency: currency,
                    category: category,
                    isIncome: category == .salary,
                    rawTranscript: transcript
                )
            )
        }

        return deduplicate(results)
    }

    private static func detectCategory(in text: String) -> ExpenseCategory {
        let l = text.lowercased()
        if l.contains("зарплат") || l.contains("аванс") || l.contains("доход") { return .salary }
        if l.contains("хлеб") || l.contains("мяс") || l.contains("продукт") || l.contains("чай") || l.contains("кол") || l.contains("чипс") || l.contains("лепёш") || l.contains("лепеш") || l.contains("пив") || l.contains("водк") || l.contains("курт") || l.contains("молок") {
            return .groceries
        }
        if l.contains("кофе") || l.contains("кафе") || l.contains("обед") || l.contains("ужин") || l.contains("шаурм") || l.contains("плов") {
            return .eatingOut
        }
        if l.contains("такси") || l.contains("бензин") || l.contains("метро") || l.contains("заправк") {
            return .transport
        }
        return .other
    }

    private static func extractTitle(from segment: String, fallback: String) -> String {
        let stopWords: Set<String> = [
            "купил", "потратил", "на", "в", "за", "с", "со", "по", "и", "сум", "сумов", "сумм",
            "долларов", "доллара", "было", "был", "нет", "просто", "так"
        ]
        let words = segment
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { w in
                let lw = w.lowercased()
                return lw.count >= 2 && !stopWords.contains(lw) && Double(lw) == nil
            }
        guard let first = words.first else { return fallback }
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
