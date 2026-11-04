import SwiftUI

struct ContentView: View {
    @Binding var showVoiceSheet: Bool
    @State private var expenses: [ExpenseItem] = SharedExpenseStorage.shared.loadExpenses()
    @StateObject private var recorder = VoiceRecorderManager()

    private var todayTotalUZS: Double {
        let cal = Calendar.current
        return expenses
            .filter { !$0.isIncome && $0.currency.uppercased() != "USD" && cal.isDateInToday($0.createdAt) }
            .reduce(0) { $0 + $1.amount }
    }

    private var todayTotalUSD: Double {
        let cal = Calendar.current
        return expenses
            .filter { !$0.isIncome && $0.currency.uppercased() == "USD" && cal.isDateInToday($0.createdAt) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthTotalUZS: Double {
        let cal = Calendar.current
        let now = Date()
        return expenses
            .filter { !$0.isIncome && $0.currency.uppercased() != "USD" && cal.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var monthTotalUSD: Double {
        let cal = Calendar.current
        let now = Date()
        return expenses
            .filter { !$0.isIncome && $0.currency.uppercased() == "USD" && cal.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.04, green: 0.05, blue: 0.09)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ИСТОРИЯ ГОЛОСОВЫХ ЗАПИСЕЙ (\(expenses.count))")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if !expenses.isEmpty {
                                    Button(role: .destructive) {
                                        expenses.removeAll()
                                        SharedExpenseStorage.shared.clearAll()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                            Text("Очистить базу")
                                        }
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.red.opacity(0.14))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 4)

                            if expenses.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "waveform.circle")
                                        .font(.system(size: 38))
                                        .foregroundStyle(.green.opacity(0.7))
                                    Text("Записей пока нет")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text("Нажмите кнопку внизу и скажите, например:\n«200 тысяч хлеб и 50 тысяч чай»")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.03))
                                )
                            } else {
                                ForEach(expenses) { item in
                                    expenseRow(item)
                                }
                            }
                        }
                        .padding(.bottom, 95)
                    }
                    .padding()
                }

                Button {
                    showVoiceSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.title3.bold())
                        Text("Сказать расход голосом")
                            .font(.headline.bold())
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .green.opacity(0.35), radius: 16, y: 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("ChatterCash")
            .sheet(isPresented: $showVoiceSheet) {
                voiceCaptureSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                recorder.onAutoSave = { newItems, rawTranscript in
                    applyAndSaveItems(newItems, rawTranscript: rawTranscript)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        showVoiceSheet = false
                    }
                }
            }
        }
    }

    private func applyAndSaveItems(_ newItems: [ExpenseItem], rawTranscript: String) {
        let isExplicitCorrection = RussianVoiceParser.isCorrectionPhrase(rawTranscript)
        let now = Date()

        for newItem in newItems {
            let newStem = RussianVoiceParser.getItemStem(newItem.title)
            if newStem.count >= 2,
               let existingIdx = expenses.firstIndex(where: { existing in
                   let sameStem = RussianVoiceParser.getItemStem(existing.title) == newStem
                   let isRecent = now.timeIntervalSince(existing.createdAt) < 10 * 60
                   return sameStem && (isExplicitCorrection || isRecent)
               }) {
                expenses[existingIdx].title = newItem.title
                expenses[existingIdx].amount = newItem.amount
                expenses[existingIdx].currency = newItem.currency
                if newItem.category != .other {
                    expenses[existingIdx].category = newItem.category
                }
                if let pm = newItem.paymentMethod {
                    expenses[existingIdx].paymentMethod = pm
                }
                expenses[existingIdx].rawTranscript = rawTranscript
                expenses[existingIdx].createdAt = now
            } else {
                expenses.insert(newItem, at: 0)
            }
        }

        SharedExpenseStorage.shared.saveExpenses(expenses)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ПОТРАЧЕНО ЗА МЕСЯЦ")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(ExpenseItem.formatAmount(monthTotalUZS, currency: "UZS"))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if monthTotalUSD > 0 {
                        Text("+ \(ExpenseItem.formatAmount(monthTotalUSD, currency: "USD"))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.mint)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Сегодня")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ExpenseItem.formatAmount(todayTotalUZS, currency: "UZS"))
                        .font(.headline.bold())
                        .foregroundStyle(.green)
                    if todayTotalUSD > 0 {
                        Text("+ \(ExpenseItem.formatAmount(todayTotalUSD, currency: "USD"))")
                            .font(.caption.bold())
                            .foregroundStyle(.mint)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Text("✨ ИИ Gemini 2.5 Flash • Мгновенная запись голосом и автоисправление («Мясо было 100 000»)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.08, green: 0.11, blue: 0.18))
        )
    }

    private func expenseRow(_ item: ExpenseItem) -> some View {
        HStack(spacing: 12) {
            Text(item.category.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    if let bank = item.paymentMethod {
                        Text(bank)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text("«\(item.rawTranscript)»")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\(item.isIncome ? "+" : "-")\(item.formattedAmount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(item.isIncome ? .green : .white)

                Button {
                    expenses.removeAll { $0.id == item.id }
                    SharedExpenseStorage.shared.saveExpenses(expenses)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var voiceCaptureSheet: some View {
        VStack(spacing: 18) {
            Text("Голосовой ввод расхода")
                .font(.headline)
                .padding(.top, 12)

            Button {
                if recorder.isRecording {
                    recorder.finishAndSave()
                } else if !recorder.isParsingAI {
                    recorder.requestPermissionsAndStart()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 88, height: 88)
                        .shadow(color: recorder.isRecording ? .green.opacity(0.5) : .clear, radius: 20)

                    if recorder.isParsingAI {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: recorder.isRecording ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(recorder.isRecording ? .black : .white)
                    }
                }
            }

            Text(recorder.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Например: 200 000 хлеб и 50 000 чай", text: $recorder.transcript)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: recorder.transcript) { _, newValue in
                    recorder.previewItems = RussianVoiceParser.parseLocally(transcript: newValue)
                }

            if !recorder.previewItems.isEmpty {
                VStack(spacing: 8) {
                    ForEach(recorder.previewItems) { item in
                        HStack {
                            Text("\(item.category.emoji) \(item.title)")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("-\(item.formattedAmount)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        recorder.finishAndSave()
                    } label: {
                        Text(recorder.isParsingAI ? "ИИ Gemini обрабатывает..." : "Сохранить (\(recorder.previewItems.count))")
                            .font(.headline.bold())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(recorder.isParsingAI)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .background(Color(red: 0.06, green: 0.08, blue: 0.14))
        .onAppear {
            recorder.requestPermissionsAndStart()
        }
        .onDisappear {
            recorder.stopRecording()
        }
    }
}
