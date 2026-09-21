// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

part of 'chat_facade.dart';

/// Swipe, edit/delete, personas, and session history for [ChatFacade].
extension ChatFacadeHistory on ChatFacade {
  Map<String, dynamic> variants(int messageIndex) =>
      _chat.variantPickerPayload(messageIndex);

  Future<void> selectVariant(int messageIndex, int variantIndex) async {
    await _chat.selectVariant(messageIndex, variantIndex);
    _notify();
  }

  /// AI writes the user's next line into the composer (desktop wand parity).
  /// Tokens ride a dedicated `impersonate` WS event — never the `token`
  /// bubble stream.
  void impersonate(String prefix) {
    unawaited(
      _chat
          .impersonateUser(
            prefix: prefix,
            onToken: (acc) => _hub?.broadcastImpersonate(acc),
          )
          .whenComplete(() {
            _hub?.broadcastImpersonateDone();
            _notify();
          }),
    );
    _notify();
  }

  /// Director redo: re-evaluate a message's Needs deltas using the user's
  /// written [critique]. Awaited (it runs LLM evals) so the route can report the
  /// outcome; the new deltas + a pre-reprocess stash land in the message's
  /// metadata, which the next state fetch surfaces as chips. Reuses the existing
  /// ChatService flow — no parallel logic.
  /// [onlyNeeds] scopes the pass to those needs; empty re-evaluates all of
  /// them. Additive on the wire — an older PWA that omits it keeps the
  /// all-needs behaviour it has always had.
  Future<bool> reprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) async {
    final ok = await _chat.manualReprocessNeeds(
      index,
      critique,
      onlyNeeds: onlyNeeds,
    );
    _notify();
    return ok;
  }

  /// Restore a message's Needs deltas + live state from the pre-reprocess stash.
  Future<bool> revertNeedsReprocess(int index) async {
    final ok = await _chat.revertNeedsReprocess(index);
    _notify();
    return ok;
  }

  void swipe(int messageIndex, int direction, {String? critique}) {
    _chat.swipeMessage(messageIndex, direction, critique: critique);
    _notify();
  }

  void edit(int index, String text) {
    _chat.editMessage(index, text);
    _notify();
  }

  void delete(int index) {
    _chat.deleteMessage(index);
    _notify();
  }

  /// Attach a generated image (saved under `KoboldManager/images/`) to the
  /// conversation as its own image message — the SAME path the desktop's
  /// /image command and the Image Studio's "Send to chat" use
  /// (ChatServiceImages.addGeneratedImageMessage), so it renders identically
  /// on both surfaces. Replaces the old markdown-append-to-last-message hack,
  /// which never rendered on desktop (relative URLs aren't matched by the
  /// markdown-image regex) and mutated an unrelated message.
  /// Resolve a parked /image prompt review from the web modal: the (possibly
  /// edited) prompt to generate with, or null to cancel. No-op when nothing
  /// is pending (e.g. the desktop dialog resolved it first).
  void resolveImageReview(String? prompt) {
    _chat.resolveImagePromptReview(prompt);
    _notify();
  }

  Future<bool> insertImage(String filename, {String prompt = ''}) async {
    final file = _resolveSavedImage?.call(filename.trim());
    if (file == null) return false;
    await _chat.addGeneratedImageMessage(file.path, prompt);
    _notify();
    return true;
  }

  void setAuthorNote(String note, {int? strength}) {
    _chat.setAuthorNote(note, strength: strength);
    _notify();
  }

  /// All user personas for the web persona surfaces.
  ///
  /// Two flags, because there are two distinct answers: `default` is who a NEW
  /// chat starts as (Settings), `active` is who the CURRENT chat is speaking as
  /// (the in-chat switcher). `active` is kept for older PWA builds that only
  /// know that key — additive-only, per the API contract.
  List<Map<String, dynamic>> personas() {
    final svc = _personas;
    if (svc == null) return const [];
    final activeId = svc.persona.id;
    final defaultId = svc.defaultPersonaId;
    return svc.personas
        .map(
          (p) => {
            'id': p.id,
            'label': p.displayLabel,
            'name': p.name,
            'active': p.id == activeId,
            'default': p.id == defaultId,
          },
        )
        .toList();
  }

  /// Change which persona NEW chats start as (Settings → Personas). Leaves the
  /// open chat alone. Returns false if personas aren't wired.
  Future<bool> setPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setDefaultPersona(id);
    _notify();
    return true;
  }

  /// Speak as [id] in the CURRENT chat, and bind the session to it — the web
  /// counterpart of the desktop composer's persona switcher. Saves immediately
  /// so the binding survives a reload even if the user says nothing else.
  Future<bool> setChatPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setActivePersona(id);
    await _chat.persistSessionPersona();
    _notify();
    return true;
  }

  /// Full persona detail for the editor (text + name/title), or null if absent.
  Map<String, dynamic>? personaDetail(String id) {
    final svc = _personas;
    if (svc == null) return null;
    for (final p in svc.personas) {
      if (p.id == id) {
        return {
          'id': p.id,
          'title': p.title,
          'name': p.name,
          'persona': p.persona,
          'birthday': p.birthday,
        };
      }
    }
    return null;
  }

  /// Create a new persona (and make it active, matching the desktop). Returns
  /// false if personas aren't wired.
  Future<bool> createPersona(Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.createPersona(
      f['title']?.toString() ?? '',
      f['name']?.toString() ?? 'User',
      f['persona']?.toString() ?? '',
      null,
      birthday: f['birthday']?.toString() ?? '',
    );
    _notify();
    return true;
  }

  /// Edit an existing persona's text fields (only provided keys change).
  Future<bool> updatePersona(String id, Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    UserPersona? existing;
    for (final p in svc.personas) {
      if (p.id == id) {
        existing = p;
        break;
      }
    }
    if (existing == null) return false;
    await svc.updatePersona(
      existing.copyWith(
        title: f.containsKey('title') ? f['title']?.toString() : null,
        name: f.containsKey('name') ? f['name']?.toString() : null,
        persona: f.containsKey('persona') ? f['persona']?.toString() : null,
        birthday: f.containsKey('birthday') ? f['birthday']?.toString() : null,
      ),
    );
    _notify();
    return true;
  }

  /// Delete a persona. The service refuses to delete the last one (throws),
  /// which we surface as false. Returns false if personas aren't wired.
  Future<bool> deletePersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    try {
      await svc.deletePersona(id);
    } catch (_) {
      return false;
    }
    _notify();
    return true;
  }

  /// All saved conversations. See [ChatSessionFacade.list].
  Future<List<Map<String, dynamic>>> sessions({
    String? characterId,
    String? groupId,
  }) => _sessions.list(characterId: characterId, groupId: groupId);

  /// New / load / delete. See [ChatSessionFacade.apply].
  Future<String?> session({
    String? action,
    String? sessionId,
    bool startReplacement = true,
  }) => _sessions.apply(
    action: action,
    sessionId: sessionId,
    startReplacement: startReplacement,
  );

  /// Fork at [messageIndex]. See [ChatSessionFacade.fork].
  Future<String?> fork(int messageIndex) => _sessions.fork(messageIndex);

  String? get currentSessionId => _chat.currentSessionId;

  /// The chat-scoped lorebook as web editor rows (full-fidelity via `ext`).
  Map<String, dynamic> chatLorebookRows() => {
    'entries': lorebookEntriesToJson(_chat.chatLorebook),
  };

  /// Replace the chat-scoped lorebook from web editor rows. An empty/absent
  /// list clears it. Returns false when no session is active.
  Future<bool> setChatLorebook(dynamic rowsJson) async {
    if (_chat.currentSessionId == null) return false;
    final built = buildLorebookFromJson(rowsJson);
    _chat.chatLorebook.entries
      ..clear()
      ..addAll(built?.entries ?? const []);
    await _chat.commitChatLorebookEdit();
    _notify();
    return true;
  }

  /// Save per-chat theme overrides from the web UI.
  Future<bool> setThemeOverrides(Map<String, dynamic> json) async {
    if (_chat.currentSessionId == null) return false;
    _chat.sessionThemeOverrides = ChatThemeOverrides.fromJson(json);
    _notify();
    return true;
  }

  /// Mutation-free "would trigger next" preview for a composer draft —
  /// display names of idle entries the draft would wake up.
  List<String> lorePreview(String draft) => [
    for (final e in _chat.previewLoreTriggers(draft)) e.displayName,
  ];
}
