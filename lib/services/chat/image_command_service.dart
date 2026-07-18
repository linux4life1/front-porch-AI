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

import 'dart:typed_data';

/// What a parsed `/image` command asks for. [kind] selects the generation
/// mode; [text] carries the free text (a character name for `char`, the raw
/// prompt for `raw`, the scene description for `custom`, empty otherwise).
enum ImageCommandKind { scene, me, character, raw, custom }

/// Parsed form of the `/image` slash-command arguments.
class ImageCommandRequest {
  const ImageCommandRequest(this.kind, [this.text = '']);

  final ImageCommandKind kind;
  final String text;
}

/// Orchestrates in-chat image generation for the `/image` slash command
/// (SillyTavern-style): parse the subcommand, craft a prompt from the live
/// chat context, generate through the configured image backend, and attach
/// the result to the conversation.
///
/// This leaf keeps the flow out of the `ChatService` god file. It never
/// imports `ChatService` or `ImageGenService` — every action is injected as a
/// small callback (same pattern as `ChatCommandHandler`), so it stays pure
/// and unit-testable with plain closures. It does ZERO Realism/Needs work and
/// behaves identically in 1:1 and group chats (the wiring decides which
/// character the image is attached to; the flow here is mode-agnostic).
class ImageCommandService {
  ImageCommandService({
    required bool Function() isConfigured,
    required bool Function() isBusy,
    required void Function(String message, {bool sticky}) onStatus,
    required Future<String?> Function(ImageCommandRequest request) craftPrompt,
    required Future<Uint8List?> Function(
      String prompt,
      ImageCommandRequest request,
    )
    generate,
    required Future<String?> Function(Uint8List bytes) saveImage,
    // Returns true if the image was actually attached, false if it was dropped
    // (e.g. the user switched chats mid-gen) so the run doesn't post a false
    // "added to the chat" success line over the drop's own status.
    required Future<bool> Function(
      String path,
      String prompt,
      ImageCommandRequest request,
      Object? launchToken,
    )
    attachToChat,
    Object? Function()? snapshotSession,
    void Function()? notifyRunStateChanged,
  }) : _isConfigured = isConfigured,
       _isBusy = isBusy,
       _onStatus = onStatus,
       _craftPrompt = craftPrompt,
       _generate = generate,
       _saveImage = saveImage,
       _attachToChat = attachToChat,
       _snapshotSession = snapshotSession,
       _notifyRunStateChanged = notifyRunStateChanged;

  final bool Function() _isConfigured;
  final bool Function() _isBusy;
  final void Function(String message, {bool sticky}) _onStatus;
  final Future<String?> Function(ImageCommandRequest request) _craftPrompt;
  final Future<Uint8List?> Function(String prompt, ImageCommandRequest request)
  _generate;
  final Future<String?> Function(Uint8List bytes) _saveImage;
  final Future<bool> Function(
    String path,
    String prompt,
    ImageCommandRequest request,
    Object? launchToken,
  )
  _attachToChat;

  /// Snapshots an OPAQUE token identifying the chat/session this run belongs
  /// to (captured at run start, passed back to [attachToChat] so the wiring
  /// can drop the result if the user switched chats during the slow gen). The
  /// leaf never interprets it — it just carries it, keeping this pure.
  final Object? Function()? _snapshotSession;
  final void Function()? _notifyRunStateChanged;

  /// Guards against overlapping `/image` runs (generation is slow). Public
  /// read so the chat UI can show the in-progress bubble while a run is live.
  bool _generating = false;
  bool get generating => _generating;

  /// Parse `/image` arguments into a typed request. Pure and static so the
  /// grammar is unit-testable without any wiring:
  ///   `/image`                  → visualize the current scene
  ///   `/image scene`            → same
  ///   `/image last`             → the last message only
  ///   `/image me`               → the user's persona portrait
  ///   `/image char [name]`      → a character portrait (name optional)
  ///   `/image raw ...`          → send the rest to the backend verbatim
  ///   `/image ...`              → LLM-crafted image of the description
  static ImageCommandRequest parse(String args) {
    final trimmed = args.trim();
    if (trimmed.isEmpty) {
      return const ImageCommandRequest(ImageCommandKind.scene);
    }
    final spaceIdx = trimmed.indexOf(RegExp(r'\s'));
    final head = (spaceIdx < 0 ? trimmed : trimmed.substring(0, spaceIdx))
        .toLowerCase();
    final rest = spaceIdx < 0 ? '' : trimmed.substring(spaceIdx + 1).trim();

    switch (head) {
      case 'scene':
      case 'here':
        return const ImageCommandRequest(ImageCommandKind.scene);
      case 'last':
        return const ImageCommandRequest(ImageCommandKind.scene, 'last');
      case 'me':
      case 'self':
        return const ImageCommandRequest(ImageCommandKind.me);
      case 'char':
      case 'character':
      case 'portrait':
      case 'you':
        return ImageCommandRequest(ImageCommandKind.character, rest);
      case 'raw':
        return ImageCommandRequest(ImageCommandKind.raw, rest);
      default:
        // Free text → an LLM-crafted custom image of whatever was described.
        return ImageCommandRequest(ImageCommandKind.custom, trimmed);
    }
  }

  /// Run the full `/image` flow for [args]. Errors surface through the status
  /// banner (⚠ prefix = error, matching the other slash commands) — this never
  /// throws for user-facing failures.
  Future<void> handle(String args) async {
    if (!_isConfigured()) {
      _onStatus(
        '⚠ Image generation is not set up. Enable it in Settings and '
        'configure a backend in the Image Studio.',
        sticky: false,
      );
      return;
    }
    if (_generating || _isBusy()) {
      _onStatus('⚠ Busy — try again in a moment.', sticky: false);
      return;
    }

    final request = parse(args);
    if (request.kind == ImageCommandKind.raw && request.text.isEmpty) {
      _onStatus('⚠ Usage: /image raw <prompt>', sticky: false);
      return;
    }

    _generating = true;
    _notifyRunStateChanged?.call();
    // Which chat this run belongs to — checked at attach time so a slow gen
    // (1-10 min local) whose user switched chats can't land in the wrong one.
    final launchToken = _snapshotSession?.call();
    try {
      String? prompt;
      if (request.kind == ImageCommandKind.raw) {
        prompt = request.text;
      } else {
        _onStatus('🎨 Crafting image prompt…', sticky: true);
        prompt = await _craftPrompt(request);
        // null = stop silently — the callback already surfaced its own
        // message (e.g. the user cancelled the prompt review).
        if (prompt == null) return;
      }
      if (prompt.trim().isEmpty) {
        _onStatus('⚠ Couldn’t build an image prompt for that.', sticky: false);
        return;
      }

      _onStatus('🎨 Generating image…', sticky: true);
      final bytes = await _generate(prompt, request);
      if (bytes == null || bytes.isEmpty) {
        _onStatus(
          '⚠ Image generation failed — check the backend connection in the '
          'Image Studio.',
          sticky: false,
        );
        return;
      }

      final path = await _saveImage(bytes);
      if (path == null || path.isEmpty) {
        _onStatus('⚠ Couldn’t save the generated image.', sticky: false);
        return;
      }

      final attached = await _attachToChat(path, prompt, request, launchToken);
      // The drop path posts its own "you left the chat" status; only claim
      // success when the image actually landed.
      if (attached) {
        _onStatus('🎨 Image added to the chat.', sticky: false);
      }
    } finally {
      _generating = false;
      _notifyRunStateChanged?.call();
    }
  }
}
