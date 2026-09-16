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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
// Sidebar panels are direct-import per the chat_components barrel's policy.
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/journal_panel.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

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

  /// The bubble showing exactly [msg] — matched by INSTANCE IDENTITY on
  /// [MessageBubble.message], never by key. Bubbles used to be keyed
  /// `GlobalObjectKey(msg)` and two suites found them that way; the
  /// duplicate-GlobalKey crash fix (2026-08-10, page-owned `_bubbleKeys`)
  /// removed that scheme and the keyed finders went from "the one true
  /// handle" to "Found 0 widgets" on every platform. Identity matching
  /// keeps the property the keyed lookup existed for — the fake backend's
  /// replies share identical text, so text matching is ambiguous — while
  /// depending only on the bubble's public contract, not the page's
  /// private key scheme. ChatMessage does not override `==`, so this is
  /// the same equality the old key used.
  Finder bubbleFor(ChatMessage msg) => find.byWidgetPredicate(
    (w) => w is MessageBubble && identical(w.message, msg),
  );

  /// [bubbleFor], revealed by scrolling. The reversed list VIRTUALIZES, so
  /// an old message's bubble may not be built at all until dragged into
  /// view (the macOS leg of message_actions' first CI run). Positive drags
  /// reveal older messages in the reversed list; the negative tail is
  /// insurance.
  Future<Finder> revealBubbleFor(ChatMessage msg) async {
    final f = bubbleFor(msg);
    if (f.evaluate().isNotEmpty) return f;
    final scrollable = find
        .ancestor(
          of: find.byType(MessageBubble).first,
          matching: find.byType(Scrollable),
        )
        .first;
    const drags = [
      300.0, 300.0, 300.0, 300.0, 300.0, 300.0, //
      -300.0, -300.0, -300.0, -300.0, -300.0, -300.0,
    ];
    for (final dy in drags) {
      if (f.evaluate().isNotEmpty) break;
      await tester.drag(scrollable, Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 250));
    }
    // fail(), never an assertion: support/ is harness, not evidence
    // (e2e_support_has_no_assertions_test bans the assertion marker here,
    // by substring — comments included). This is the harness giving up,
    // the same shape as waitFor's timeout, and deleting it can't create a
    // false pass: callers immediately dead-end on the empty finder and
    // time out loudly in their own waits.
    if (f.evaluate().isEmpty) {
      fail(
        'the bubble for "${msg.text}" was not reachable by scrolling '
        'the chat list',
      );
    }
    return f;
  }

  /// Optional regen-note dialog. Blank + confirm is the product default
  /// ("just try again"). Same class as Chance Time: a modal that waits for
  /// the user, so every wait must clear it or regenerate never reaches the
  /// fake backend.
  Future<void> confirmRegenCritiqueIfAsked() async {
    final confirm = find.byKey(const Key('regen-critique-confirm'));
    if (confirm.evaluate().isEmpty) return;
    await tester.tap(confirm.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
  }

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
      await confirmRegenCritiqueIfAsked();
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
  ///
  /// `isSettlingTurn` is included deliberately, and it earns its place in every
  /// suite: the awaited post-gen critical section (needs impact, the group
  /// scalar persist, the chip attach) runs AFTER `isGenerating` clears, and its
  /// guard flag is cleared in a `finally`. If that `finally` is ever bypassed —
  /// a new early-return, a swallowed throw — the flag latches true and the app
  /// silently refuses deletes, regenerates and group edits for the rest of the
  /// session. That failure is worse than the race it prevents and is invisible
  /// in review, so every single wait in the suite now insists it clears.
  Future<void> waitSendable() => waitFor(
    () =>
        !chatService.isGenerating &&
        !chatService.isSettlingTurn &&
        !chatService.isGuestBusy &&
        !chatService.isPhotoTurnInFlight &&
        !chatService.entrancesInFlight,
    () =>
        'chat sendable (gen=${chatService.isGenerating} '
        'settling=${chatService.isSettlingTurn} '
        'guest=${chatService.isGuestBusy} '
        'photo=${chatService.isPhotoTurnInFlight} '
        'entrances=${chatService.entrancesInFlight})',
  );

  /// True when a tap at [finder]'s centre actually reaches [finder] rather
  /// than something painted over it — or clipped away.
  ///
  /// Existing in the tree is not the same as being tappable, and finders only
  /// ever answer the first question. Two ways that bites, both of which cost a
  /// CI round:
  ///  * a `showDialog` MODAL (Chance Time) leaves the send button findable by
  ///    `find.byTooltip` while every tap lands on the route's barrier —
  ///    diagnostics read `sendButtons=1` with all guards clear;
  ///  * a collapsed `SizeTransition` (the Model Manager's quant rows) builds
  ///    its child ANYWAY, so the buttons inside a collapsed card are found,
  ///    are laid out at full intrinsic size, and are clipped to nothing —
  ///    taps hit whatever is painted behind them and vanish silently.
  ///
  /// Callers must ensure [finder] resolves to exactly one widget: a
  /// `.first`/`.last`-wrapped finder THROWS on an empty tree rather than
  /// reporting empty.
  bool hitReaches(Finder finder) {
    if (finder.evaluate().isEmpty) return false;
    final target = tester.renderObject(finder);
    final result = tester.hitTestOnBinding(tester.getCenter(finder));
    return result.path.any((entry) => identical(entry.target, target));
  }

  /// Tap [targets] in order, repeating the WHOLE sequence until [done] — the
  /// generic delivery-confirmed tap.
  ///
  /// A single `tester.tap` is a coin flip anywhere the target sits in a
  /// scrollable, a dialog, or a panel that rebuilds: it can land on a
  /// barrier, on a clipped region, or on the widget's old position. With
  /// `warnIfMissed: false` (needed everywhere else) that failure is SILENT,
  /// and the suite dies minutes later at a wait naming a symptom rather than
  /// the missed tap.
  ///
  /// [targets] is a LIST because the retry unit is often more than one tap:
  /// ticking a checkbox and then pressing the button it enables only works
  /// as a pair, and retrying just the button would hammer a still-disabled
  /// control forever. Every finder must be UNWRAPPED — `.first`/`.last`
  /// throw on an empty tree instead of reporting empty.
  Future<void> tapUntilTrue(
    List<Finder> targets,
    bool Function() done,
    String Function() describe, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    for (var attempt = 0; attempt < 8 && !done(); attempt++) {
      await spinChanceTimeIfAsked();
      await confirmRegenCritiqueIfAsked();
      for (final target in targets) {
        if (target.evaluate().isEmpty) continue;
        try {
          await tester.ensureVisible(target.first);
        } on StateError {
          // Not inside a scrollable — nothing to scroll, tap where it is.
        }
        await tester.pump(const Duration(milliseconds: 200));
        if (target.evaluate().isEmpty) continue;
        await tester.tap(target.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
      }
      for (var i = 0; i < 6 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await waitFor(done, describe, timeout: timeout);
  }

  /// [tapUntilTrue] where the confirmation is simply a widget appearing.
  Future<void> tapUntil(
    List<Finder> targets,
    Finder confirmation, {
    Duration timeout = const Duration(seconds: 30),
  }) => tapUntilTrue(
    targets,
    () => confirmation.evaluate().isNotEmpty,
    () => '$confirmation to appear after tapping $targets',
    timeout: timeout,
  );

  /// Delivery-confirmed send. One tap is not enough: guards can flip in the
  /// gap between the sendable check and the tap, and the app deliberately
  /// swallows such sends (text preserved for retry). The live binding's fake
  /// keyboard connection also goes stale after the app's post-send IME churn —
  /// enterText works for turn 1 and silently no-ops later — so the controller
  /// is set directly when the IME path drops the text.
  Future<void> sendMessage(String text) async {
    bool delivered() => chatService.messages.any((m) => m.text.contains(text));
    // Deadline, not a fixed attempt count: attempts spent while a modal covers
    // the button are not evidence of anything, and a count-based budget turns
    // "the wheel happened to fire here" into a red CI leg.
    final deadline = DateTime.now().add(
      const Duration(seconds: 90) * kCiTimeoutScale,
    );
    while (!delivered() && DateTime.now().isBefore(deadline)) {
      await waitSendable();
      // Clear any Chance Time / regen-note modal BEFORE aiming at send.
      await spinChanceTimeIfAsked();
      await confirmRegenCritiqueIfAsked();
      await tester.enterText(input, text);
      final controller = tester.widget<TextField>(input).controller;
      if (controller != null && controller.text != text) {
        controller.text = text;
      }
      await tester.pump();
      // The composer is a TERNARY: `isGenerating ? StopButton : SendButton`,
      // so while a generation is live there is no 'Send message' tooltip in
      // the tree at all. waitSendable() above cleared isGenerating, but a
      // background turn (an objective-completion check, an auto-advance) can
      // flip it back in the gap before this tap — and then find.byTooltip
      // matches nothing and tester.tap throws inside _getElementPoint rather
      // than failing this loop's own retry. Re-check and give the attempt back
      // to the loop instead of exploding on a race the app is allowed to have.
      final sendBtn = find.byTooltip('Send message');
      // Two distinct not-yet states, neither of which is a failure:
      //   * absent  — the composer is `isGenerating ? Stop : Send`, so a
      //               background turn swapped the button out;
      //   * covered — a Chance Time modal (or any dialog) is over it.
      if (!hitReaches(sendBtn)) {
        await tester.pump(const Duration(milliseconds: 250));
        continue;
      }
      await tester.tap(sendBtn);
      for (var i = 0; i < 8 && !delivered(); i++) {
        await spinChanceTimeIfAsked();
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    if (delivered()) return;
    // Self-diagnosing on purpose. This failure has now cost three CI cycles of
    // guessing from a message that said only "was never accepted": every
    // early-return in _sendCurrentMessage is silent, so from the outside a
    // refused send is indistinguishable from a missed tap, a stale controller
    // or a lost finder. Report the whole guard set plus the tap surface so the
    // next red run names the cause instead of inviting another theory.
    final input0 = input.evaluate();
    final controllerText = input0.isEmpty
        ? '(input widget not found)'
        : (tester.widget<TextField>(input).controller?.text ??
              '(no controller)');
    final sendBtn = find.byTooltip('Send message').evaluate().length;
    fail(
      '"$text" was never accepted by sendMessage after 8 attempts.\n'
      '  guards : gen=${chatService.isGenerating} '
      'settling=${chatService.isSettlingTurn} '
      'guest=${chatService.isGuestBusy} '
      'photo=${chatService.isPhotoTurnInFlight} '
      'entrances=${chatService.entrancesInFlight}\n'
      '  chat   : char=${chatService.activeCharacter?.name} '
      'group=${chatService.activeGroup?.id} '
      'session=${chatService.currentSessionId}\n'
      '  tree   : inputWidgets=${input0.length} sendButtons=$sendBtn '
      'controllerText="$controllerText"\n'
      '  msgs   : ${chatService.messages.length} '
      'last=${chatService.messages.isEmpty ? "(none)" : chatService.messages.last.sender}\n'
      '  wheels : $wheelsSpun',
    );
  }

  /// The sidebar's own ListView. Anchored on the SidebarBody TYPE, never on
  /// a text inside it: the list builds lazily, so any anchor text (round 4
  /// used "Author's Note") gets CULLED once scrolled past — and then the
  /// `.first`-wrapped ancestor finder throws "No element" mid-drag, which is
  /// exactly how sidebar_sweep died on Linux after its earlier phases had
  /// scrolled the top of the list away.
  Finder get _sidebarScrollable => find
      .descendant(
        of: find.byType(SidebarBody),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Drag the chat sidebar until [target] is BUILT, tolerating both zero and
  /// multiple matches — the two states that kill scrollUntilVisible (its
  /// dragUntilVisible resolves with .single, and a `.first`-wrapped finder
  /// THROWS on an empty tree instead of reporting it, which is exactly how
  /// round 2's lorebook suite died on macOS: the sidebar ListView builds
  /// lazily, so a below-the-fold header has no element until dragged near).
  /// Downward drags first (the sidebar starts at the top), a short upward
  /// tail as insurance.
  Future<void> revealInSidebar(Finder target) async {
    const drags = [
      -250.0, -250.0, -250.0, -250.0, -250.0, -250.0, -250.0, -250.0, //
      250.0, 250.0, 250.0, 250.0,
    ];
    for (final dy in drags) {
      if (target.evaluate().isNotEmpty) break;
      await tester.drag(_sidebarScrollable, Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await waitForWidget(target, timeout: const Duration(seconds: 15));
  }

  /// Reveal the accordion header labelled [title] and expand it, confirmed
  /// by [confirmation] (a widget that only exists while the section is open
  /// — pass an UNWRAPPED finder; .first/.last throw on an empty tree).
  /// Retap is gated on CONFIRMATION PRESENCE, not on tap success: an
  /// accordion is a toggle, and retapping after a successful expand (while
  /// content still paints) would collapse it again. An edge-of-viewport tap
  /// can hit-test as a silent miss, hence ensureVisible + retry — round 4's
  /// Windows lorebook leg died on exactly one such unconfirmed tap.
  Future<void> openSidebarAccordion(String title, Finder confirmation) async {
    final header = find.text(title);
    await revealInSidebar(header);
    for (
      var attempt = 0;
      attempt < 5 && confirmation.evaluate().isEmpty;
      attempt++
    ) {
      await spinChanceTimeIfAsked();
      await tester.ensureVisible(header.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(header.first, warnIfMissed: false);
      for (var i = 0; i < 6 && confirmation.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await waitForWidget(confirmation, timeout: const Duration(seconds: 15));
  }

  /// Scroll the sidebar to the Journal & Memory accordion and expand it.
  Future<void> openJournalAccordion() =>
      openSidebarAccordion('Journal & Memory', find.byType(JournalPanel));

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

    // CLOSE IT. This is not tidiness — leaving it open puts a showDialog
    // barrier over the whole app for every phase that follows. The send button
    // stays findable behind it (finders search the entire tree), so a tap
    // "succeeds", lands on the barrier, and the message is silently never
    // sent. Because showDialog defaults to barrierDismissible: true, the first
    // stray tap outside merely DISMISSES the dialog instead of pressing the
    // button, so the suite usually limped through on the following attempt —
    // which is exactly why this presented as an intermittent, platform-flavoured
    // failure rather than an obvious one. Four CI cycles were spent on it.
    final closeBtn = find.descendant(
      of: find.byType(JournalDialog),
      matching: find.byIcon(Icons.close),
    );
    if (closeBtn.evaluate().isNotEmpty) {
      await tester.tap(closeBtn.first);
    }
    await waitFor(
      () => find.byType(JournalDialog).evaluate().isEmpty,
      () =>
          'the Journal dialog to close so later phases are not tapping '
          'through its modal barrier',
      timeout: const Duration(seconds: 15),
    );
  }
}
