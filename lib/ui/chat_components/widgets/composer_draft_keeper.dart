// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/composer_draft_store.dart';
import 'package:front_porch_ai/services/database_rebind.dart';

/// Keeps a chat's half-typed message between closes. Wraps the composer's
/// subtree on the chat page; watches [controller] and persists every
/// change (debounced) through [ComposerDraftStore], keyed to
/// [sessionId] + [draftOwner]. Reopening the chat — or switching to it
/// inside a live page — seeds the box back from the store.
///
/// It never reads [controller] after dispose (the page disposes the
/// controller before this subtree unmounts), so it mirrors the last text
/// in [_lastText] and flushes the mirror, not the box.
class ComposerDraftKeeper extends StatefulWidget {
  const ComposerDraftKeeper({
    super.key,
    required this.sessionId,
    required this.draftOwner,
    required this.fresh,
    required this.controller,
    required this.child,
  });

  final String? sessionId;

  /// [ChatService.composerDraftOwnerId] — the mailbox a never-sent
  /// draft comes home to. Null with no chat: nothing to save or restore.
  final String? draftOwner;

  /// True while the chat holds no user message yet — the web twin's
  /// rule, mirrored: those drafts ride the owner mailbox even once the
  /// greeting-save has materialized the row, so closing a new chat and
  /// starting another still offers the line back.
  final bool fresh;

  /// The page's composer box. Kept across in-page session switches, so
  /// a switch saves the old chat's line before restoring the new one's —
  /// the box never carries a line into the wrong chat.
  final TextEditingController controller;

  final Widget child;

  @override
  State<ComposerDraftKeeper> createState() => _ComposerDraftKeeperState();
}

class _ComposerDraftKeeperState extends State<ComposerDraftKeeper> {
  static const _debounce = Duration(milliseconds: 500);

  late ComposerDraftStore _store;
  Timer? _debounceTimer;

  /// Every keystroke mirrors here the moment it happens, so a flush on
  /// switch or dispose needs no controller read.
  String _lastText = '';

  /// The key [_lastText] belongs to — the session/owner the box's text
  /// was last synced against, NOT the live widget fields (which already
  /// moved on when a session switch is mid-flight).
  String? _keySessionId;
  String? _keyOwner;
  bool _keyFresh = true;

  @override
  void initState() {
    super.initState();
    _store = ComposerDraftStore(liveDatabase(context));
    _keySessionId = widget.sessionId;
    _keyOwner = widget.draftOwner;
    _keyFresh = widget.fresh;
    widget.controller.addListener(_onComposerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void didUpdateWidget(ComposerDraftKeeper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // A new box (the page rebuilt with a fresh controller): the old
      // one's text is unreachable to read if it was already disposed,
      // so just re-attach and let the store answer for the chat.
      oldWidget.controller.removeListener(_onComposerChanged);
      widget.controller.addListener(_onComposerChanged);
      _lastText = '';
      _restore();
    }
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.draftOwner != widget.draftOwner) {
      // The box still holds the OLD chat's line — put it away under the
      // old key before the new chat's draft touches it.
      _flush();
      _restore();
    } else if (oldWidget.fresh != widget.fresh) {
      // The same chat crossed its first send: its draft changes doors.
      // The send cleared the box, and an empty write clears both homes,
      // so re-pointing the mirror is all this needs.
      _keyFresh = widget.fresh;
    }
  }

  void _onComposerChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _persist);
  }

  void _persist() {
    final owner = _keyOwner;
    if (owner == null) return;
    unawaited(
      _store
          .saveDraft(
            sessionId: _keySessionId,
            ownerKey: owner,
            fresh: _keyFresh,
            text: _lastText,
          )
          // A draft write that races a database swap (backup restore,
          // storage-root move — every liveDatabase story) loses the
          // draft, not the app. Letting it throw unhandled would crash.
          .catchError((Object _) {}),
    );
  }

  /// Write the mirror now — used on session switch and on leaving the
  /// page, where the debounce would otherwise eat the last keystrokes.
  void _flush() {
    _debounceTimer?.cancel();
    _persist();
  }

  Future<void> _restore() async {
    final sessionId = widget.sessionId;
    final owner = widget.draftOwner;
    final fresh = widget.fresh;
    _keySessionId = sessionId;
    _keyOwner = owner;
    _keyFresh = fresh;
    // The box right now may still carry the previous chat's flushed
    // line; that line, not user input, is ours to clear.
    final carried = _lastText.isNotEmpty && widget.controller.text == _lastText;
    _lastText = '';
    if (owner == null) return;
    final String draft;
    try {
      draft = await _store.loadDraft(
        sessionId: sessionId,
        ownerKey: owner,
        fresh: fresh,
      );
    } catch (_) {
      // Same story as _persist: a database mid-swap simply has no
      // draft to offer this box right now.
      return;
    }
    if (!mounted) return;
    if (widget.sessionId != sessionId || widget.draftOwner != owner) return;
    if (draft.isEmpty) {
      if (carried) {
        _lastText = '';
        widget.controller.clear();
      }
      return;
    }
    // Never overwrite (or duplicate) anything typed while the load ran.
    if (widget.controller.text.isNotEmpty && !carried) return;
    _lastText = draft;
    widget.controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onComposerChanged);
    _flush();
    super.dispose();
  }
}
