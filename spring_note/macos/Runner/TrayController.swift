import Cocoa
import FlutterMacOS
import Carbon.HIToolbox
import ServiceManagement

private func boolValue(_ arguments: [String: Any], _ key: String, fallback: Bool = false) -> Bool {
  arguments[key] as? Bool ?? fallback
}

private func intValue(_ arguments: [String: Any], _ key: String, fallback: Int = 0) -> Int {
  if let value = arguments[key] as? Int {
    return value
  }
  if let value = arguments[key] as? Int64 {
    return Int(value)
  }
  if let value = arguments[key] as? Double {
    return Int(value)
  }
  return fallback
}

private func doubleValue(_ arguments: [String: Any], _ key: String, fallback: Double = 0) -> Double {
  if let value = arguments[key] as? Double {
    return value
  }
  if let value = arguments[key] as? Int {
    return Double(value)
  }
  if let value = arguments[key] as? Int64 {
    return Double(value)
  }
  return fallback
}

private func stringValue(_ arguments: [String: Any], _ key: String, fallback: String = "") -> String {
  arguments[key] as? String ?? fallback
}

private func stringMapValue(_ arguments: [String: Any], _ key: String) -> [String: Any]? {
  arguments[key] as? [String: Any]
}

final class ClipboardImageController {
  private let allowedImageExtensions: Set<String> = [
    "png",
    "jpg",
    "jpeg",
    "gif",
    "webp",
    "bmp",
    "heic",
    "svg",
    "jfif",
  ]

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/clipboard_image",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "readImageFiles":
      result(readImageFiles())
    case "readPngImage":
      result(readPngImage())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func readImageFiles() -> [String] {
    let pasteboard = NSPasteboard.general
    var paths: [String] = []

    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] {
      for url in urls {
        appendImageFile(url.path, to: &paths)
      }
    }

    let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    if let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] {
      for path in filenames {
        appendImageFile(path, to: &paths)
      }
    }

    return paths
  }

  private func appendImageFile(_ path: String, to paths: inout [String]) {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    guard allowedImageExtensions.contains(ext) else {
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      return
    }
    if !paths.contains(path) {
      paths.append(path)
    }
  }

  private func readPngImage() -> FlutterStandardTypedData? {
    let pasteboard = NSPasteboard.general
    if let data = pasteboard.data(forType: .png), !data.isEmpty {
      return FlutterStandardTypedData(bytes: data)
    }
    if let data = pasteboard.data(forType: .tiff),
       let image = NSImage(data: data),
       let pngData = pngData(from: image) {
      return FlutterStandardTypedData(bytes: pngData)
    }
    if let image = NSImage(pasteboard: pasteboard),
       let pngData = pngData(from: image) {
      return FlutterStandardTypedData(bytes: pngData)
    }
    return nil
  }

  private func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}

final class TrayController: NSObject {
  private var statusItem: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private var closeToTray = false
  private var exiting = false

  var shouldCloseToTray: Bool {
    statusItem != nil && closeToTray && !exiting
  }

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "spring_note/tray",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func dispose() {
    hideStatusItem()
    closeToTray = false
  }

  func showMainWindow() {
    guard let window else {
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideMainWindow() {
    window?.orderOut(nil)
  }

  func prepareForApplicationExit() {
    exiting = true
    closeToTray = false
    hideStatusItem()
  }

  func exitApplication() {
    prepareForApplicationExit()
    NSApp.terminate(nil)
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "configure":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "configure expects a map", details: nil))
        return
      }
      let showTrayIcon = arguments["showTrayIcon"] as? Bool ?? false
      let nextCloseToTray = arguments["closeToTray"] as? Bool ?? false
      configure(showTrayIcon: showTrayIcon, closeToTray: nextCloseToTray)
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    case "prepareForApplicationExit":
      prepareForApplicationExit()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configure(showTrayIcon: Bool, closeToTray: Bool) {
    self.closeToTray = showTrayIcon && closeToTray
    if showTrayIcon {
      showStatusItem()
    } else {
      hideStatusItem()
    }
  }

  private func showStatusItem() {
    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.target = self
      item.button?.action = #selector(statusItemClicked(_:))
      item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      statusItem = item
    }

