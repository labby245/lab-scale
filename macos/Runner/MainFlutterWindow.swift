import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Where a user's own resize is remembered, in the app's user defaults.
  private static let frameAutosaveName = NSWindow.FrameAutosaveName("LabScaleMainWindow")

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // LabScale's workspace is a two-column layout that only engages above
    // 1040pt wide. The MainMenu.xib default of 800x600 sits below that, so
    // left alone the app always opens in the stacked single-column fallback
    // and needs scrolling to reach anything. Windows already opens at
    // 1360x900 (see windows/runner/main.cpp) — match it.
    //
    // The frame is managed explicitly rather than left to Cocoa's automatic
    // window restoration, which was quietly reinstating an old frame after
    // awakeFromNib and undoing any size set here.
    self.isRestorable = false
    self.contentMinSize = NSSize(width: 940, height: 640)

    if !self.setFrameUsingName(Self.frameAutosaveName) {
      var target = NSSize(width: 1360, height: 900)
      if let screen = self.screen ?? NSScreen.main {
        // Never open larger than the screen actually allows.
        let usable = screen.visibleFrame.size
        target.width = min(target.width, usable.width - 40)
        target.height = min(target.height, usable.height - 40)
      }
      self.setContentSize(target)
      self.center()
    }
    self.setFrameAutosaveName(Self.frameAutosaveName)
  }
}
