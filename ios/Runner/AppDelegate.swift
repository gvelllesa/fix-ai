import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let netBindChannel = FlutterMethodChannel(name: "fixai/netbind",
                                              binaryMessenger: controller.binaryMessenger)
    netBindChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "bindWifi":
        // iOS automatically routes local subnet traffic to the active Wi-Fi interface without bindProcessToNetwork
        result(true)
      case "unbind":
        result(true)
      case "keepScreenOn":
        if let args = call.arguments as? [String: Any], let enable = args["enable"] as? Bool {
          UIApplication.shared.isIdleTimerDisabled = enable
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