    if let image = loadStatusIcon() {
      statusItem?.button?.image = image
    } else {
      statusItem?.button?.title = "S"
    }
    statusItem?.button?.toolTip = "SpringNote"
  }

  private func loadStatusIcon() -> NSImage? {
    guard let image = NSImage(named: "TrayIcon") else {
      return nil
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = false
    return image
  }

  private func hideStatusItem() {
    guard let item = statusItem else {
      return
    }
    NSStatusBar.system.removeStatusItem(item)
    statusItem = nil
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "打开 SpringNote",
        action: #selector(openMenuItemClicked(_:)),
        keyEquivalent: ""
      )
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "退出",
        action: #selector(exitMenuItemClicked(_:)),
        keyEquivalent: "q"
      )
    )
    menu.items.forEach { $0.target = self }
    return menu
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      showMainWindow()
      return
    }
    if event.type == .rightMouseUp {
      buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    } else if event.type == .leftMouseUp {
      showMainWindow()
    }
  }

  @objc private func openMenuItemClicked(_ sender: NSMenuItem) {
    showMainWindow()
  }

  @objc private func exitMenuItemClicked(_ sender: NSMenuItem) {
    exitApplication()
  }
}

final class AutoStartController: NSObject {
  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/auto_start",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setEnabled":
      guard let enabled = call.arguments as? Bool else {
        result(FlutterError(code: "bad_args", message: "setEnabled expects a bool", details: nil))
        return
      }
      result(setEnabled(enabled))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setEnabled(_ enabled: Bool) -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }

    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status == .enabled || service.status == .requiresApproval {
          return true
        }
        try service.register()
        return service.status == .enabled || service.status == .requiresApproval
      }

      if service.status == .notRegistered || service.status == .notFound {
        return true
      }
      try service.unregister()
      return service.status == .notRegistered || service.status == .notFound
    } catch {
      return false
    }
  }
}

final class SecurityScopedDirectoryController: NSObject {
  private let defaultsKey = "spring_note.security_scoped_directory_bookmarks"
  private var channel: FlutterMethodChannel?
  private var activeUrls: [String: URL] = [:]

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "spring_note/security_scoped_directories",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "saveBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "saveBookmark expects a path", details: nil))
        return
      }
      result(saveBookmark(path: path))
    case "startAccessing":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "startAccessing expects a path", details: nil))
        return
      }
      result(startAccessing(path: path))
    case "removeBookmark":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "removeBookmark expects a path", details: nil))
        return
      }
      removeBookmark(path: path)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveBookmark(path: String) -> Bool {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var bookmarks = storedBookmarks()
      bookmarks[normalizedPath(path)] = bookmark.base64EncodedString()
      UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
      _ = startAccessing(path: path)
      return true
    } catch {
      return false
    }
  }

  private func startAccessing(path: String) -> Bool {
    let key = normalizedPath(path)
    if activeUrls[key] != nil {
      return true
    }

    guard
      let bookmarkString = storedBookmarks()[key],
      let bookmark = Data(base64Encoded: bookmarkString)
    else {
      return false
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if isStale {
        _ = saveBookmark(path: url.path)
      }
      if url.startAccessingSecurityScopedResource() {
        activeUrls[key] = url
        return true
      }
      return false
    } catch {
      return false
    }
  }

  private func removeBookmark(path: String) {
    let key = normalizedPath(path)
    if let url = activeUrls.removeValue(forKey: key) {
      url.stopAccessingSecurityScopedResource()
    }
    var bookmarks = storedBookmarks()
    bookmarks.removeValue(forKey: key)
    UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
  }

  private func storedBookmarks() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
  }

  private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }
}

final class GlobalHotkeyController: NSObject {
  private var channel: FlutterMethodChannel?
  private weak var mainWindow: NSWindow?
  private var hotkeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private let hotkeyId = EventHotKeyID(signature: fourCharCode("SPNT"), id: 1)

