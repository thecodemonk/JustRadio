import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // AudioPlayerPlugin lives outside the generated registrant (it's app
    // code, not a pub package). Register it manually against the same
    // Flutter engine so the "justradio/audio" channel is available in
    // Dart at startup. Same wiring as iOS's AppDelegate does; macOS's
    // registrar(forPlugin:) returns non-optional, so no optional binding.
    let registrar = flutterViewController.registrar(forPlugin: "AudioPlayerPlugin")
    AudioPlayerPlugin.register(with: registrar)

    super.awakeFromNib()
  }
}
