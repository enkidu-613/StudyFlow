import Cocoa
import FlutterMacOS
import UserNotifications

final class StudyFlowPlatform {
  private static let channelName = "studyflow/platform"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "scheduleReminder":
        scheduleReminder(call: call, result: result)
      case "cancelReminder":
        cancelReminder(call: call, result: result)
      case "playAlarm":
        playAlarm(call: call, result: result)
      case "startFocusSession":
        startFocusSession(call: call, result: result)
      case "getUsageSummary":
        result(unsupported("Usage summaries require separate Screen Time authorization."))
      case "applyRestriction", "clearRestriction":
        result(unsupported("Device restrictions require separate authorization."))
      case "getPermissionStatus":
        getPermissionStatus(result: result)
      case "requestPermission":
        requestPermission(call: call, result: result)
      case "showUnavailablePermission":
        showUnavailablePermission(call: call, result: result)
      case "openPermissionSettings":
        openPermissionSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func scheduleReminder(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let atMillis = arguments["at"] as? NSNumber else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Reminder arguments are missing.",
          details: nil))
      return
    }
    let title = arguments["title"] as? String ?? "StudyFlow reminder"
    let text = arguments["text"] as? String ?? "Scheduled block"
    let identifier =
      arguments["id"] as? String ?? UUID().uuidString
    authorizeIfNeeded { granted in
      guard granted else {
        result(
          FlutterError(
            code: "permission_denied",
            message: "Notifications are not authorized.",
            details: nil))
        return
      }
      let interval = max(
        0.1,
        atMillis.doubleValue / 1000.0 - Date().timeIntervalSince1970)
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = text
      content.sound = .default
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: interval,
        repeats: false)
      let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: trigger)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          result(
            FlutterError(
              code: "internal_error",
              message: error.localizedDescription,
              details: nil))
        } else {
          result(["kind": "supported", "message": "Reminder scheduled."])
        }
      }
    }
  }

  private static func cancelReminder(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let identifier = arguments["id"] as? String else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Reminder identifier is missing.",
          details: nil))
      return
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [identifier])
    result(["kind": "supported", "message": "Reminder cancelled."])
  }

  private static func playAlarm(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let title = arguments["title"] as? String,
          let text = arguments["text"] as? String else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Alarm arguments are missing.",
          details: nil))
      return
    }
    let sound = NSSound(named: "Glass")
      ?? NSSound(named: "Ping")
    sound?.volume = 1.0
    sound?.loops = true
    sound?.play()
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = title
      alert.informativeText = text
      alert.addButton(withTitle: "OK")
      if let window = NSApp.mainWindow ?? NSApp.windows.first {
        alert.beginSheetModal(for: window) { _ in
          sound?.stop()
          result(["kind": "supported", "message": "Alarm played."])
        }
      } else {
        alert.runModal()
        sound?.stop()
        result(["kind": "supported", "message": "Alarm played."])
      }
    }
  }

  private static func startFocusSession(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Focus arguments are missing.",
          details: nil))
      return
    }
    let title = arguments["title"] as? String ?? "StudyFlow focus"
    authorizeIfNeeded { granted in
      guard granted else {
        result(
          FlutterError(
            code: "permission_denied",
            message: "Notifications are not authorized.",
            details: nil))
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = "Focus session started."
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          result(
            FlutterError(
              code: "internal_error",
              message: error.localizedDescription,
              details: nil))
        } else {
          result(["kind": "supported", "message": "Focus notification posted."])
        }
      }
    }
  }

  private static func getPermissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let authorized =
        settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional
      let notificationDetail = authorized ? "authorized" : "not authorized"
      let states: [[String: Any]] = [
        [
          "id": "notifications",
          "available": true,
          "allowed": authorized,
          "detail": notificationDetail,
        ],
        [
          "id": "userNotifications",
          "available": true,
          "allowed": authorized,
          "detail": notificationDetail,
        ],
        [
          "id": "exactAlarm",
          "available": false,
          "allowed": false,
          "detail": "not applicable on macOS",
        ],
        [
          "id": "background",
          "available": true,
          "allowed": true,
          "detail": "window and background status visible",
        ],
        [
          "id": "batteryOptimization",
          "available": false,
          "allowed": false,
          "detail": "not applicable on macOS",
        ],
        [
          "id": "usageAccess",
          "available": false,
          "allowed": false,
          "detail": "requires separate Screen Time authorization",
        ],
        [
          "id": "menuBar",
          "available": true,
          "allowed": NSApp.activationPolicy() == .accessory,
          "detail": "menu bar status",
        ],
        [
          "id": "focus",
          "available": true,
          "allowed": true,
          "detail": "in-app focus workflow",
        ],
      ]
      result(states)
    }
  }

  private static func requestPermission(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let id = arguments["id"] as? String else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Permission id is missing.",
          details: nil))
      return
    }

    // Only notification permissions have a system authorization prompt on
    // macOS. Everything else is either app-internal or Android-only.
    guard id == "notifications" || id == "userNotifications" else {
      result(FlutterError(
        code: "unsupported",
        message: "This permission is not requestable on macOS.",
        details: nil))
      return
    }

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        result(["granted": true, "status": "authorized"])
      case .denied:
        // macOS never re-prompts after a denial; open the notification
        // settings pane so the user can flip the switch there.
        openNotificationSettingsPane()
        result(FlutterError(
          code: "permission_denied",
          message: "Notifications are denied. Open System Settings to allow them.",
          details: nil))
      default:
        // .notDetermined (and .ephemeral): present the system prompt.
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error = error {
            result(FlutterError(
              code: "internal_error",
              message: error.localizedDescription,
              details: nil))
          } else {
            result([
              "granted": granted,
              "status": granted ? "authorized" : "declined",
            ])
          }
        }
      }
    }
  }

  private static func openNotificationSettingsPane() {
    let urls = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for urlString in urls {
      if let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
        return
      }
    }
  }

  private static func openPermissionSettings(result: @escaping FlutterResult) {
    openNotificationSettingsPane()
    result(true)
  }

  private static func showUnavailablePermission(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let title = arguments["title"] as? String,
          let message = arguments["message"] as? String else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Unavailable permission arguments are missing.",
          details: nil))
      return
    }
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.messageText = title
      alert.informativeText = message
      alert.addButton(withTitle: "OK")
      alert.runModal()
      result(true)
    }
  }

  private static func authorizeIfNeeded(completion: @escaping (Bool) -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional:
        completion(true)
      case .denied:
        completion(false)
      default:
        center.requestAuthorization(options: [.alert, .sound, .badge]) {
          granted,
          _ in
          completion(granted)
        }
      }
    }
  }

  private static func unsupported(_ message: String) -> [String: String] {
    ["kind": "unsupported", "message": message]
  }
}