  func attach(mainWindow: NSWindow, messenger: FlutterBinaryMessenger) {
    self.mainWindow = mainWindow
    channel = FlutterMethodChannel(
      name: "spring_note/global_hotkeys",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    installEventHandlerIfNeeded()
  }

  deinit {
    unregisterToggleWindowHotkey()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setToggleWindowHotkey":
      guard let hotkey = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "setToggleWindowHotkey expects a string", details: nil))
        return
      }
      result(setToggleWindowHotkey(hotkey))
    case "unregisterToggleWindowHotkey":
      unregisterToggleWindowHotkey()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard
          let event,
          let userData
        else {
          return noErr
        }

        var eventHotkeyId = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &eventHotkeyId
        )
        guard status == noErr else {
          return status
        }

        let controller = Unmanaged<GlobalHotkeyController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        if eventHotkeyId.signature == controller.hotkeyId.signature &&
          eventHotkeyId.id == controller.hotkeyId.id {
          controller.toggleMainWindow()
        }
        return noErr
      },
      1,
      &eventType,
      selfPointer,
      &eventHandler
    )
  }

  private func setToggleWindowHotkey(_ hotkey: String) -> Bool {
    guard let spec = parseHotkey(hotkey) else {
      return false
    }

    unregisterToggleWindowHotkey()
    let status = RegisterEventHotKey(
      UInt32(spec.keyCode),
      spec.modifiers,
      hotkeyId,
      GetApplicationEventTarget(),
      0,
      &hotkeyRef
    )
    return status == noErr
  }

  private func unregisterToggleWindowHotkey() {
    guard let hotkeyRef else {
      return
    }
    UnregisterEventHotKey(hotkeyRef)
    self.hotkeyRef = nil
  }

  private func toggleMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = mainWindow else {
      return
    }

    if !window.isVisible || window.isMiniaturized {
      window.makeKeyAndOrderFront(nil)
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      return
    }

    window.orderOut(nil)
  }

  private func parseHotkey(_ hotkey: String) -> (keyCode: UInt16, modifiers: UInt32)? {
    let tokens = hotkey
      .split(separator: "+")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
      .filter { !$0.isEmpty }
    guard !tokens.isEmpty else {
      return nil
    }

    var modifiers: UInt32 = 0
    var keyCode: UInt16?

    for token in tokens {
      switch token {
      case "CTRL", "CONTROL":
        modifiers |= UInt32(controlKey)
      case "SHIFT":
        modifiers |= UInt32(shiftKey)
      case "ALT", "OPTION":
        modifiers |= UInt32(optionKey)
      case "WIN", "WINDOWS", "META", "CMD", "COMMAND", "SUPER":
        modifiers |= UInt32(cmdKey)
      default:
        guard keyCode == nil, let nextKeyCode = keyCodeForToken(token) else {
          return nil
        }
        keyCode = nextKeyCode
      }
    }

    guard let keyCode else {
      return nil
    }
    return (keyCode, modifiers)
  }

  private func keyCodeForToken(_ token: String) -> UInt16? {
    if token.count == 1, let scalar = token.unicodeScalars.first {
      switch scalar.value {
      case 65: return UInt16(kVK_ANSI_A)
      case 66: return UInt16(kVK_ANSI_B)
      case 67: return UInt16(kVK_ANSI_C)
      case 68: return UInt16(kVK_ANSI_D)
      case 69: return UInt16(kVK_ANSI_E)
      case 70: return UInt16(kVK_ANSI_F)
      case 71: return UInt16(kVK_ANSI_G)
      case 72: return UInt16(kVK_ANSI_H)
      case 73: return UInt16(kVK_ANSI_I)
      case 74: return UInt16(kVK_ANSI_J)
      case 75: return UInt16(kVK_ANSI_K)
      case 76: return UInt16(kVK_ANSI_L)
      case 77: return UInt16(kVK_ANSI_M)
      case 78: return UInt16(kVK_ANSI_N)
      case 79: return UInt16(kVK_ANSI_O)
      case 80: return UInt16(kVK_ANSI_P)
      case 81: return UInt16(kVK_ANSI_Q)
      case 82: return UInt16(kVK_ANSI_R)
      case 83: return UInt16(kVK_ANSI_S)
      case 84: return UInt16(kVK_ANSI_T)
      case 85: return UInt16(kVK_ANSI_U)
      case 86: return UInt16(kVK_ANSI_V)
      case 87: return UInt16(kVK_ANSI_W)
      case 88: return UInt16(kVK_ANSI_X)
      case 89: return UInt16(kVK_ANSI_Y)
      case 90: return UInt16(kVK_ANSI_Z)
      case 48: return UInt16(kVK_ANSI_0)
      case 49: return UInt16(kVK_ANSI_1)
      case 50: return UInt16(kVK_ANSI_2)
      case 51: return UInt16(kVK_ANSI_3)
      case 52: return UInt16(kVK_ANSI_4)
      case 53: return UInt16(kVK_ANSI_5)
      case 54: return UInt16(kVK_ANSI_6)
      case 55: return UInt16(kVK_ANSI_7)
      case 56: return UInt16(kVK_ANSI_8)
      case 57: return UInt16(kVK_ANSI_9)
      default: break
      }
    }

    if token.first == "F", let number = Int(token.dropFirst()) {
      switch number {
      case 1: return UInt16(kVK_F1)
      case 2: return UInt16(kVK_F2)
      case 3: return UInt16(kVK_F3)
      case 4: return UInt16(kVK_F4)
      case 5: return UInt16(kVK_F5)
      case 6: return UInt16(kVK_F6)
      case 7: return UInt16(kVK_F7)
      case 8: return UInt16(kVK_F8)
      case 9: return UInt16(kVK_F9)
      case 10: return UInt16(kVK_F10)
      case 11: return UInt16(kVK_F11)
      case 12: return UInt16(kVK_F12)
      case 13: return UInt16(kVK_F13)
      case 14: return UInt16(kVK_F14)
      case 15: return UInt16(kVK_F15)
      case 16: return UInt16(kVK_F16)
      case 17: return UInt16(kVK_F17)
      case 18: return UInt16(kVK_F18)
      case 19: return UInt16(kVK_F19)
      case 20: return UInt16(kVK_F20)
      default: break
      }
    }

    switch token {
    case "SPACE": return UInt16(kVK_Space)
    case "TAB": return UInt16(kVK_Tab)
    case "ENTER", "RETURN": return UInt16(kVK_Return)
    case "ESC", "ESCAPE": return UInt16(kVK_Escape)
    case "BACKSPACE": return UInt16(kVK_Delete)
    case "DELETE", "DEL": return UInt16(kVK_ForwardDelete)
    case "HOME": return UInt16(kVK_Home)
    case "END": return UInt16(kVK_End)
    case "PAGEUP", "PGUP": return UInt16(kVK_PageUp)
    case "PAGEDOWN", "PGDN": return UInt16(kVK_PageDown)
    case "UP": return UInt16(kVK_UpArrow)
    case "DOWN": return UInt16(kVK_DownArrow)
    case "LEFT": return UInt16(kVK_LeftArrow)
    case "RIGHT": return UInt16(kVK_RightArrow)
    default: return nil
    }
  }
}

