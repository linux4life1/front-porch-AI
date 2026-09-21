// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Opaque so Impeller's wide-gamut Metal layer does not start clear
    // under the title bar (Flutter 3.47 desktop default).
    flutterViewController.backgroundColor = NSColor(
      srgbRed: 15.0 / 255.0,
      green: 23.0 / 255.0,
      blue: 42.0 / 255.0,
      alpha: 1.0
    )

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    applyOpaqueTitleBar()

    RegisterGeneratedPlugins(registry: flutterViewController)

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
