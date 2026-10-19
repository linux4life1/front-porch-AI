// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Publishes the find controller to mounted bubbles. Bubbles rebuild only
/// when the highlights change (a scan lands, a step, open/close), never for
/// bar-only ticks like typing or the backfill progress poll. Null-scope
/// (waifu, previews, dialogs) = no highlights, zero cost on the normal path.
class FindHighlightScope extends InheritedNotifier<Listenable> {
  FindHighlightScope({
    super.key,
    required this.controller,
    required super.child,
  }) : super(notifier: controller.highlights);

  final ChatFindController controller;

  static ChatFindController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FindHighlightScope>()
      ?.controller;
}

/// Splits finished leaf spans around engine matches of the active find
/// query. Body leaves share one instance per message build so occurrences
/// count in assembly order — the same numbering the scanner used — and
/// exactly the active occurrence paints strong. [senderRegion] leaves are
/// the bubble header: its active hit is occurrence 0 of the sender name.
class FindLeafSplit {
  final FindLeafState? state;
  final Color honey;
  final bool senderRegion;
  int _occurrence = 0;

  FindLeafSplit(this.state, this.honey, {this.senderRegion = false});

  List<TextSpan> expand(String text, TextStyle? base) {
    final st = state;
    if (st == null) return [TextSpan(text: text, style: base)];
    final ranges = chatQueryRanges(text, st.spec);
    if (ranges.isEmpty) return [TextSpan(text: text, style: base)];
    final out = <TextSpan>[];
    var pos = 0;
    for (final r in ranges) {
      if (r.start > pos) {
        out.add(TextSpan(text: text.substring(pos, r.start), style: base));
      }
      final isActive = senderRegion
          ? (_occurrence == 0 && st.activeSender)
          : _occurrence == st.activeBodyOccurrence;
      out.add(
        TextSpan(
          text: text.substring(r.start, r.end),
          style: isActive
              ? (base ?? const TextStyle()).copyWith(
                  backgroundColor: honey,
                  color: AppColors.inkOn(honey),
                  fontWeight: FontWeight.w600,
                )
              : (base ?? const TextStyle()).copyWith(
                  backgroundColor: honey.withValues(alpha: 0.25),
                ),
        ),
      );
      _occurrence++;
      pos = r.end;
    }
    if (pos < text.length) {
      out.add(TextSpan(text: text.substring(pos), style: base));
    }
    return out;
  }
}

/// What one bubble needs to paint its find highlights: the compiled query to
/// self-split its leaf spans with, and which occurrence / the sender header
/// is the ACTIVE one. Mirrors the reviewed mockup's leaf-level matching;
/// matches may span formatting boundaries — those partials are a documented
/// cosmetic caveat, counts and jumps stay exact.
class FindLeafState {
  final ChatQuerySpec spec;
  final int? activeBodyOccurrence;
  final bool activeSender;
  const FindLeafState({
    required this.spec,
    this.activeBodyOccurrence,
    this.activeSender = false,
  });
}

/// ⌘F find-in-chat state, owned by the chat page. Count/navigation truth is
/// the Dart engine scan (`ChatService.findInTranscript`, which waits for the
/// history backfill); bubbles highlight via [leafStateFor]. Re-scans on any
/// transcript change while open (edits, swipes, regens change visible text)
/// and closes itself when the session changes. Listeners (the bar) hear
/// every change; [highlights] fires only when what bubbles paint changes.
class ChatFindController extends ChangeNotifier {
  ChatFindController();

  /// Bumped whenever [leafStateFor] can answer differently.
  final ValueNotifier<int> highlights = ValueNotifier<int>(0);
  bool _disposed = false;

  final TextEditingController text = TextEditingController();

  /// Enter / Shift+Enter step, Esc closes — a node handler, the same shape
  /// the composer's _chatFocusNode uses, so the editable cannot eat the key
  /// before the bar does.
  late final FocusNode focus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        close();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  ChatService? _service;
  void Function(int messageIndex)? onNavigate;

  bool open = false;
  bool regexOn = false;
  bool caseSensitive = false;

  /// True while the scan is parked on `_awaitHistoryHydrated()`; the bar
  /// shows spinner + loaded/total instead of a count.
  bool waiting = false;
  int loadedCount = 0;
  int totalCount = 0;

  ChatQuerySpec _spec = compileChatQuery('');
  List<ChatFindMatch> matches = const [];
  int active = -1;

  int _scanSeq = 0;
  String? _scanSessionId;
  Timer? _debounce;
  Timer? _poll;
  Map<ChatMessage, FindLeafState> _leafMap =
      Map<ChatMessage, FindLeafState>.identity();

  bool get badPattern => _spec.bad;
  bool get hasQuery => !_spec.isEmpty && !_spec.bad;
  String get counterLabel {
    if (matches.isEmpty) return 'No matches';
    final total = matches.length >= kFindMatchCap
        ? '999+'
        : '${matches.length}';
    return '${active + 1} / $total';
  }

  void attach(ChatService service) {
    _service = service;
    service.addListener(_onTranscriptChanged);
  }

