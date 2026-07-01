import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var trayController: TrayController? {
    (NSApp.delegate as? AppDelegate)?.trayController
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.autoStartController.attach(
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.clipboardImageController.attach(
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.desktopWidgetController.attach(
        mainWindow: self,
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.globalHotkeyController.attach(
        mainWindow: self,
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.macUpdateController.attach(
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.securityScopedDirectoryController.attach(
        messenger: flutterViewController.engine.binaryMessenger
      )
      appDelegate.trayController.attach(
        window: self,
        messenger: flutterViewController.engine.binaryMessenger
      )
    }

    super.awakeFromNib()
  }

  override func performClose(_ sender: Any?) {
    if trayController?.shouldCloseToTray == true {
      trayController?.hideMainWindow()
      return
    }
    super.performClose(sender)
  }
}