struct DesktopWidgetState {
  var running = true
  var workSeconds = 0
  var coins = 0.0
  var coinRatePerSecond = 0.0
  var level = 1
  var experiencePercent = 0
  var progress = 0.0
  var fontFamily = "system"
  var fontScaleFactor = 1.0
  var orbMode = false
  var darkMode = false
  var wallpaperMode = 0          // 0=defaultWhite, 1=solid, 2=image
  var wallpaperColor: Int = -1   // ARGB int, -1 means unset
  var wallpaperImagePath: String? = nil
  var wallpaperOpacity: CGFloat = 1.0

  mutating func update(with arguments: [String: Any]) {
    running = boolValue(arguments, "running", fallback: running)
    workSeconds = intValue(arguments, "workSeconds", fallback: workSeconds)
    coins = doubleValue(arguments, "coins", fallback: coins)
    coinRatePerSecond = doubleValue(
      arguments,
      "coinRatePerSecond",
      fallback: coinRatePerSecond
    )
    level = max(1, intValue(arguments, "level", fallback: level))
    experiencePercent = min(
      99,
      max(0, intValue(arguments, "experiencePercent", fallback: experiencePercent))
    )
    progress = min(1, max(0, doubleValue(arguments, "progress", fallback: progress)))
    fontFamily = stringValue(arguments, "appFont", fallback: fontFamily)
    fontScaleFactor = min(
      1.4,
      max(0.8, doubleValue(arguments, "fontScaleFactor", fallback: fontScaleFactor))
    )
    orbMode = boolValue(arguments, "orbMode", fallback: orbMode)
    darkMode = boolValue(arguments, "darkMode", fallback: darkMode)
    wallpaperMode = min(2, max(0, intValue(arguments, "widgetWallpaperMode", fallback: wallpaperMode)))
    let wpColor = intValue(arguments, "widgetWallpaperColor", fallback: -1)
    if wpColor >= 0 {
      wallpaperColor = wpColor
    }
    let wpPath = stringValue(arguments, "widgetWallpaperImagePath", fallback: "")
    wallpaperImagePath = wpPath.isEmpty ? nil : wpPath
    wallpaperOpacity = min(1.0, max(0.0, CGFloat(doubleValue(arguments, "widgetWallpaperOpacity", fallback: Double(wallpaperOpacity)))))
  }
}

struct DesktopWidgetColors {
  let surface: NSColor
  let surfaceMuted: NSColor
  let surfacePressed: NSColor
  let border: NSColor
  let text: NSColor
  let textSubtle: NSColor
  let stopped: NSColor
  let accent: NSColor

  private static let defaultAccent = NSColor(
    calibratedRed: 0.06,
    green: 0.73,
    blue: 0.51,
    alpha: 1
  )
  static let dark = DesktopWidgetColors(
    surface: rgb(27, 27, 27),
    surfaceMuted: rgb(42, 42, 42),
    surfacePressed: rgb(48, 48, 48),
    border: rgb(51, 51, 51),
    text: rgb(242, 242, 242),
    textSubtle: rgb(154, 154, 154),
    stopped: rgb(154, 154, 154),
    accent: defaultAccent
  )
  static let light = DesktopWidgetColors(
    surface: .white,
    surfaceMuted: white(0.93),
    surfacePressed: white(0.81),
    border: white(0.9),
    text: white(0.09),
    textSubtle: white(0.4),
    stopped: white(0.81),
    accent: defaultAccent
  )

  static func palette(darkMode: Bool) -> DesktopWidgetColors {
    darkMode ? dark : light
  }

