// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// Compile-time launch hook (`--dart-define=OPEN_SECTION=timestrip`).
///
/// Empty (the product default) is a no-op. After OPEN_CHAT has landed the
/// 1:1 ChatPage, a known token expands/scrolls a sidebar section or opens
/// Edit Character Details (no Save). Tests inject [section] into [apply]
/// so they do not need dart-define.
class OpenSectionEnv {
  OpenSectionEnv._();

  static const String name = String.fromEnvironment('OPEN_SECTION');

  static bool get enabled => name.isNotEmpty;

  static const journal = 'journal';
  static const objectives = 'objectives';
  static const timestrip = 'timestrip';
  static const edit = 'edit';

  static bool isKnown(String section) {
    switch (section) {
      case journal:
      case objectives:
      case timestrip:
      case edit:
        return true;
      default:
        return false;
    }
  }

  /// Apply [section]. Empty is a no-op. Unknown tokens debugPrint and return.
  ///
  /// [objectivesInTree] stays on the signature for call-site stability.
  /// Apply does not early-return on it: the accordion is still built for
  /// OPEN_SECTION=objectives when the feature flag is off.
  static void apply({
    required String section,
    required bool isGroup,
    required bool isLite,
    required bool objectivesInTree,
    VoidCallback? collapseCharacterState,
    VoidCallback? collapseJournal,
    VoidCallback? expandCharacterState,
    VoidCallback? expandJournal,
    VoidCallback? expandObjectives,
    GlobalKey? journalKey,
    GlobalKey? objectivesKey,
    GlobalKey? timeStripKey,
    VoidCallback? onOpenEdit,
  }) {
    if (section.isEmpty) return;
    if (!isKnown(section)) {
      debugPrint('[Chat] OPEN_SECTION=$section: unknown');
      return;
    }

    switch (section) {
      case journal:
        collapseCharacterState?.call();
        expandJournal?.call();
        afterExpanded(() => ensureKeyVisible(journalKey));
        return;
      case objectives:
        if (isGroup || isLite) return;
        collapseCharacterState?.call();
        collapseJournal?.call();
        // Stay collapsed: PASS is the title in the pane. Do not call
        // expandObjectives (kept on the signature for call-site stability).
        afterExpanded(() => ensureKeyVisible(objectivesKey));
        return;
      case timestrip:
        if (isLite) return;
        expandCharacterState?.call();
        afterExpanded(() => ensureKeyVisible(timeStripKey));
        return;
      case edit:
        if (isGroup || isLite) return;
        onOpenEdit?.call();
        return;
    }
  }

  /// Two nested post-frame callbacks so an expanded accordion body (TimeStrip
  /// at the bottom of Character State, journal/objectives headers) is laid
  /// out before [ensureKeyVisible].
  static void afterExpanded(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    });
  }

  static void ensureKeyVisible(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
  }

  /// Key on the Relationship gap+header block in [RealismFormSection].
  static const Key relationshipHeaderBlockKey = Key(
    'relationship-header-block',
  );

  /// Scroll [relationshipHeaderBlockKey] into view via the overlay (the
  /// Edit Character dialog), not a ChatPage-only walk. Alignment 0.0 parks
  /// the 20px gap at the top of the Details body, below the TabBar.
  static void ensureRelationshipHeaderVisible(BuildContext context) {
    ensureKeyedVisible(context, relationshipHeaderBlockKey);
  }

  static void ensureKeyedVisible(BuildContext context, Key key) {
    Element? found;
    void visitor(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visitor);
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      overlay.context.visitChildElements(visitor);
    } else {
      context.visitChildElements(visitor);
    }
    final target = found;
    if (target == null) return;
    Scrollable.ensureVisible(target, alignment: 0.0, duration: Duration.zero);
  }
}
