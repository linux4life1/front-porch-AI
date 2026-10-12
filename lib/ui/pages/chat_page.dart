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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/overlays/absence_recap_banner.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/pages/chat_page.image_consent.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input.dart';
import 'package:front_porch_ai/ui/pages/chat_page.scene_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.session_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_actions.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_bar.dart';
import 'package:front_porch_ai/ui/pages/chat_page.regen_shortcut.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart';
import 'package:front_porch_ai/ui/pages/chat_page.speakers.dart';
import 'package:front_porch_ai/ui/pages/chat_page_overlays.dart';
import 'package:front_porch_ai/ui/pages/chat_page_sidebar_host.dart';

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
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  /// Owns the transcript ListView so a Stack sibling toggle or a
  /// stream rebuild cannot dispose the scroll position (re-anchor
  /// at newest + scrollbar metrics reset).
  final GlobalKey _transcriptListKey = GlobalKey();

  /// Which rows the transcript mounts. The service list can be the
  /// whole archive; the screen stays on the latest lines.
  final TranscriptWindow _transcriptWindow = TranscriptWindow();

  late final FocusNode _chatFocusNode;

  /// Bubble keys owned by THIS page instance (never GlobalObjectKey(msg):
  /// two live chat routes would collide) plus the tap-to-jump flash.
  final ChatTranscriptAnchors _anchors = ChatTranscriptAnchors();
  double _sidebarWidth = SidebarTokens.widthFromEnvironment();
  late final ComposerHeight _composerHeight = ComposerHeight(update: setState);
  bool _isCallActive = false;
  late final PendingImageSlot _pendingImage = PendingImageSlot(
    update: setState,
  );
  late final ExternalImageConsent _imageConsent = ExternalImageConsent(
    onDecided: () => setState(() {}),
  );
  late final ChatSpeakerResolver _speakers = ChatSpeakerResolver(
    storage: () => Provider.of<StorageService>(context, listen: false),
    repository: () => Provider.of<CharacterRepository>(context, listen: false),
  );
  late final ChatScenePrompts _scenePrompts = ChatScenePrompts(
    coverFor: _speakers.coverFor,
  );
  TtsService? _ttsService;
  ChatService? _chatService;

  /// The cast participant whose per-character sidebar sections are shown.
  /// `null` = focus the host / first participant. Falls back automatically when
  /// the id is no longer in the active cast (e.g. after switching chats).
  String? _focusedParticipantId;

  /// Held so dispose removes the same handler initState added.
  late final KeyEventCallback _regenKeys = _onRegenShortcut;

  bool _onRegenShortcut(KeyEvent event) => handleChatRegenShortcut(event, this);

  @override
  void initState() {
    super.initState();
    _composerHeight.load();
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
        return KeyEventResult.ignored;
      },
    );
    HardwareKeyboard.instance.addHandler(_regenKeys);

    // Listen for TTS errors (e.g. ElevenLabs quota exceeded) and show a snackbar.
    final tts = Provider.of<TtsService>(context, listen: false);
    _ttsService = tts;
    tts.addListener(_onTtsChanged);

    // Listen for Chaos Mode auto-triggers
    final chat = Provider.of<ChatService>(context, listen: false);
    _chatService = chat;
    chat.addListener(_onChatServiceChanged);
    chat.chatScreenOpened();

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
    _scenePrompts.onChatChanged(
      context,
      chat,
      // A guest's background portrait finished — evict its stale cached
      // image so the new art replaces the initials avatar.
      onGuestAvatarReady: (path) {
        FileImage(_speakers.resolveCharImage(path)).evict().then((_) {
          if (mounted) setState(() {});
        });
      },
    );
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

  /// Repaint after an edit made in a dialog (editor, gallery, studio).
  void _refresh() {
    if (mounted) setState(() {});
  }

  void _sendCurrentMessage(ChatService chatService) => sendComposerMessage(
    chatService,
    controller: _controller,
    pendingImage: _pendingImage,
  );

  Future<void> _editCharacter(
    CharacterCard character, {
    bool ensureRelationshipVisible = false,
  }) async {
    await showEditCharacterDialog(
      context,
      character,
      ensureRelationshipVisible: ensureRelationshipVisible,
    );
    _refresh();
  }

  Future<void> _jumpToMessage(int position) => _anchors.jumpTo(
    position,
    messages: Provider.of<ChatService>(context, listen: false).messages,
    window: _transcriptWindow,
    controller: _scrollController,
    update: setState,
    isMounted: () => mounted,
  );

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_regenKeys);
    _chatService?.pauseDynamicResponses();
    _chatService?.chatScreenClosed();
    _ttsService?.removeListener(_onTtsChanged);
    _chatService?.removeListener(_onChatServiceChanged);
    _chatFocusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
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
        if (_anchors.syncSession(chatService.currentSessionId)) {
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
              appBar: ChatPageAppBar(
                chatService: chatService,
                coverFor: _speakers.coverFor,
                sidebarOpen: _sidebarWidth > 0,
                onToggleSidebar: () => setState(
                  () => _sidebarWidth = _sidebarWidth > 0
                      ? 0
                      : SidebarTokens.widthFromEnvironment(),
                ),
              ),
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
                          child: ChatSurface(
                            transcriptListKey: _transcriptListKey,
                            character: character,
                            messages: messages,
                            isGroup: isGroup,
                            controller: _controller,
                            focusNode: _chatFocusNode,
                            scrollController: _scrollController,
                            window: _transcriptWindow,
                            bgExistsCache: _bgExistsCache,
                            resolveSpeaker: _speakers.resolveSpeaker,
                            bubbleKeyFor: _anchors.keyFor,
                            jumpFlash: _anchors.jumpFlash,
                            externalImagesAllowed: _imageConsent.allowed,
                            onRequestImagePermission: () =>
                                _imageConsent.request(this.context),
                          ),
                        ),
                        if (chatService.isGenerating)
                          GenerationStatusBar(chatService: chatService),
                        _buildInputArea(chatService),
                      ],
                    ),
                  ),
                  if (isGroup || character != null)
                    ChatResizeSidebar(
                      width: _sidebarWidth,
                      onWidth: (w) => setState(() => _sidebarWidth = w),
                      child: _buildRightSidebar(chatService),
                    ),
                ],
              ),
            ),
            ...buildChatPageOverlays(
              context,
              chatService: chatService,
              character: character,
              isGroup: isGroup,
              callActive: _isCallActive,
              onEndCall: () => setState(() => _isCallActive = false),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputArea(ChatService chatService) {
    return ChatInputArea(
      chatService: chatService,
      controller: _controller,
      focusNode: _chatFocusNode,
      inputBar: ChatInputBar(
        chatService: chatService,
        pendingImageBytes: _pendingImage.bytes,
        pendingImageVisionOk: _pendingImage.visionOk,
        pendingImageBlindReason: _pendingImage.blindReason,
        onRemoveImage: _pendingImage.clear,
        onImage: (bytes) => _pendingImage.accept(context, bytes),
        onResizeReset: _composerHeight.resetDrag,
        onResize: _composerHeight.drag,
        menu: ChatManagementMenu(
          chatService: chatService,
          onImport: () => importChatPackageFile(context),
          onExport: () => exportChatFile(context),
          onConvertToGroup: () => showConvertToGroupPicker(
            context,
            chatService,
            coverFor: _speakers.coverFor,
          ),
        ),
        actions: ChatInputActionStrip(
          chatService: chatService,
          controller: _controller,
          focusNode: _chatFocusNode,
          minLines: _composerHeight.minLines,
          isPageMounted: () => mounted,
          onOpenImageStudio: () => showChatImageStudio(
            context,
            chatService,
            onAvatarsRefreshed: _refresh,
          ),
          onAttachImage: () => _pendingImage.pick(context),
          onStartCall: () => setState(() => _isCallActive = true),
          onSend: () => _sendCurrentMessage(chatService),
        ),
      ),
    );
  }

  Widget _buildRightSidebar(ChatService chatService) {
    return ChatRightSidebar(
      chatService: chatService,
      focusedParticipantId: _focusedParticipantId,
      onFocusParticipant: (id) => setState(() => _focusedParticipantId = id),
      sidebarWidth: _sidebarWidth,
      resolveCharImage: _speakers.resolveCharImage,
      draft: _controller,
      onJumpToMessage: _jumpToMessage,
      onEditCharacter: _editCharacter,
      onAvatarsChanged: _refresh,
    );
  }
}
