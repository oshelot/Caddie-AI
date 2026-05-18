import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // KAN-410: OAuth hosted-UI channels.
  //   caddieai/auth     (MethodChannel) — `launchUrl` opens the Cognito
  //                     hosted UI in an ASWebAuthenticationSession.
  //   caddieai/deeplink (EventChannel)  — streams the `caddieai://callback`
  //                     redirect back to Dart (see auth_service.dart).
  // Mirrors the Android contract in MainActivity.kt so the Dart layer is
  // platform-agnostic.
  private var deeplinkSink: FlutterEventSink?
  private var webAuthSession: ASWebAuthenticationSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CaddieAuthChannel") {
      setupAuthChannels(messenger: registrar.messenger())
    }
  }

  private func setupAuthChannels(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "caddieai/auth", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        if call.method == "launchUrl",
           let urlString = call.arguments as? String,
           let url = URL(string: urlString) {
          self?.startWebAuth(url: url)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(name: "caddieai/deeplink", binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func startWebAuth(url: URL) {
    let session = ASWebAuthenticationSession(
      url: url, callbackURLScheme: "caddieai"
    ) { [weak self] callbackURL, error in
      if let callbackURL = callbackURL {
        self?.deeplinkSink?(callbackURL.absoluteString)
      } else if let err = error as? ASWebAuthenticationSessionError,
                err.code == .canceledLogin {
        self?.deeplinkSink?("caddieai://callback?error=canceled")
      } else if error != nil {
        self?.deeplinkSink?("caddieai://callback?error=session_failed")
      }
      self?.webAuthSession = nil
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    webAuthSession = session
    session.start()
  }
}

// MARK: - Deep-link EventChannel

extension AppDelegate: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    deeplinkSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    deeplinkSink = nil
    return nil
  }
}

// MARK: - ASWebAuthenticationSession presentation

extension AppDelegate: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(
    for session: ASWebAuthenticationSession
  ) -> ASPresentationAnchor {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow } ?? ASPresentationAnchor()
  }
}