  private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
  }

  private static func white(_ white: CGFloat) -> NSColor {
    NSColor(calibratedWhite: white, alpha: 1)
  }
}

final class DesktopWidgetWindowController: NSObject {
  private let expandedSize = NSSize(width: 260, height: 140)
  private let orbSize = NSSize(width: 64, height: 64)
  private let defaultMargin: CGFloat = 28
  private var channel: FlutterMethodChannel?
  private weak var mainWindow: NSWindow?
  private var panel: DesktopWidgetPanel?
  private var state = DesktopWidgetState()
  private var positioned = false
  private var savedPosition: DesktopWidgetPosition?
  private var expanded = true

  func attach(mainWindow: NSWindow, messenger: FlutterBinaryMessenger) {
    self.mainWindow = mainWindow
    channel = FlutterMethodChannel(
      name: "spring_note/desktop_widget_window",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "showOrUpdate":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "showOrUpdate expects a map", details: nil))
        return
      }
      showOrUpdate(arguments)
      result(nil)
    case "hide":
      hide()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showOrUpdate(_ arguments: [String: Any]) {
    let wasOrbMode = state.orbMode
    state.update(with: arguments)
    if !state.orbMode {
      expanded = true
    } else if !wasOrbMode || panel == nil {
      expanded = false
    }
    savedPosition = DesktopWidgetPosition.from(arguments: arguments)
      ?? DesktopWidgetPosition.fromUserDefaults()

    let panel = ensurePanel()
    panel.widgetView.expanded = expanded
    panel.widgetView.state = state
    applyPanelSize(panel, preserveBottomRight: positioned)
    panel.widgetView.needsDisplay = true
    if !positioned {
      moveToSavedOrDefaultPosition(panel)
      positioned = true
    } else {
      clampPanelToVisibleScreen(panel, notify: false)
    }
    panel.orderFrontRegardless()
  }

  private func hide() {
    panel?.close()
    panel = nil
    positioned = false
  }

  private func ensurePanel() -> DesktopWidgetPanel {
    if let panel {
      return panel
    }

    let nextPanel = DesktopWidgetPanel(
      controller: self,
      contentRect: NSRect(origin: .zero, size: currentSize)
    )
    panel = nextPanel
    return nextPanel
  }

  private var currentSize: NSSize {
    state.orbMode && !expanded ? orbSize : expandedSize
  }

  private func applyPanelSize(_ panel: NSPanel, preserveBottomRight: Bool) {
    var frame = panel.frame
    let size = currentSize
    if preserveBottomRight {
      frame.origin.x = frame.maxX - size.width
      frame.origin.y = frame.maxY - size.height
    }
    frame.size = size
    frame.origin = clampedOrigin(
      frame.origin,
      size: size,
      screen: nearestScreen(to: frame.center, fallback: panel.screen)
    )
    panel.setFrame(frame, display: true)
  }

  private func moveToSavedOrDefaultPosition(_ panel: NSPanel) {
    if let savedPosition {
      let screen = screen(for: savedPosition.screenId) ?? nearestScreen(
        to: NSPoint(x: savedPosition.x, y: savedPosition.y),
        fallback: nil
      )
      let origin = clampedOrigin(
        NSPoint(x: savedPosition.x, y: savedPosition.y),
        size: panel.frame.size,
        screen: screen
      )
      panel.setFrameOrigin(origin)
      notifyPositionChanged(panel)
      return
    }

    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let screen else {
      return
    }
    let screenFrame = screen.visibleFrame
    let x = screenFrame.maxX - panel.frame.width - defaultMargin
    let y = screenFrame.minY + defaultMargin
    panel.setFrameOrigin(NSPoint(x: x, y: y))
    notifyPositionChanged(panel)
  }

  private func clampPanelToVisibleScreen(_ panel: NSPanel, notify: Bool) {
    let origin = clampedOrigin(
      panel.frame.origin,
      size: panel.frame.size,
      screen: nearestScreen(to: panel.frame.center, fallback: panel.screen)
    )
    if panel.frame.origin != origin {
      panel.setFrameOrigin(origin)
    }
    if notify {
      notifyPositionChanged(panel)
    }
  }

  private func clampedOrigin(
    _ origin: NSPoint,
    size: NSSize,
    screen preferredScreen: NSScreen?
  ) -> NSPoint {
    let screen = preferredScreen ?? nearestScreen(
      to: NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2),
      fallback: nil
    )
    guard let screenFrame = screen?.visibleFrame else {
      return origin
    }
    let minX = screenFrame.minX
    let maxX = screenFrame.maxX - size.width
    let minY = screenFrame.minY
    let maxY = screenFrame.maxY - size.height
    return NSPoint(
      x: min(max(origin.x, minX), max(minX, maxX)),
      y: min(max(origin.y, minY), max(minY, maxY))
    )
  }

  private func nearestScreen(to point: NSPoint, fallback: NSScreen?) -> NSScreen? {
    if let containing = NSScreen.screens.first(where: { $0.visibleFrame.contains(point) }) {
      return containing
    }
    return NSScreen.screens.min { lhs, rhs in
      lhs.visibleFrame.distanceSquared(to: point) < rhs.visibleFrame.distanceSquared(to: point)
    } ?? fallback ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func screen(for id: String?) -> NSScreen? {
    guard let id else {
      return nil
    }
    return NSScreen.screens.first { $0.springNoteScreenId == id }
  }

  func boundedOrigin(for proposedOrigin: NSPoint, size: NSSize) -> NSPoint {
    clampedOrigin(
      proposedOrigin,
      size: size,
      screen: nearestScreen(
        to: NSPoint(x: proposedOrigin.x + size.width / 2, y: proposedOrigin.y + size.height / 2),
        fallback: panel?.screen
      )
    )
  }

  func finishMovingPanel() {
    guard let panel else {
      return
    }
    clampPanelToVisibleScreen(panel, notify: true)
  }

  private func notifyPositionChanged(_ panel: NSPanel) {
    let screen = nearestScreen(to: panel.frame.center, fallback: panel.screen)
    let position = DesktopWidgetPosition(
      screenId: screen?.springNoteScreenId,
      x: panel.frame.origin.x,
      y: panel.frame.origin.y
    )
    position.saveToUserDefaults()
    channel?.invokeMethod(
      "positionChanged",
      arguments: [
        "screenId": position.screenId ?? "",
        "x": Double(position.x),
        "y": Double(position.y),
      ]
    )
  }

  func toggle() {
    channel?.invokeMethod("toggle", arguments: nil)
  }

  func setExpanded(_ nextExpanded: Bool) {
    guard state.orbMode, expanded != nextExpanded, let panel else {
      return
    }
    expanded = nextExpanded
    panel.widgetView.expanded = nextExpanded
    applyPanelSize(panel, preserveBottomRight: true)
    panel.widgetView.needsDisplay = true
  }

  func openHome() {
    NSApp.activate(ignoringOtherApps: true)
    if let mainWindow {
      mainWindow.makeKeyAndOrderFront(nil)
      if mainWindow.isMiniaturized {
        mainWindow.deminiaturize(nil)
      }
    }
    channel?.invokeMethod("openHome", arguments: nil)
  }
}

