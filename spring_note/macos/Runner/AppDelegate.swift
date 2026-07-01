import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  let autoStartController = AutoStartController()
  let clipboardImageController = ClipboardImageController()
  let desktopWidgetController = DesktopWidgetWindowController()
  let globalHotkeyController = GlobalHotkeyController()
  let macUpdateController = MacUpdateController()
  let securityScopedDirectoryController = SecurityScopedDirectoryController()
  let trayController = TrayController()

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    if trayController.shouldCloseToTray {
      trayController.hideMainWindow()
      return false
    }
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    trayController.prepareForApplicationExit()
    return .terminateNow
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    trayController.showMainWindow()
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    trayController.showMainWindow()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
