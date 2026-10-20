// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  private var launchWindowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Opaque so Impeller's wide-gamut Metal layer does not start clear
    // under the title bar (Flutter 3.47 desktop default). Porch brown
    // #1B1611 is only the fallback: the window stays hidden until Dart has
    // sent the saved theme's background (setBackground below) and shown it.
    flutterViewController.backgroundColor = NSColor(
      srgbRed: 27.0 / 255.0,
      green: 22.0 / 255.0,
      blue: 17.0 / 255.0,
      alpha: 1.0
    )

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    applyOpaqueTitleBar()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // lib/app/launch_window.dart: the saved theme's background, sent before
    // the window shows, so nothing before the first frame is another colour.
    let channel = FlutterMethodChannel(
      name: "front_porch_ai/launch_window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak flutterViewController] call, result in
      guard call.method == "setBackground", let argb = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      flutterViewController?.backgroundColor = NSColor(
        srgbRed: CGFloat((argb >> 16) & 0xFF) / 255.0,
        green: CGFloat((argb >> 8) & 0xFF) / 255.0,
        blue: CGFloat(argb & 0xFF) / 255.0,
        alpha: 1.0
      )
      result(nil)
    }
    launchWindowChannel = channel

    super.awakeFromNib()
  }

  /// Pin a normal macOS title bar. window_manager's `setTitleBarStyle`
  /// always sets `isOpaque = false`; a later transparent
  /// `setBackgroundColor` then lets Flutter content sit under the
  /// traffic lights. Dart sends an opaque background as well.
  func applyOpaqueTitleBar() {
    titleVisibility = .visible
    titlebarAppearsTransparent = false
    styleMask.remove(.fullSizeContentView)
    isOpaque = true
    backgroundColor = NSColor.windowBackgroundColor
    if let titleBarView = standardWindowButton(.closeButton)?.superview?.superview {
      titleBarView.isHidden = false
    }
  }

  // Hidden until Dart's windowManager.show() (lib/app/main_window.dart),
  // which runs after the saved theme's background is set.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }

  // window_manager.setTitleBarStyle always writes isOpaque = false even
  // for TitleBarStyle.normal. Refuse that so Impeller cannot composite
  // the Flutter view through the title bar.
  override var isOpaque: Bool {
    get { true }
    set { super.isOpaque = true }
  }

  override var titlebarAppearsTransparent: Bool {
    get { false }
    set { super.titlebarAppearsTransparent = false }
  }

  override var styleMask: NSWindow.StyleMask {
    get { super.styleMask }
    set {
      var mask = newValue
      mask.remove(.fullSizeContentView)
      super.styleMask = mask
    }
  }
}
