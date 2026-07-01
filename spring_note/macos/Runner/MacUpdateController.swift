import Cocoa
import FlutterMacOS
import Sparkle

final class MacUpdateController: NSObject, FlutterStreamHandler, SPUUpdaterDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var feedURL: URL?
  private var updater: SPUUpdater?
  private var userDriver: MacUpdateUserDriver?

  func attach(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "spring_note/mac_update",
      binaryMessenger: messenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    eventChannel = FlutterEventChannel(
      name: "spring_note/mac_update_events",
      binaryMessenger: messenger
    )
    eventChannel?.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "installUpdate":
      guard let arguments = call.arguments as? [String: Any],
            let feedURLString = arguments["feedUrl"] as? String,
            let url = URL(string: feedURLString) else {
        result(FlutterError(code: "bad_args", message: "installUpdate expects feedUrl", details: nil))
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.installUpdate(feedURL: url, result: result)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installUpdate(feedURL: URL, result: @escaping FlutterResult) {
    guard updater?.sessionInProgress != true else {
      result(FlutterError(
        code: "update_in_progress",
        message: "An update is already in progress.",
        details: nil
      ))
      return
    }

    self.feedURL = feedURL
    do {
      let updater = try ensureUpdater()
      emit(["type": "preparing"])
      updater.checkForUpdates()
      result(nil)
    } catch {
      result(FlutterError(
        code: "start_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func ensureUpdater() throws -> SPUUpdater {
    if let updater {
      return updater
    }

    let hostBundle = Bundle.main
    let driver = MacUpdateUserDriver { [weak self] event in
      self?.emit(event)
    }
    let updater = SPUUpdater(
      hostBundle: hostBundle,
      applicationBundle: hostBundle,
      userDriver: driver,
      delegate: self
    )
    try updater.start()
    updater.automaticallyChecksForUpdates = false
    updater.automaticallyDownloadsUpdates = false
    updater.sendsSystemProfile = false
    _ = updater.clearFeedURLFromUserDefaults()

    self.userDriver = driver
    self.updater = updater
    return updater
  }

  private func emit(_ event: [String: Any]) {
    guard let eventSink else {
      return
    }
    eventSink(event)
  }

  private func prepareForRelaunch() {
    (NSApp.delegate as? AppDelegate)?.trayController.prepareForApplicationExit()
  }

  func feedURLString(for updater: SPUUpdater) -> String? {
    feedURL?.absoluteString
  }

  func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
    false
  }

  func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
    false
  }

  func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
    true
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    prepareForRelaunch()
    emit(["type": "relaunching"])
  }

  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
    prepareForRelaunch()
    emit(["type": "installing"])
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    emit([
      "type": "notFound",
      "message": error.localizedDescription,
    ])
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    emit([
      "type": "error",
      "message": error.localizedDescription,
    ])
  }
}

private final class MacUpdateUserDriver: NSObject, SPUUserDriver {
  private let emitEvent: ([String: Any]) -> Void
  private var expectedContentLength: UInt64?
  private var receivedContentLength: UInt64 = 0

  init(emitEvent: @escaping ([String: Any]) -> Void) {
    self.emitEvent = emitEvent
    super.init()
  }

  func show(
    _ request: SPUUpdatePermissionRequest,
    reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(SUUpdatePermissionResponse(
      automaticUpdateChecks: false,
      sendSystemProfile: false
    ))
  }

  @objc(showUserInitiatedUpdateCheckWithCancellation:)
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    emit(["type": "preparing"])
  }

  @objc(showUpdateFoundWithAppcastItem:state:reply:)
  func showUpdateFound(
    with appcastItem: SUAppcastItem,
    state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    guard appcastItem.fileURL != nil else {
      emit([
        "type": "error",
        "message": "此更新没有可安装的 macOS 包。",
      ])
      reply(dismissChoice)
      return
    }
    reply(installChoice)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    emit([
      "type": "notFound",
      "message": error.localizedDescription,
    ])
    acknowledgement()
  }

  func showUpdaterError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    emit([
      "type": "error",
      "message": error.localizedDescription,
    ])
    acknowledgement()
  }

  @objc(showDownloadInitiatedWithCancellation:)
  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    expectedContentLength = nil
    receivedContentLength = 0
    emitDownloadProgress()
  }

  @objc(showDownloadDidReceiveExpectedContentLength:)
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    self.expectedContentLength = expectedContentLength
    emitDownloadProgress()
  }

  @objc(showDownloadDidReceiveDataOfLength:)
  func showDownloadDidReceiveData(ofLength length: UInt64) {
    receivedContentLength += length
    emitDownloadProgress()
  }

  @objc(showDownloadDidStartExtractingUpdate)
  func showDownloadDidStartExtractingUpdate() {
    emit([
      "type": "extracting",
      "fraction": 0.0,
    ])
  }

  @objc(showExtractionReceivedProgress:)
  func showExtractionReceivedProgress(_ progress: Double) {
    emit([
      "type": "extracting",
      "fraction": min(max(progress, 0.0), 1.0),
    ])
  }

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    emit(["type": "relaunching"])
    reply(installChoice)
  }

  @objc(showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:)
  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    emit([
      "type": applicationTerminated ? "installing" : "relaunching",
    ])
  }

  @objc(showUpdateInstalledAndRelaunched:acknowledgement:)
  func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool,
    acknowledgement: @escaping () -> Void
  ) {
    emit([
      "type": "installed",
      "relaunched": relaunched,
    ])
    acknowledgement()
  }

  @objc(dismissUpdateInstallation)
  func dismissUpdateInstallation() {
    emit(["type": "dismissed"])
  }

  @objc(showUpdateInFocus)
  func showUpdateInFocus() {
    emit(["type": "focus"])
  }

  private var installChoice: SPUUserUpdateChoice {
    SPUUserUpdateChoice(rawValue: 1)!
  }

  private var dismissChoice: SPUUserUpdateChoice {
    SPUUserUpdateChoice(rawValue: 2)!
  }

  private func emitDownloadProgress() {
    var event: [String: Any] = [
      "type": "downloading",
      "receivedBytes": clampedInt64(receivedContentLength),
    ]
    if let expectedContentLength, expectedContentLength > 0 {
      event["totalBytes"] = clampedInt64(expectedContentLength)
    }
    emit(event)
  }

  private func emit(_ event: [String: Any]) {
    emitEvent(event)
  }

  private func clampedInt64(_ value: UInt64) -> Int64 {
    if value > UInt64(Int64.max) {
      return Int64.max
    }
    return Int64(value)
  }
}
