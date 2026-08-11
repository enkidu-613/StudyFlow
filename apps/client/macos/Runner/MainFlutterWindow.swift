import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    StudyFlowPlatform.register(
      with: flutterViewController.registrar(forPlugin: "StudyFlowPlatform").messenger)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