final class DesktopWidgetPanel: NSPanel {
  let widgetView: DesktopWidgetView

  init(controller: DesktopWidgetWindowController, contentRect: NSRect) {
    widgetView = DesktopWidgetView(controller: controller, frame: contentRect)
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    contentView = widgetView
  }

  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}

final class DesktopWidgetView: NSView {
  var state = DesktopWidgetState() {
    didSet {
      invalidateDisplay()
    }
  }
  var expanded = true {
    didSet {
      invalidateDisplay()
    }
  }
  #if DEBUG
  var onDisplayInvalidated: (() -> Void)?
  #endif
  private weak var controller: DesktopWidgetWindowController?
  private var mouseDownLocation: NSPoint?
  private var windowStartOrigin: NSPoint?
  private var movedWhilePressed = false
  private var trackingArea: NSTrackingArea?
  private var cachedWallpaperImage: NSImage?
  private var cachedWallpaperPath: String?

  init(controller: DesktopWidgetWindowController, frame: NSRect) {
    self.controller = controller
    super.init(frame: frame)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool {
    true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let nextTrackingArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(nextTrackingArea)
    trackingArea = nextTrackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    controller?.setExpanded(true)
  }

  override func mouseExited(with event: NSEvent) {
    guard mouseDownLocation == nil, !isMouseInsideWindowFrame() else {
      return
    }
    controller?.setExpanded(false)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    let bounds = self.bounds
    let colors = DesktopWidgetColors.palette(darkMode: state.darkMode)
    if state.orbMode && !expanded {
      let orbPath = CGPath(
        ellipseIn: bounds.insetBy(dx: 0.5, dy: 0.5),
        transform: nil
      )

      // Wallpaper background (clipped to orb circle)
      drawWallpaper(context: context, bounds: bounds, clipPath: orbPath)

      context.setStrokeColor(colors.border.cgColor)
      context.setLineWidth(1)
      context.addPath(orbPath)
      context.strokePath()

      let dotColor = state.running
        ? colors.accent
        : colors.stopped
      context.setFillColor(dotColor.cgColor)
      context.fillEllipse(in: NSRect(x: bounds.width - 18, y: 12, width: 8, height: 8))

      let coinsFormat = state.coins >= 100 ? "%.0f" : "%.1f"
      drawText(
        String(format: coinsFormat, state.coins),
        rect: NSRect(x: 7, y: 20, width: bounds.width - 14, height: 24),
        size: scaled(17),
        weight: .semibold,
        color: colors.text,
        alignment: .center
      )
      drawText(
        "coin",
        rect: NSRect(x: 8, y: 43, width: bounds.width - 16, height: 14),
        size: scaled(10),
        weight: .semibold,
        color: colors.textSubtle,
        alignment: .center
      )
      return
    }

    let cardPath = CGPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: 16,
      cornerHeight: 16,
      transform: nil
    )

    // Wallpaper background (clipped to rounded rect)
    drawWallpaper(context: context, bounds: bounds, clipPath: cardPath)

    context.setStrokeColor(colors.border.cgColor)
    context.setLineWidth(1)
    context.addPath(cardPath)
    context.strokePath()

    drawText(
      "Lv.\(state.level) 实习生 (\(state.experiencePercent)%)",
      rect: NSRect(x: 16, y: 13, width: bounds.width - 32, height: 20),
      size: scaled(14),
      weight: .semibold,
      color: colors.textSubtle,
      alignment: .left
    )

    let track = NSRect(x: 16, y: 39, width: bounds.width - 32, height: 2)
    drawRoundedRect(track, radius: 1, color: colors.surfaceMuted)
    let progressWidth = track.width * CGFloat(min(1, max(0, state.progress)))
    if progressWidth > 0 {
      drawRoundedRect(
        NSRect(x: track.minX, y: track.minY, width: progressWidth, height: track.height),
        radius: 1,
        color: colors.surfacePressed
      )
    }

    drawText(
      String(format: "%.2f", state.coins),
      rect: NSRect(x: 16, y: 52, width: bounds.width - 32, height: 48),
      size: scaled(38),
      weight: .medium,
      color: colors.text,
      alignment: .left
    )

    let rate = state.running ? state.coinRatePerSecond : 0
    drawText(
      String(format: "+%.3f coin/s", rate),
      rect: NSRect(x: 16, y: 111, width: 130, height: 20),
      size: scaled(14),
      weight: .bold,
      color: colors.accent,
      alignment: .left
    )

    let dotColor = state.running
      ? colors.accent
      : colors.stopped
    context.setFillColor(dotColor.cgColor)
    context.fillEllipse(in: NSRect(x: bounds.width - 96, y: 118, width: 6, height: 6))

    drawText(
      formatDuration(state.workSeconds),
      rect: NSRect(x: bounds.width - 84, y: 111, width: 68, height: 20),
      size: scaled(13),
      weight: .regular,
      color: colors.textSubtle,
      alignment: .right
    )
  }

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = NSEvent.mouseLocation
    windowStartOrigin = window?.frame.origin
    movedWhilePressed = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard
      let window,
      let mouseDownLocation,
      let windowStartOrigin
    else {
      return
    }

