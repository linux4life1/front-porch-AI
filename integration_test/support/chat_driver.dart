// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Interaction driver for the E2E suite: every wait, send, and sidebar
// gesture the journey needs, with two invariants baked into ALL of them:
//
//  1. CI timeout scaling (kCiTimeoutScale) — runners are slower than dev
//     machines; no wait may use an unscaled deadline.
//  2. Chance Time immunity — Chaos Mode's wheel is a modal overlay that
//     waits for the USER to spin, and its trigger is an RNG roll, so it can
//     interrupt any turn on any run. A CI gate must NEVER go red because a
//     game mechanic worked as intended: every wait in this driver keeps the
//     wheel moving (spin → land → dismiss) while it waits. PR authors only
//     see red for real regressions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/journal_panel.dart';
import 'package:front_porch_ai/ui/dialogs/journal_dialog.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay.dart';

import 'e2e_sandbox.dart';
import 'fake_backend.dart';

class ChatDriver {
  ChatDriver(this.tester, this.chatService, this.backend);

  final WidgetTester tester;
  final ChatService chatService;
  final FakeBackendServer backend;

  /// Chance Time wheels handled so far. The chaos assert accepts a fired
  /// wheel as proof the mechanism lives (firing CONSUMES the pressure, so
  /// "pressure moved" and "wheel fired" are mutually exclusive outcomes).
  int wheelsSpun = 0;

  /// The chat message input — the TextField whose hint invites typing.
  Finder get input => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText?.contains('Type a message') ?? false),
  );

  /// If the Chance Time overlay is up, do what a user would: spin, let the
  /// wheel land, dismiss the result card (its single button pops the route).
  Future<void> spinChanceTimeIfAsked() async {
    if (find.byType(ChanceTimeOverlay).evaluate().isEmpty) return;
    final spin = find.text('SPIN');
    if (spin.evaluate().isNotEmpty) {
      wheelsSpun++;
      debugPrint('[e2e] Chance Time! Spinning the wheel (#$wheelsSpun).');
      await tester.tap(spin);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(ChanceTimeOverlay).evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      final dismiss = find.descendant(
        of: find.byType(ChanceTimeOverlay),
        matching: find.byType(ElevatedButton),
      );
      if (dismiss.evaluate().isNotEmpty) {
        await tester.tap(dismiss.first);
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Wheel-aware, CI-scaled state wait.
  Future<void> waitFor(
    bool Function() condition,
    String Function() describe, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    timeout *= kCiTimeoutScale;
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      await spinChanceTimeIfAsked();
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out after $timeout waiting for: ${describe()}');
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Wheel-aware, CI-scaled widget wait.
  Future<void> waitForWidget(
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
  }) => waitFor(
    () => finder.evaluate().isNotEmpty,
    () =>
        '$finder (widget tree holds ${tester.allWidgets.length} widgets, '
        'wheels spun: $wheelsSpun)',
    timeout: timeout,
  );

  /// All of _sendCurrentMessage's silent early-return guards down at once.
  Future<void> waitSendable() => waitFor(
    () =>
        !chatService.isGenerating &&
        !chatService.isGuestBusy &&
        !chatService.isPhotoTurnInFlight &&
        !chatService.entrancesInFlight,
    () =>
        'chat sendable (gen=${chatService.isGenerating} '
        'guest=${chatService.isGuestBusy} '
        'photo=${chatService.isPhotoTurnInFlight} '
        'entrances=${chatService.entrancesInFlight})',
  );

  /// Delivery-confirmed send. One tap is not enough: guards can flip in the
  /// gap between the sendable check and the tap, and the app deliberately
  /// swallows such sends (text preserved for retry). The live binding's
  /// fake keyboard connection also goes stale after the app's post-send IME
  /// churn — enterText works for turn 1 and silently no-ops later — so the
  /// controller is set directly when the IME path drops the text.
  Future<void> sendMessage(String text) async {
    bool delivered() => chatService.messages.any((m) => m.text.contains(text));
    for (var attempt = 0; attempt < 8; attempt++) {
      await waitSendable();
      await tester.enterText(input, text);
      final controller = tester.widget<TextField>(input).controller;
      if (controller != null && controller.text != text) {
        controller.text = text;
      }
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      for (var i = 0; i < 8 && !delivered(); i++) {
        await spinChanceTimeIfAsked();
        await tester.pump(const Duration(milliseconds: 250));
      }
      if (delivered()) return;
    }
    fail('"$text" was never accepted by sendMessage after 8 attempts');
  }

  /// Scroll the sidebar to the Journal & Memory accordion and expand it.
  /// Retap is gated on PANEL PRESENCE, not card text: an accordion is a
  /// toggle, and retapping after a successful expand (while content still
  /// paints) would collapse it again. An edge-of-viewport tap can hit-test
  /// as a silent miss, hence ensureVisible + retry.
  Future<void> openJournalAccordion() async {
    final sidebarScrollable = find
        .ancestor(
          of: find.text("Author's Note"),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Journal & Memory'),
      100,
      scrollable: sidebarScrollable,
    );
    final panel = find.byType(JournalPanel);
    for (var attempt = 0; attempt < 5 && panel.evaluate().isEmpty; attempt++) {
      await spinChanceTimeIfAsked();
      await tester.ensureVisible(find.text('Journal & Memory'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Journal & Memory'));
      for (var i = 0; i < 6 && panel.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await waitForWidget(panel, timeout: const Duration(seconds: 15));
  }

  /// Open the full Journal dialog from the sidebar panel and switch to the
  /// "Our Story" timeline tab, requiring it to RESOLVE — entries, a Chance
  /// Time entry, or the empty state, but never a stuck spinner. Guards the
  /// regression where an identity-unstable provider family key (the fresh
  /// List ChatService.messages returns per call) respawned the timeline
  /// provider on every rebuild, pinning the tab on an eternal spinner
  /// whenever the session had background activity.
  Future<void> openOurStoryAndRequireResolved() async {
    // The Open button sits at the BOTTOM of the expanded panel — usually
    // below the sidebar viewport, where a tap silently misses. Same pattern
    // as the accordion: ensure visible, retry until the dialog is really up.
    final openBtn = find.descendant(
      of: find.byType(JournalPanel),
      matching: find.text('Open'),
    );
    final ourStoryTab = find.text('Our Story');
    for (var a = 0; a < 5 && ourStoryTab.evaluate().isEmpty; a++) {
      await spinChanceTimeIfAsked();
      await tester.ensureVisible(openBtn);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(openBtn);
      for (var i = 0; i < 6 && ourStoryTab.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await waitForWidget(ourStoryTab, timeout: const Duration(seconds: 15));
    await tester.tap(ourStoryTab);
    // Content-agnostic resolution signal (entries vs empty state both count):
    // the dialog is up and NO spinner remains inside it. A stuck spinner was
    // the bug's exact signature.
    await waitFor(
      () {
        final dialog = find.byType(JournalDialog);
        if (dialog.evaluate().isEmpty) return false;
        return find
            .descendant(
              of: dialog,
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isEmpty;
      },
      () =>
          '"Our Story" resolving past its spinner '
          '(wheels spun so far: $wheelsSpun)',
      timeout: const Duration(seconds: 30),
    );
  }
}
