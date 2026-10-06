import Flutter
import UIKit
import Speech
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "pargig/speech_file"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps key, read from Info.plist rather than hardcoded here so
    // the key stays out of source control (see ios/Runner/Keys.xcconfig).
    // Missing key => maps render blank instead of crashing the app.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("[Pargig] GMSApiKey missing — Google Maps will not render.")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Transcribes an already-recorded file with the phone's own speech
    // recogniser. The microphone can only serve one consumer at a time,
    // so recognising the finished recording — rather than listening live
    // alongside it — is what lets a single take produce both the stored
    // audio and the written description.
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: engineBridge.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(SFSpeechRecognizer() != nil)
      case "transcribeFile":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(nil)
          return
        }
        AppDelegate.transcribe(path: path, completion: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Always calls back exactly once with ["text": String?, "error":
  /// String?]. Never a Flutter error — the recording is the primary
  /// artefact and must not be jeopardised by a missing transcript. The
  /// reason is reported so a failure is diagnosable on a real device
  /// instead of just silently producing no text.
  private static func transcribe(
    path: String,
    completion: @escaping FlutterResult
  ) {
    func fail(_ reason: String) {
      completion(["text": nil, "error": reason])
    }

    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          fail("Speech recognition permission denied")
          return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
          fail("No speech recogniser available for this language")
          return
        }

        let request = SFSpeechURLRecognitionRequest(
          url: URL(fileURLWithPath: path)
        )
        request.shouldReportPartialResults = false
        // Keep it local: no audio leaves the device.
        if recognizer.supportsOnDeviceRecognition {
          request.requiresOnDeviceRecognition = true
        }

        var settled = false
        recognizer.recognitionTask(with: request) { response, error in
          guard !settled else { return }
          if let error = error {
            settled = true
            fail(error.localizedDescription)
            return
          }
          guard let response = response, response.isFinal else { return }
          settled = true
          let text = response.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if text.isEmpty {
            fail("Nothing recognisable was heard")
          } else {
            completion(["text": text, "error": nil])
          }
        }
      }
    }
  }
}