    let current = NSEvent.mouseLocation
    let dx = current.x - mouseDownLocation.x
    let dy = current.y - mouseDownLocation.y
    if abs(dx) > 3 || abs(dy) > 3 {
      movedWhilePressed = true
    }
    let nextOrigin = controller?.boundedOrigin(
      for: NSPoint(x: windowStartOrigin.x + dx, y: windowStartOrigin.y + dy),
      size: window.frame.size
    ) ?? NSPoint(x: windowStartOrigin.x + dx, y: windowStartOrigin.y + dy)
    window.setFrameOrigin(nextOrigin)
  }

  override func mouseUp(with event: NSEvent) {
    if !movedWhilePressed {
      controller?.toggle()
    }
    let shouldCollapse = state.orbMode && !isMouseInsideWindowFrame()
    mouseDownLocation = nil
    windowStartOrigin = nil
    controller?.finishMovingPanel()
    if shouldCollapse {
      controller?.setExpanded(false)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    controller?.openHome()
  }

  private func scaled(_ size: CGFloat) -> CGFloat {
    max(1, size * CGFloat(state.fontScaleFactor))
  }

  private func isMouseInsideWindowFrame() -> Bool {
    guard let window else {
      return false
    }
    return window.frame.contains(NSEvent.mouseLocation)
  }

  private func drawRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
  }

  private func invalidateDisplay() {
    needsDisplay = true
    #if DEBUG
    onDisplayInvalidated?()
    #endif
  }

  private func drawText(
    _ text: String,
    rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment
  ) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    paragraphStyle.lineBreakMode = .byTruncatingTail

    let fontName = state.fontFamily == "system" ? "" : state.fontFamily
    let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]
    NSString(string: text).draw(in: rect, withAttributes: attributes)
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remainingSeconds = seconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
  }

  /// 在裁剪路径内绘制壁纸背景。
  ///
  /// - mode 0 (defaultWhite): 填充主题 surface 色（原有行为）
  /// - mode 1 (solid): 填充用户自选纯色
  /// - mode 2 (image): 加载本地图片，等比覆盖，支持透明度
  private func drawWallpaper(context: CGContext, bounds: NSRect, clipPath: CGPath) {
    let colors = DesktopWidgetColors.palette(darkMode: state.darkMode)

    context.saveGState()
    context.addPath(clipPath)
    context.clip()

    switch state.wallpaperMode {
    case 1:
      // 纯色模式：从 ARGB int 提取 RGB
      let argb = state.wallpaperColor >= 0 ? state.wallpaperColor : 0xFFFFFF
      let r = CGFloat((argb >> 16) & 0xFF) / 255.0
      let g = CGFloat((argb >> 8) & 0xFF) / 255.0
      let b = CGFloat(argb & 0xFF) / 255.0
      context.setFillColor(red: r, green: g, blue: b, alpha: state.wallpaperOpacity)
      context.fill(bounds)

    case 2:
      // 图片模式：加载并绘制壁纸
      if let imagePath = state.wallpaperImagePath {
        if cachedWallpaperPath != imagePath {
          cachedWallpaperImage = NSImage(contentsOfFile: imagePath)
          cachedWallpaperPath = imagePath
        }
        if let image = cachedWallpaperImage {
          context.saveGState()
          context.setAlpha(state.wallpaperOpacity)
          // 等比覆盖：计算缩放比例，居中裁剪
          let imgSize = image.size
          if imgSize.width > 0 && imgSize.height > 0 {
            let scaleX = bounds.width / imgSize.width
            let scaleY = bounds.height / imgSize.height
            let scale = max(scaleX, scaleY)
            let drawW = imgSize.width * scale
            let drawH = imgSize.height * scale
            let drawX = bounds.origin.x + (bounds.width - drawW) / 2
            let drawY = bounds.origin.y + (bounds.height - drawH) / 2
            image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH))
          }
          context.restoreGState()
        } else {
          // 图片加载失败，回退白色
          context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
          context.fill(bounds)
        }
      } else {
        // 无路径，回退白色
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(bounds)
      }

    default:
      // mode 0: 默认主题背景色
      context.setFillColor(colors.surface.cgColor)
      context.fill(bounds)
    }

    context.restoreGState()
  }
}

