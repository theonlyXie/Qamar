import AppIntents
import Foundation

/// Siri / Shortcuts / iPhone Back Tap entry points.
/// Assign in Settings → Accessibility → Touch → Back Tap.
@available(iOS 16.0, *)
struct AskQamarIntent: AppIntent {
  static var title: LocalizedStringResource = "Ask Qamar"
  static var description = IntentDescription("Talk to Qamar about food or training without walking the in-app menu.")
  static var openAppWhenRun = true

  @Parameter(title: "Message")
  var message: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Ask Qamar \(\.$message)")
  }

  func perform() async throws -> some IntentResult {
    await MainActor.run {
      QamarQuickBridge.enqueue(action: "ask", text: message)
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct LogMealQamarIntent: AppIntent {
  static var title: LocalizedStringResource = "Log a meal with Qamar"
  static var description = IntentDescription("Tell Qamar what you ate. Nothing is saved until you confirm.")
  static var openAppWhenRun = true

  @Parameter(title: "What you ate")
  var meal: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$meal) with Qamar")
  }

  func perform() async throws -> some IntentResult {
    await MainActor.run {
      QamarQuickBridge.enqueue(action: "log", text: meal)
    }
    return .result()
  }
}

@available(iOS 16.0, *)
struct QamarShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    [
      AppShortcut(
        intent: AskQamarIntent(),
        phrases: [
          "Ask \(.applicationName)",
          "Talk to \(.applicationName)",
        ]
      ),
      AppShortcut(
        intent: LogMealQamarIntent(),
        phrases: [
          "Log a meal with \(.applicationName)",
          "Tell \(.applicationName) what I ate",
        ]
      ),
    ]
  }
}