  void _changed({bool repaintBubbles = false}) {
    if (_disposed) return;
    if (repaintBubbles) highlights.value++;
    notifyListeners();
  }

  void openFind() {
    final wasOpen = open;
    open = true;
    _changed(repaintBubbles: !wasOpen);
    focus.requestFocus();
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
    if (text.text.trim().isNotEmpty) _runScan();
  }

  void close() {
    open = false;
    waiting = false;
    _debounce?.cancel();
    _poll?.cancel();
    matches = const [];
    active = -1;
    _leafMap = Map<ChatMessage, FindLeafState>.identity();
    _changed(repaintBubbles: true);
  }

  /// The query text changed: debounced scan that starts over at the first
  /// match and jumps to it.
  void scheduleScan() => _debounceScan(fresh: true);

  void _debounceScan({required bool fresh}) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => _runScan(fresh: fresh),
    );
  }

  void toggleRegex() {
    regexOn = !regexOn;
    _runScan();
  }

  void toggleCase() {
    caseSensitive = !caseSensitive;
    _runScan();
  }

  void step(int direction) {
    if (matches.isEmpty) return;
    active = (active + direction + matches.length) % matches.length;
    final service = _service;
    if (service != null) _rebuildLeafMap(service.messages);
    onNavigate?.call(matches[active].messageIndex);
    _changed(repaintBubbles: true);
  }

  void _onTranscriptChanged() {
    if (!open) return;
    final service = _service;
    if (service == null) return;
    if (_scanSessionId != null && service.currentSessionId != _scanSessionId) {
      close();
      return;
    }
    // Debounced re-scan keeps counts honest after edits/swipes/regens. It
    // keeps the reader's place: a new reply or a sidebar notify must not
    // yank the transcript back to the active match.
    _debounceScan(fresh: false);
  }

  /// [fresh]: the query or a mode changed, so start at the first match and
  /// jump there. Otherwise only the transcript moved: keep the active hit
  /// and the scroll position.
  Future<void> _runScan({bool fresh = true}) async {
    final service = _service;
    if (service == null || !open) return;
    final seq = ++_scanSeq;
    _scanSessionId = service.currentSessionId;
    _spec = compileChatQuery(
      text.text,
      regexMode: regexOn,
      caseSensitive: caseSensitive,
    );
    if (_spec.bad) {
      matches = const [];
      active = -1;
      _leafMap = Map<ChatMessage, FindLeafState>.identity();
      _changed(repaintBubbles: true);
      return;
    }
    waiting = service.isBackfillingHistory;
    if (waiting) _startPolling(service);
    _changed();
    final outcome = await service.findInTranscript(
      text.text,
      regexMode: regexOn,
      caseSensitive: caseSensitive,
    );
    if (seq != _scanSeq || !open) return;
    if (outcome.stale) {
      unawaited(_runScan(fresh: fresh));
      return;
    }
    _poll?.cancel();
    waiting = false;
    matches = outcome.matches;
    active = matches.isEmpty
        ? -1
        : fresh
        ? 0
        : active.clamp(0, matches.length - 1);
    _rebuildLeafMap(service.messages);
    if (fresh && active >= 0) onNavigate?.call(matches[active].messageIndex);
    _changed(repaintBubbles: true);
  }

  /// The backfill loop notifies once at the end, so the bar's
  /// "2,400 / 11,382" line polls while the scan awaits hydration.
  void _startPolling(ChatService service) {
    totalCount = 0;
    loadedCount = service.messages.length;
    _poll?.cancel();
    unawaited(
      service.countAllMessages().then((n) {
        if (open && waiting) totalCount = n;
      }),
    );
    _poll = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!open || !waiting) {
        timer.cancel();
        return;
      }
      loadedCount = service.messages.length;
      _changed();
    });
  }

  /// Highlight state for one bubble, or null when nothing to paint.
  FindLeafState? leafStateFor(ChatMessage message) =>
      open && hasQuery ? _leafMap[message] : null;

  ChatFindMatch? get activeHit =>
      active >= 0 && active < matches.length ? matches[active] : null;

  void _rebuildLeafMap(List<ChatMessage> messages) {
    final next = Map<ChatMessage, FindLeafState>.identity();
    for (final hit in matches) {
      if (hit.messageIndex < 0 || hit.messageIndex >= messages.length) continue;
      final message = messages[hit.messageIndex];
      final isActive = identical(hit, activeHit);
      final existing = next[message];
      next[message] = FindLeafState(
        spec: _spec,
        activeBodyOccurrence: isActive && hit.region == findRegionBody
            ? hit.occurrenceInRegion
            : existing?.activeBodyOccurrence,
        activeSender: isActive && hit.region == findRegionSender
            ? true
            : (existing?.activeSender ?? false),
      );
    }
    _leafMap = next;
  }

  @override
  void dispose() {
    _disposed = true;
    highlights.dispose();
    _debounce?.cancel();
    _poll?.cancel();
    _service?.removeListener(_onTranscriptChanged);
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
