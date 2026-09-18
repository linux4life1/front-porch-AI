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

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Barrel imports for high-frequency services, models, utils, and widgets
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/overlays/absence_recap_banner.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

// Specific dialogs and modules not covered by the barrels (or intentionally direct)
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_dialog.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/home/open_section_env.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
// Old ImageGenDialog removed in Stage 3 (full from-scratch Image Studio).
// Studio launched below; see lib/ui/image_studio/ and _showImageGenDialog.
// Stage 3 Image Studio (replaces old image_gen_dialog completely)
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
part 'chat_page.image_consent.dart';
part 'chat_page.input.dart';
part 'chat_page.scene_dialogs.dart';
part 'chat_page.session_dialogs.dart';
part 'chat_page.input_actions.dart';
part 'chat_page.input_bar.dart';
part 'chat_page.sidebar.dart';
part 'chat_page.sidebar_widgets.dart';
part 'chat_page.speakers.dart';
part 'chat_page_overlays.dart';
part 'chat_page_sidebar_host.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// Custom-background existence memo — see the io-lint gate. Cleared
  /// implicitly on page remount; a deleted bg file shows stale until then,
  /// same visual outcome as before (background simply doesn't render).
  final Map<String, bool> _bgExistsCache = {};

  final StyledTextController _controller = StyledTextController(
    preset: StyledTextPreset.chat,
  );
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _chatFocusNode;
  bool _autoScroll = true;
  // Journal receipts tap-to-jump: the just-landed-on bubble, briefly tinted.
  ChatMessage? _jumpFlashMessage;
  // Bubble keys for tap-to-jump, owned by THIS page instance. They used to
  // be `GlobalObjectKey(msg)` — whose identity is the message alone — and a
  // GlobalKey must be unique across the whole app. Two ChatPage routes can
  // be alive in the same frame (a push over a not-yet-disposed page, or the
  // frames of a route transition), and both listen to the same ChatService,
  // so a chat switch had BOTH pages building bubbles for the same message
  // objects: one duplicate-key crash per visible message, then cascading
  // tree corruption (maintainer repro, 2026-08-10). Keys minted per page
  // instance can never collide across pages; jumpToMessage looks them up
  // through [_bubbleKeyOf]. Identity map on purpose: message equality is
  // identity everywhere else (list diffing, jump targets, flash).
  final Map<ChatMessage, GlobalKey> _bubbleKeys = HashMap.identity();
  // Prune marker: entries live until the session changes (or the page dies),
  // so a long-lived page can't accumulate every past chat's messages.
  String? _bubbleKeysSessionId;
  double _sidebarWidth = SidebarTokens.widthFromEnvironment();
  int _inputMinLines = 1;
  double _dragAccumulator = 0;
  bool _isCallActive = false;
  // Guards the Scene Guest detection popup so it cannot stack while open.
  bool _showingGuestDetection = false;
  bool _showingGuestPicker = false;
  bool _showingImageReview = false;
  // Pending photo attachment for the next user message (bytes already
  // downscaled + PNG re-encoded by pickChatImageAttachment). visionOk is
  // null while the capability resolver is still checking the active model;
  // blindReason carries the backend-specific "why" for the chip's
  // last-resort explanation when the check fails.
  Uint8List? _pendingImageBytes;
  bool? _pendingImageVisionOk;
  String? _pendingImageBlindReason;
  bool? _externalImagesAllowed;
  bool _imageConsentChecked = false;
  TtsService? _ttsService;
  ChatService? _chatService;

  // Slider drag tracking — store live value during drag, null on release
  double? _dragDirectorDelay;

  /// The cast participant whose per-character sidebar sections are shown.
  /// `null` = focus the host / first participant. Falls back automatically when
  /// the id is no longer in the active cast (e.g. after switching chats).
  String? _focusedParticipantId;

  /// Platform-appropriate label for the regenerate shortcut (#86), surfaced in
  /// the Generate-reply button tooltip so keyboard users can discover it.
  String get _regenShortcutLabel => Platform.isMacOS ? '⌘R' : 'Ctrl+R';

  @override
  void initState() {
    super.initState();
    _loadInputSettings();
    _chatFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (HardwareKeyboard.instance.isShiftPressed) {
            return KeyEventResult.ignored; // let the TextField insert a newline
          }
          // Bare Enter → send message (shared path with the send button,
          // so a pending photo attachment rides along here too)
          final chatService = Provider.of<ChatService>(context, listen: false);
          _sendCurrentMessage(chatService);
          return KeyEventResult.handled;
        }
        // ⌘R (macOS) / Ctrl+R — (re)generate the last AI reply. If the previous
        // reply was deleted, regenerateLastMessage() generates a fresh one from
        // the trailing user prompt instead (it handles both). Mirrors the
        // Generate-reply toolbar button / bubble regen for keyboard users.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyR &&
            (Platform.isMacOS
                ? HardwareKeyboard.instance.isMetaPressed
                : HardwareKeyboard.instance.isControlPressed)) {
          final chatService = Provider.of<ChatService>(context, listen: false);
          if (!chatService.isGenerating && !chatService.isGuestBusy) {
            final last = chatService.messages.isEmpty
                ? null
                : chatService.messages.last;
            if (last != null &&
                !last.isUser &&
                last != chatService.messages.first) {
              unawaited(
                promptRegenCritiqueThen(
                  context,
                  (c) => chatService.regenerateLastMessage(critique: c),
                ),
              );
            } else {
              chatService.regenerateLastMessage();
            }
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    // Listen for TTS errors (e.g. ElevenLabs quota exceeded) and show a snackbar.
    final tts = Provider.of<TtsService>(context, listen: false);
    _ttsService = tts;
    tts.addListener(_onTtsChanged);

    // Listen for Chaos Mode auto-triggers
    final chat = Provider.of<ChatService>(context, listen: false);
    _chatService = chat;
    chat.addListener(_onChatServiceChanged);

    // Resume timer if this is a pre-existing chat with history
    chat.resumeDynamicResponses();
  }

  // Lifecycle pausing intentionally omitted — the idle timer should fire when
  // the user walks away (minimized/backgrounded). Pausing on dispose (page
  // navigation) is sufficient to prevent phantom generations.

  void _onChatServiceChanged() {
    if (!mounted) return;
    final chat = _chatService;
    if (chat == null) return;
    if (chat.chanceTimePendingTrigger) {
      chat.consumeChanceTimeTrigger();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showChanceTimeOverlay(context),
      );
    }
    // Scene Guest cast detection — same Chance-Time-style pending-flag pattern.
    if (chat.pendingGuestDetection != null && !_showingGuestDetection) {
      _showingGuestDetection = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showGuestDetectionDialog(chat),
      );
    }
    // Scene Guest `/join` picker — same pending-flag pattern.
    if (chat.pendingGuestPickerFilter != null && !_showingGuestPicker) {
      _showingGuestPicker = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showGuestPickerDialog(chat),
      );
    }
    // /image prompt review — same pending-flag pattern (review setting on).
    if (chat.pendingImagePromptReview != null && !_showingImageReview) {
      _showingImageReview = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showImagePromptReviewDialog(chat),
      );
    }
    // A guest's background portrait finished — evict its stale cached image so
    // the new art replaces the initials avatar.
    final evictPath = chat.guestAvatarEvictPath;
    if (evictPath != null) {
      chat.consumeGuestAvatarEvict();
      FileImage(_resolveCharImage(evictPath)).evict().then((_) {
        if (mounted) setState(() {});
      });
    }
    // A guest just /exit-ed — offer a brief UNDO (delete the departure message
    // + restore the guest with full context). Consume the offer so it shows once.
    final exitUndoName = chat.exitUndoOfferName;
    if (exitUndoName != null) {
      chat.consumeExitUndoOffer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text('$exitUndoName left the scene'),
            duration: const Duration(seconds: 8),
            // Flutter's SnackBar.persist defaults to `action != null`, so an
            // action snackbar silently ignores its duration and stays forever
            // (the auto-dismiss timer fires but early-returns on persist). We
            // want it to disappear after 8s, so opt out explicitly.
            persist: false,
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => _chatService?.undoLastExit(),
            ),
          ),
        );
      });
    }
  }

  void _onTtsChanged() {
    final tts = _ttsService;
    if (tts != null && tts.lastError != null && mounted) {
      final error = tts.lastError!;
      tts.clearError();
      // A TTS error mid-call ends the call. Unmounting CallOverlay runs its
      // dispose teardown — mic released, call session ended, callMode
      // cleared. (Before the overlay owned teardown, this line only HID the
      // overlay: the mic kept listening and auto-sending, headless.)
      if (_isCallActive) {
        setState(() => _isCallActive = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(error, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFB91C1C),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          // Opt out of Flutter's persist-when-action default so the 6s duration
          // is honored (otherwise this error toast never leaves the screen).
          persist: false,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white70,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _loadInputSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _inputMinLines = prefs.getInt('input_min_lines') ?? 1;
    });
  }

  Future<void> _saveInputMinLines(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('input_min_lines', value);
  }

  void _handleInputResize(double deltaPixels) {
    _dragAccumulator -= deltaPixels;
    final pixelsPerLine = 8.0;
    final deltaLines = (_dragAccumulator / pixelsPerLine).floor();
    if (deltaLines != 0) {
      _dragAccumulator -= deltaLines * pixelsPerLine;
      final newLines = _inputMinLines + deltaLines;
      if (newLines >= 1 && newLines <= 8) {
        setState(() => _inputMinLines = newLines);
        _saveInputMinLines(newLines);
      }
    }
  }

  @override
  void dispose() {
    _chatService?.pauseDynamicResponses();
    _ttsService?.removeListener(_onTtsChanged);
    _chatService?.removeListener(_onChatServiceChanged);
    _chatFocusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _autoScroll) {
      // ListView is reversed: position 0 = visual bottom (most recent).
      // While streaming this fires per token batch — each animateTo would
      // interrupt and restart the previous 300 ms curve, churning the scroll
      // position every frame. Jump instantly during generation; keep the
      // smooth ease for one-shot scrolls (send, page open).
      final chat = context.read<ChatService>();
      if (chat.isGenerating) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, child) {
        final character = chatService.activeCharacter;
        final messages = chatService.messages;
        final isGroup = chatService.isGroupMode;

        // New chat, new keys: without this a long-lived page pins every past
        // chat's ChatMessage objects through the key map. No setState — the
        // map is not visual state, and this runs during build anyway.
        if (_bubbleKeysSessionId != chatService.currentSessionId) {
          _bubbleKeys.clear();
          _bubbleKeysSessionId = chatService.currentSessionId;
          // A live call is bound to the chat it started in — left up, the
          // mic would keep feeding the NEW chat. Dropping the flag unmounts
          // CallOverlay, whose dispose is the one call teardown (mic, TTS,
          // callMode). No setState: we are already inside this build.
          _isCallActive = false;
        }

        if (character == null && !isGroup) {
          // Scaffold, not a bare Center: without a Material ancestor the Text
          // renders in the red/yellow debug style on a black void — which is
          // exactly what users saw when a bug landed them here.
          return Scaffold(
            backgroundColor: AppColors.backgroundOf(context),
            body: Center(
              child: Text(
                'No character selected.',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.backgroundOf(context),
              appBar: _buildAppBar(context, chatService),
              body: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        // "Previously on…" welcome-back banner (Living Time
                        // §2). App-voice, dismissible, gated: enabled +
                        // over-threshold gap + a real session.
                        Builder(
                          builder: (context) {
                            // Subscribe so a settings toggle updates live;
                            // the gate itself lives once on ChatService.
                            Provider.of<StorageService>(context);
                            final phrase = chatService.absenceBannerPhrase;
                            final sid = chatService.currentSessionId;
                            if (phrase == null || sid == null) {
                              return const SizedBox.shrink();
                            }
                            return AbsenceRecapBanner(
                              sessionId: sid,
                              phrase: phrase,
                              recap: chatService.summary,
                            );
                          },
                        ),
                        Expanded(
                          child: _buildChatSurface(
                            context: context,
                            chatService: chatService,
                            character: character,
                            messages: messages,
                            isGroup: isGroup,
                          ),
                        ),
                        if (chatService.isGenerating)
                          GenerationStatusBar(chatService: chatService),
                        _buildInputArea(context, chatService),
                      ],
                    ),
                  ),
                  if (isGroup || character != null)
                    _buildResizableSidebar(
                      child: _buildRightSidebar(chatService),
                    ),
                ],
              ),
            ),
            ..._buildPageOverlays(
              context: context,
              chatService: chatService,
              character: character,
              isGroup: isGroup,
            ),
          ],
        );
      },
    );
  }

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`chat_page.*.dart`), which hold the sidebar/input/dialog builders but
  /// can't call a State's protected members directly. Same bridge pattern as
  /// settings_page.dart.
  void rebuildState(VoidCallback fn) => setState(fn);

  /// Per-character color palette for group chats (single source lives in
  /// sidebar_tokens.dart). Class static so sibling parts can call
  /// `_ChatPageState._groupCharacterColor` — an extension static is not
  /// that name.
  static Color _groupCharacterColor(int index) => groupCharacterColor(index);
}
