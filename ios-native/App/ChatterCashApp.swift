import AppIntents
import SwiftUI

struct LaunchVoiceRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Записать расход голосом"
    static var description = IntentDescription("Мгновенно открывает ChatterCash и включает микрофон для записи трат.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("ChatterCashTriggerMic"), object: nil)
        return .result()
    }
}

@main
struct ChatterCashApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showVoiceSheetFromShade: Bool = true

    var body: some Scene {
        WindowGroup {
            ContentView(showVoiceSheet: $showVoiceSheetFromShade)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.scheme == "chattercash" || url.absoluteString.contains("voice=1") {
                        showVoiceSheetFromShade = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ChatterCashTriggerMic"))) { _ in
                    showVoiceSheetFromShade = true
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        showVoiceSheetFromShade = true
                    }
                }
        }
    }
}
