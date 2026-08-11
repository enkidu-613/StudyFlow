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
      case "startFocusSession":
        startFocusSession(call: call, result: result)
      case "getUsageSummary":
        result(unsupported("Usage summaries require separate Screen Time authorization."))
      case "applyRestriction", "clearRestriction":
        result(unsupported("Device restrictions require separate authorization."))
      case "getPermissionStatus":
        getPermissionStatus(result: result)
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
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: interval,
        repeats: false)
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
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
