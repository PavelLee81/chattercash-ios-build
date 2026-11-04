import AudioToolbox
import AVFoundation
import Foundation
import Speech
import UIKit

@MainActor
public final class VoiceRecorderManager: ObservableObject {
    @Published public var isRecording: Bool = false
    @Published public var isParsingAI: Bool = false
    @Published public var transcript: String = ""
    @Published public var statusText: String = "Нажмите на микрофон или говорите..."
    @Published public var previewItems: [ExpenseItem] = []

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var hasSavedCurrentSession: Bool = false

    public var onAutoSave: (([ExpenseItem], String) -> Void)?

    public init() {}

    public func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self = self else { return }
                if authStatus == .authorized {
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        Task { @MainActor in
                            if granted {
                                self.startRecording()
                            } else {
                                self.statusText = "Разрешите доступ к микрофону в Настройках iOS"
                            }
                        }
                    }
                } else {
                    self.statusText = "Разрешите доступ к распознаванию речи в Настройках iOS"
                }
            }
        }
    }

    public func startRecording() {
        stopRecording()
        hasSavedCurrentSession = false
        isParsingAI = false
        transcript = ""
        previewItems = []

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusText = "Не удалось активировать микрофон iPhone"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            statusText = "🎤 Слушаю... Говорите спокойно, можно несколько покупок подряд"
        } catch {
            statusText = "Ошибка запуска аудиодвижка"
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    let spoken = result.bestTranscription.formattedString
                    if !spoken.isEmpty {
                        self.transcript = spoken
                        self.previewItems = RussianVoiceParser.parseLocally(transcript: spoken)
                        self.resetSilenceTimer()
                    }
                }
                if error != nil {
                    self.stopAudioOnly()
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.hasSavedCurrentSession {
                    self.finishAndSave()
                }
            }
        }
    }

    public func finishAndSave() {
        guard !hasSavedCurrentSession else { return }
        let currentTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTranscript.isEmpty else {
            statusText = "Скажите например: «200 тысяч хлеб и 50 тысяч чай»"
            return
        }

        hasSavedCurrentSession = true
        silenceTimer?.invalidate()
        stopAudioOnly()
        isParsingAI = true
        statusText = "✨ ИИ Gemini 2.5 проверяет и сохраняет..."

        Task { @MainActor in
            let items = await RussianVoiceParser.parseWithGemini(transcript: currentTranscript)
            self.isParsingAI = false

            guard !items.isEmpty else {
                self.hasSavedCurrentSession = false
                self.statusText = "Не удалось распознать сумму. Попробуйте ещё раз"
                return
            }

            self.previewItems = items
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1407) // Приятный фирменный звук Apple Pay / iOS
            self.statusText = "✅ Записано (\(items.count))!"
            self.onAutoSave?(items, currentTranscript)
        }
    }

    public func stopRecording() {
        silenceTimer?.invalidate()
        stopAudioOnly()
    }

    private func stopAudioOnly() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}
