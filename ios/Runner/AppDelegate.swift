import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var emailChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let launchURL = launchOptions?[.url] as? URL {
      pendingDeepLink = launchURL.absoluteString
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      deepLinkChannel = FlutterMethodChannel(name: "soulbuddy/deep_links", binaryMessenger: controller.binaryMessenger)
      deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialLink" {
          result(self?.pendingDeepLink)
          self?.pendingDeepLink = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      emailChannel = FlutterMethodChannel(name: "soulbuddy/email", binaryMessenger: controller.binaryMessenger)
      emailChannel?.setMethodCallHandler { call, result in
        guard call.method == "composeEmail",
              let arguments = call.arguments as? [String: String] else {
          result(FlutterMethodNotImplemented)
          return
        }
        var components = URLComponents(string: "mailto:")!
        components.queryItems = [
          URLQueryItem(name: "subject", value: arguments["subject"] ?? ""),
          URLQueryItem(name: "body", value: arguments["body"] ?? "")
        ]
        guard let url = components.url else {
          result(FlutterError(code: "INVALID_EMAIL_URL", message: "Не удалось подготовить письмо", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened {
            result(true)
          } else {
            result(FlutterError(code: "NO_EMAIL_APP", message: "На устройстве нет почтового приложения", details: nil))
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    pendingDeepLink = url.absoluteString
    deepLinkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
    return true
  }
}
