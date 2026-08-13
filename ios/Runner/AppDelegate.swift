import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Claim the notification centre delegate before the app finishes launching,
    // which is the only window iOS accepts it in. Without this a locally
    // scheduled reminder still fires, but tapping it reaches nothing — the
    // payload never reaches Dart, so the challenge deep link silently does
    // nothing. Setting it does not request permission; that is asked for from
    // Dart after the player's first win.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate =
        self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
