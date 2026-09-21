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

  /// An invitation code carried by a link, or nil: qamar://i/<code>,
  /// com.qamar.app://i/<code>, https://dr-qamar.com/i/<code>.
  static func inviteCode(in url: URL) -> String? {
    let scheme = (url.scheme ?? "").lowercased()
    let host = (url.host ?? "").lowercased()
    let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    if (scheme == "qamar" || scheme == "com.qamar.app") && host == "i", let code = parts.first {
      return code
    }
    if (scheme == "https" || scheme == "http") && (host == "dr-qamar.com" || host == "www.dr-qamar.com"),
       parts.count >= 2, parts[0] == "i" {
      return parts[1]
    }
    return nil
  }

  static func enqueue(url: URL) {
    if let code = inviteCode(in: url) {
      enqueue(action: "invite", text: code)
      return
    }
    guard url.scheme == "com.qamar.app" else { return }
    let host = url.host ?? ""
    let parts = url.path.split(separator: "/").map(String.init)
    var action: String?
    if host == "quick", let first = parts.first {
      action = first
    } else if host == "ask" || host == "log" || host == "plus" {
      action = host
    }
    guard let resolved = action, resolved == "ask" || resolved == "log" || resolved == "plus" else { return }
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