private struct DesktopWidgetPosition {
  private static let storedKey = "desktopWidgetPosition.stored"
  private static let screenIdKey = "desktopWidgetPosition.screenId"
  private static let xKey = "desktopWidgetPosition.x"
  private static let yKey = "desktopWidgetPosition.y"

  let screenId: String?
  let x: CGFloat
  let y: CGFloat

  static func from(arguments: [String: Any]) -> DesktopWidgetPosition? {
    guard let position = stringMapValue(arguments, "position") else {
      return nil
    }
    let x = doubleValue(position, "x", fallback: .nan)
    let y = doubleValue(position, "y", fallback: .nan)
    guard x.isFinite && y.isFinite else {
      return nil
    }
    let screenId = stringValue(position, "screenId")
    return DesktopWidgetPosition(
      screenId: screenId.isEmpty ? nil : screenId,
      x: CGFloat(x),
      y: CGFloat(y)
    )
  }

  static func fromUserDefaults() -> DesktopWidgetPosition? {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: storedKey) else {
      return nil
    }
    let x = defaults.double(forKey: xKey)
    let y = defaults.double(forKey: yKey)
    guard x.isFinite && y.isFinite else {
      return nil
    }
    let screenId = defaults.string(forKey: screenIdKey)
    return DesktopWidgetPosition(
      screenId: screenId?.isEmpty == true ? nil : screenId,
      x: CGFloat(x),
      y: CGFloat(y)
    )
  }

  func saveToUserDefaults() {
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: Self.storedKey)
    defaults.set(screenId ?? "", forKey: Self.screenIdKey)
    defaults.set(Double(x), forKey: Self.xKey)
    defaults.set(Double(y), forKey: Self.yKey)
  }
}

private extension NSRect {
  var center: NSPoint {
    NSPoint(x: midX, y: midY)
  }

  func distanceSquared(to point: NSPoint) -> CGFloat {
    let clampedX = min(max(point.x, minX), maxX)
    let clampedY = min(max(point.y, minY), maxY)
    let dx = point.x - clampedX
    let dy = point.y - clampedY
    return dx * dx + dy * dy
  }
}

private extension NSScreen {
  var springNoteScreenId: String {
    if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return number.stringValue
    }
    return frame.debugDescription
  }
}

private func fourCharCode(_ value: String) -> OSType {
  value.utf8.reduce(0) { result, byte in
    (result << 8) + OSType(byte)
  }
}
