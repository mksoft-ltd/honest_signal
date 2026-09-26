import Flutter
import UIKit

enum BudgetFileStore {
  static let directoryName = "HonestSignalLocal"
  static let fileName = "budget.json"

  static func excludeFromBackup(_ url: URL) throws {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutableURL.setResourceValues(values)
  }

  static func directory() throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = root.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try excludeFromBackup(directory)
    return directory
  }

  static func read(day: String, in storageDirectory: URL? = nil) throws -> Int64 {
    let file = try (storageDirectory ?? directory()).appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: file),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["day"] as? String == day
    else { return 0 }
    return (json["used"] as? NSNumber)?.int64Value ?? 0
  }

  static func write(day: String, used: Int64, in storageDirectory: URL? = nil) throws {
    let directory = try storageDirectory ?? self.directory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try excludeFromBackup(directory)
    let file = directory.appendingPathComponent(fileName)
    let data = try JSONSerialization.data(withJSONObject: ["day": day, "used": used])
    try data.write(to: file, options: .atomic)
    try excludeFromBackup(file)
  }

  static func access(
    day: String,
    spending bytes: Int64 = 0,
    in storageDirectory: URL? = nil
  ) throws -> Int64 {
    let used = try read(day: day, in: storageDirectory) + max(0, bytes)
    try write(day: day, used: used, in: storageDirectory)
    return used
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.froggyeye.honestsignal/budget",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "excludeFromBackup" {
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        do {
          try BudgetFileStore.excludeFromBackup(URL(fileURLWithPath: path, isDirectory: true))
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "backup_exclusion_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      guard call.method == "budgetRead" || call.method == "budgetSpend",
        let arguments = call.arguments as? [String: Any],
        let day = arguments["day"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let bytes =
          call.method == "budgetSpend"
          ? (arguments["bytes"] as? NSNumber)?.int64Value ?? 0
          : 0
        let used = try BudgetFileStore.access(day: day, spending: bytes)
        result(["day": day, "used": used])
      } catch {
        result(
          FlutterError(code: "budget_io_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
