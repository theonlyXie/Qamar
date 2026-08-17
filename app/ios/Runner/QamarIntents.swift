import Foundation
import Flutter

/// Holds a Back Tap / Siri / URL request until Flutter is ready to consume it.
enum QamarQuickBridge {
  static let actionKey = "qamar.pending.action"
  static let textKey = "qamar.pending.text"
  static var eventSink: FlutterEventSink?

  static func enqueue(action: String, text: String?) {
    UserDefaults.standard.set(action, forKey: actionKey)
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      UserDefaults.standard.set(text, forKey: textKey)
    } else {
      UserDefaults.standard.removeObject(forKey: textKey)
    }
    if let sink = eventSink {
      var payload: [String: String] = ["action": action]
      if let text, !text.isEmpty { payload["text"] = text }
      sink(payload)
      clear()
    }
  }

  static func enqueue(url: URL) {
    guard url.scheme == "com.qamar.app" else { return }
    let host = url.host ?? ""
    let parts = url.path.split(separator: "/").map(String.init)
    var action: String?
    if host == "quick", let first = parts.first {
      action = first
    } else if host == "ask" || host == "log" {
      action = host
    }
    guard let resolved = action, resolved == "ask" || resolved == "log" else { return }
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let text = comps?.queryItems?.first(where: { $0.name == "q" || $0.name == "text" })?.value
    enqueue(action: resolved, text: text)
  }

  static func take() -> [String: String]? {
    guard let action = UserDefaults.standard.string(forKey: actionKey) else { return nil }
    let text = UserDefaults.standard.string(forKey: textKey)
    clear()
    var payload: [String: String] = ["action": action]
    if let text, !text.isEmpty { payload["text"] = text }
    return payload
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: actionKey)
    UserDefaults.standard.removeObject(forKey: textKey)
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "com.qamar.app/quick", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
      if call.method == "takePending" {
        result(take())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let events = FlutterEventChannel(name: "com.qamar.app/quick_events", binaryMessenger: messenger)
    events.setStreamHandler(QamarQuickStreamHandler())
  }
}

final class QamarQuickStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    QamarQuickBridge.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    QamarQuickBridge.eventSink = nil
    return nil
  }
}
