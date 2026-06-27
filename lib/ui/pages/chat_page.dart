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
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

// Barrel imports for high-frequency services, models, utils, and widgets
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

// Specific dialogs and modules not covered by the barrels (or intentionally direct)
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/character_avatars_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/edit_character_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/user_persona_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/context_viewer_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/group_objectives_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/scene_guest_detected_dialog.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/ui/dialogs/scene_guest_picker_dialog.dart';
// Old ImageGenDialog removed in Stage 3 (full from-scratch Image Studio).
// Studio launched below; see lib/ui/image_studio/ and _showImageGenDialog.
import 'package:front_porch_ai/ui/dialogs/kobold_log_dialog.dart';
// Stage 3 Image Studio (replaces old image_gen_dialog completely)
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final StyledTextController _controller = StyledTextController(
    preset: StyledTextPreset.chat,
  );
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _chatFocusNode;
  bool _autoScroll = true;
  double _sidebarWidth = 300;
  int _inputMinLines = 1;
  double _dragAccumulator = 0;
  bool _isCallActive = false;
  // Guards the Scene Guest detection popup so it cannot stack while open.
  bool _showingGuestDetection = false;
  bool _showingGuestPicker = false;
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

  /// Resolve the currently-focused participant from the unified cast, defaulting
  /// to the first participant (the host in a 1:1/NPC chat). Returns null only
  /// when no chat is loaded.
  ChatParticipant? _focusedParticipant(ChatService chat) {
    final cast = chat.cast;
    if (cast.isEmpty) return null;
    if (_focusedParticipantId != null) {
      for (final p in cast) {
        if (p.id == _focusedParticipantId) return p;
      }
    }
    return cast.first;
  }

  /// Resolve a character [imagePath] (basename or full path) to a [File].
  /// Always use this instead of [File(imagePath)] directly.
  File _resolveCharImage(String imagePath) {
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(imagePath);
  }

  /// Resolve the avatar + name color for a message's speaker from the unified
  /// [ChatService.cast], replacing the old group-vs-1:1/guest branches with one
  /// path. A non-host participant (group member or Scene Guest) gets its own
  /// avatar and a palette color keyed by its order among non-host speakers
  /// (preserving the previous per-mode coloring). The host gets its avatar and
  /// no color; an unresolved sender (a departed guest) gets the placeholder.
  (File?, Color?) _resolveSpeaker(ChatService chatService, ChatMessage msg) {
    if (msg.isUser) return (null, null);
    final cast = chatService.cast;
    final nonHost = cast.where((p) => !p.isHost).toList();

    ChatParticipant? speaker;
    for (final p in cast) {
      if ((msg.characterId != null && p.id == msg.characterId) ||
          p.name == msg.sender) {
        speaker = p;
        break;
      }
    }

    if (speaker != null && !speaker.isHost) {
      final img = speaker.card.imagePath != null
          ? _resolveCharImage(speaker.card.imagePath!)
          : null;
      final idx = nonHost.indexWhere((p) => p.id == speaker!.id);
      return (img, _groupCharacterColor(idx >= 0 ? idx : 0));
    }

    // Host message (or an unresolved/departed sender). Use the host avatar only
    // for an actual host message; an unknown non-host sender gets the
    // placeholder rather than the host's face under someone else's name.
    final host = cast.where((p) => p.isHost).firstOrNull;
    final isHostMsg =
        (speaker != null && speaker.isHost) ||
        (host != null &&
            (msg.sender == host.name ||
                (msg.characterId != null && msg.characterId == host.id)));
    final img = (isHostMsg && host?.card.imagePath != null)
        ? _resolveCharImage(host!.card.imagePath!)
        : null;
    return (img, null);
  }

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
          // Bare Enter → send message
          final chatService = Provider.of<ChatService>(context, listen: false);
          final text = _controller.text.trim();
          if (text.isNotEmpty && !chatService.isGenerating) {
            chatService.sendMessage(text);
            _controller.clear();
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
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
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => _chatService?.undoLastExit(),
            ),
          ),
        );
      });
    }
  }

  void _showChanceTimeOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChanceTimeOverlay(),
    );
  }

  Future<void> _showGuestDetectionDialog(ChatService chat) async {
    final detected = chat.pendingGuestDetection;
    if (detected == null || !mounted) {
      _showingGuestDetection = false;
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SceneGuestDetectedDialog(
        detected: detected,
        hostName: chat.activeCharacter?.name ?? 'your character',
      ),
    );
    _showingGuestDetection = false;
    if (accepted == true) {
      await chat.acceptDetectedGuest();
    } else {
      chat.dismissDetectedGuest();
    }
  }

  /// Show the `/join` character picker, then bring the chosen library character
  /// into the scene as a Scene Guest. The pending flag is always cleared so the
  /// picker never re-opens for the same request.
  Future<void> _showGuestPickerDialog(ChatService chat) async {
    final initial = chat.pendingGuestPickerFilter;
    if (initial == null || !mounted) {
      _showingGuestPicker = false;
      chat.dismissGuestPicker();
      return;
    }
    final full = chat.pendingGuestPickerFull;
    // Full picker: in a group it adds a member; in a 1:1 it converts to a group.
    // Lite picker: a Scene Guest inside a 1:1.
    final characters = full
        ? (chat.activeGroup != null
              ? chat.joinableGroupCharacters
              : chat.joinableGuestCharacters)
        : chat.joinableGuestCharacters;
    final selected = await showDialog<CharacterCard>(
      context: context,
      builder: (_) => SceneGuestPickerDialog(
        characters: characters,
        initialFilter: initial,
        resolveImage: _resolveCharImage,
      ),
    );
    _showingGuestPicker = false;
    chat.dismissGuestPicker();
    if (selected != null) {
      if (full) {
        await chat.joinFull(selected);
      } else {
        await chat.joinSceneGuest(selected);
      }
    }
  }

  /// Replacement for the removed Fork-to-Group wizard: pick a library character
  /// and bring them in as a FULL participant via the unified `joinFull` path,
  /// converting the current 1:1 into a group in place (with an organic entrance).
  /// Same picker as `/join`; only the join tier differs.
  Future<void> _showConvertToGroupPicker(ChatService chat) async {
    final selected = await showDialog<CharacterCard>(
      context: context,
      builder: (_) => SceneGuestPickerDialog(
        characters: chat.joinableGuestCharacters,
        initialFilter: '',
        resolveImage: _resolveCharImage,
      ),
    );
    if (selected != null) {
      await chat.joinFull(selected);
    }
  }

  void _onTtsChanged() {
    final tts = _ttsService;
    if (tts != null && tts.lastError != null && mounted) {
      final error = tts.lastError!;
      tts.clearError();
      // If a call is active, end it
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
      // ListView is reversed: position 0 = visual bottom (most recent)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, child) {
        final character = chatService.activeCharacter;
        final messages = chatService.messages;
        final isGroup = chatService.isGroupMode;

        if (character == null && !isGroup) {
          return const Center(child: Text('No character selected.'));
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
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final storageService =
                                  Provider.of<StorageService>(context);
                              final bgKey = storageService.chatBackground;
                              const bgAssets = {
                                'cyberpunk_bedroom':
                                    'assets/backgrounds/cyberpunk_bedroom.png',
                                'coffee_shop':
                                    'assets/backgrounds/coffee_shop.png',
                                'beach': 'assets/backgrounds/beach.png',
                                'futuristic_city':
                                    'assets/backgrounds/futuristic_city.png',
                                'edm_rave': 'assets/backgrounds/edm_rave.png',
                                'cozy_library':
                                    'assets/backgrounds/cozy_library.png',
                                'rainy_japan':
                                    'assets/backgrounds/rainy_japan.png',
                                'space_station':
                                    'assets/backgrounds/space_station.png',
                                'enchanted_forest':
                                    'assets/backgrounds/enchanted_forest.png',
                                'anime_cherry_blossom':
                                    'assets/backgrounds/anime_cherry_blossom.png',
                                'anime_rooftop':
                                    'assets/backgrounds/anime_rooftop.png',
                                'anime_rooftop_sunset':
                                    'assets/backgrounds/anime_rooftop_sunset.png',
                                'cherry_blossom':
                                    'assets/backgrounds/cherry_blossom.png',
                                'beach_waves':
                                    'assets/backgrounds/beach_waves.png',
                                'waifu_gaming_room':
                                    'assets/backgrounds/waifu_gaming_room.png',
                                'waifu_beach_bar':
                                    'assets/backgrounds/waifu_beach_bar.png',
                                'waifu_garden':
                                    'assets/backgrounds/waifu_garden.png',
                                'waifu_neon':
                                    'assets/backgrounds/waifu_neon.png',
                                'waifu_beach':
                                    'assets/backgrounds/waifu_beach.png',
                              };
                              final bgPath = bgAssets[bgKey];
                              final bgPathExists = bgPath != null;

                              // Check for matching custom background
                              Map<String, String>? customEntry;
                              if (!bgPathExists) {
                                try {
                                  customEntry = storageService.customBackgrounds
                                      .firstWhere((e) => e['id'] == bgKey);
                                } catch (_) {}
                              }
                              final hasCustomBg =
                                  customEntry != null &&
                                  File(customEntry['filePath']!).existsSync();

                              return Stack(
                                children: [
                                  if (bgPath != null) ...[
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Image.asset(
                                          bgPath,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ],
                                  // Expression background sprite
                                  Consumer<ChatService>(
                                    builder: (context, chat, _) {
                                      final storage =
                                          Provider.of<StorageService>(
                                            context,
                                            listen: false,
                                          );
                                      final displayMode =
                                          storage.expressionDisplayMode;
                                      final isEnabled =
                                          storage.expressionEnabled;
                                      if (!isEnabled ||
                                          displayMode == 'sidebar' ||
                                          chat.isEvaluatingRealism) {
                                        return const SizedBox.shrink();
                                      }
                                      final char = character;
                                      if (char == null ||
                                          char.avatarImages == null ||
                                          char.avatarImages!.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      final avatar = chat
                                          .resolveExpressionAvatar(
                                            char,
                                            rerollIfSame:
                                                storage.expressionRerollSame,
                                          );
                                      if (avatar == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final avatarDir = storage
                                          .characterAvatarDir(char.name);
                                      final avatarFile = File(
                                        '${avatarDir.path}/${avatar.filename}',
                                      );
                                      return Positioned.fill(
                                        child: IgnorePointer(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            child: Stack(
                                              key: ValueKey(
                                                'expr_bg_${avatar.id}',
                                              ),
                                              fit: StackFit.expand,
                                              children: [
                                                Image.file(
                                                  avatarFile,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      const SizedBox.shrink(),
                                                ),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.85,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (bgPath != null)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!bgPathExists && hasCustomBg) ...[
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            image: DecorationImage(
                                              image: FileImage(
                                                File(customEntry['filePath']!),
                                              ),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  ListView.builder(
                                    controller: _scrollController,
                                    reverse: true,
                                    padding: const EdgeInsets.all(20),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      // Reverse index so newest messages are at the top of the reversed list (visual bottom)
                                      final reversedIndex =
                                          messages.length - 1 - index;
                                      final msg = messages[reversedIndex];
                                      // Resolve the speaker's avatar + name color
                                      // from the unified cast (host, group member,
                                      // or Scene Guest) — one path for all modes.
                                      final (senderImage, senderColor) =
                                          _resolveSpeaker(chatService, msg);
                                      return MessageBubble(
                                        key: ObjectKey(msg),
                                        message: msg,
                                        characterImage: senderImage,
                                        index: reversedIndex,
                                        senderColor: senderColor,
                                        externalImagesAllowed:
                                            _externalImagesAllowed,
                                        onRequestImagePermission: () async {
                                          if (_externalImagesAllowed != null) {
                                            return _externalImagesAllowed!;
                                          }
                                          // Check persisted consent first
                                          if (!_imageConsentChecked) {
                                            _imageConsentChecked = true;
                                            final prefs =
                                                await SharedPreferences.getInstance();
                                            final consented =
                                                prefs.getStringList(
                                                  'image_consent_characters',
                                                ) ??
                                                [];
                                            final charName =
                                                Provider.of<ChatService>(
                                                  context,
                                                  listen: false,
                                                ).activeCharacter?.name ??
                                                '';
                                            if (charName.isNotEmpty &&
                                                consented.contains(charName)) {
                                              if (mounted) {
                                                setState(
                                                  () => _externalImagesAllowed =
                                                      true,
                                                );
                                              }
                                              return true;
                                            }
                                          }
                                          final result = await showDialog<bool>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(
                                                0xFF1E293B,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              icon: const Icon(
                                                Icons.shield_outlined,
                                                color: Colors.orangeAccent,
                                                size: 36,
                                              ),
                                              title: const Text(
                                                'External Image Detected',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'This message contains images hosted on an external server. '
                                                    'Loading them carries security risks:',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                      height: 1.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  _buildRiskItem(
                                                    Icons.visibility,
                                                    'Your IP address will be exposed to the image host',
                                                  ),
                                                  _buildRiskItem(
                                                    Icons.bug_report,
                                                    'Maliciously crafted images could potentially exploit vulnerabilities',
                                                  ),
                                                  _buildRiskItem(
                                                    Icons.track_changes,
                                                    'The URL may be used for tracking',
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'The source has not been verified as safe.',
                                                    style: TextStyle(
                                                      color: Colors.orangeAccent
                                                          .withValues(
                                                            alpha: 0.8,
                                                          ),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text(
                                                    'Block Images',
                                                    style: TextStyle(
                                                      color: Colors.white54,
                                                    ),
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.orangeAccent,
                                                        foregroundColor:
                                                            Colors.black87,
                                                      ),
                                                  child: const Text(
                                                    'Accept Risk & Load',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          final allowed = result ?? false;
                                          if (allowed) {
                                            // Persist consent for this character
                                            final prefs =
                                                await SharedPreferences.getInstance();
                                            final charName =
                                                Provider.of<ChatService>(
                                                  context,
                                                  listen: false,
                                                ).activeCharacter?.name ??
                                                '';
                                            if (charName.isNotEmpty) {
                                              final consented =
                                                  prefs.getStringList(
                                                    'image_consent_characters',
                                                  ) ??
                                                  [];
                                              if (!consented.contains(
                                                charName,
                                              )) {
                                                consented.add(charName);
                                                await prefs.setStringList(
                                                  'image_consent_characters',
                                                  consented,
                                                );
                                              }
                                            }
                                          }
                                          if (mounted) {
                                            setState(
                                              () => _externalImagesAllowed =
                                                  allowed,
                                            );
                                          }
                                          return allowed;
                                        },
                                        character: isGroup && !msg.isUser
                                            ? chatService.groupCharacters
                                                  .where(
                                                    (c) => c.name == msg.sender,
                                                  )
                                                  .firstOrNull
                                            : character,
                                        chatService: chatService,
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
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
            if (chatService.isLoadingSession)
              Container(
                color: AppColors.resolve(
                  context,
                  Colors.black54,
                  Colors.black.withValues(alpha: 0.25),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            // Voice call overlay
            if (_isCallActive && character != null && !isGroup)
              Positioned.fill(
                child: CallOverlay(
                  character: character,
                  onEndCall: () {
                    setState(() => _isCallActive = false);
                  },
                ),
              ),
            // Realism Engine processing overlays
            if (chatService.isEvaluatingRealism ||
                chatService.isProcessingGreeting ||
                chatService.isVerifyingRealism)
              RealismProcessingOverlay(
                chatService: chatService,
                isGreeting: chatService.isProcessingGreeting,
              ),
            // Objective completion check overlay (only when realism isn't already showing)
            if (chatService.isCheckingCompletion &&
                !chatService.isEvaluatingRealism &&
                !chatService.isProcessingGreeting)
              ObjectiveCheckOverlay(chatService: chatService),
            // ONNX model download progress overlay
            Positioned.fill(
              child: Consumer<ExpressionClassifierService>(
                builder: (context, classifier, _) {
                  if (!classifier.isDownloading) return const SizedBox.shrink();
                  return OnnxDownloadOverlay(classifierService: classifier);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Single AppBar for every chat. Driven by the unified [ChatService.cast]:
  /// a cast of one renders the classic single-character header (avatar + name +
  /// description); a cast of two or more renders stacked avatars (with emotion
  /// rings when group realism is active) + a "N characters" subtitle. This is
  /// the same header whether the extra speakers are full group members or Scene
  /// Guests, so a 1:1 that gains a guest visually becomes a multi-speaker chat.
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatService chatService,
  ) {
    final cast = chatService.cast;
    final group = chatService.activeGroup;
    final isMulti = cast.length > 1;

    final Widget avatars;
    if (!isMulti) {
      final card = cast.isNotEmpty ? cast.first.card : null;
      avatars = CircleAvatar(
        backgroundImage: card?.imagePath != null
            ? FileImage(_resolveCharImage(card!.imagePath!))
            : null,
        onBackgroundImageError: card?.imagePath != null ? (_, _) {} : null,
        child: card?.imagePath == null ? const Icon(Icons.person) : null,
      );
    } else {
      final shown = cast.length.clamp(0, 4);
      avatars = SizedBox(
        width: 24.0 + (shown - 1) * 16,
        height: 32,
        child: Stack(
          children: [
            for (int i = 0; i < shown; i++)
              Positioned(
                left: i * 16.0,
                child: Builder(
                  builder: (_) {
                    final card = cast[i].card;
                    final emo = chatService.isGroupRealismActive
                        ? chatService.getEmotionForGroupCharacter(card)
                        : null;
                    final fix = chatService.isGroupRealismActive
                        ? chatService.getFixationForGroupCharacter(card)
                        : null;
                    final tooltip = emo == null
                        ? card.name
                        : (fix != null && fix.isNotEmpty
                              ? '${card.name} • $emo\nFixated: $fix'
                              : '${card.name} • $emo');
                    return Tooltip(
                      message: tooltip,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: chatService.isGroupRealismActive
                              ? Border.all(
                                  color: EmotionLabels.ringColor(emo),
                                  width: 2.0,
                                )
                              : null,
                        ),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: _groupCharacterColor(i),
                          backgroundImage: card.imagePath != null
                              ? FileImage(_resolveCharImage(card.imagePath!))
                              : null,
                          child: card.imagePath == null
                              ? Text(
                                  card.name.isNotEmpty ? card.name[0] : '?',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }

    final title = group?.name ?? (cast.isNotEmpty ? cast.first.name : '');
    final String? subtitle;
    if (isMulti) {
      subtitle = group != null
          ? '${cast.length} characters • ${group.turnOrder.name}'
          : '${cast.length} characters';
    } else {
      final desc = cast.isNotEmpty ? cast.first.card.description : '';
      subtitle = desc.isEmpty
          ? null
          : (desc.length > 30 ? '${desc.substring(0, 30)}...' : desc);
    }

    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          avatars,
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _sidebarWidth > 0 ? Icons.last_page : Icons.first_page,
            color: AppColors.iconSecondary(context),
          ),
          tooltip: 'Toggle Sidebar',
          onPressed: () =>
              setState(() => _sidebarWidth = _sidebarWidth > 0 ? 0 : 300),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Per-character color palette for group chats.
  static Color _groupCharacterColor(int index) {
    const colors = [
      Color(0xFF8B5CF6), // Purple
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber
      Color(0xFFEF4444), // Red
      Color(0xFF3B82F6), // Blue
      Color(0xFFEC4899), // Pink
      Color(0xFF14B8A6), // Teal
      Color(0xFFF97316), // Orange
    ];
    return colors[index % colors.length];
  }

  void _showGroupSettingsDialog(ChatService chatService) {
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) =>
          GroupSettingsDialog(chatService: chatService, groupRepo: groupRepo),
    );
  }

  Future<void> _importChat() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonData = await file.readAsString();

      if (!mounted) return;

      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.importFromSillyTavern(jsonData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat imported successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          title: const Text('Import Failed'),
          content: Text('Error importing chat: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _exportChat() async {
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final jsonData = chatService.exportToSillyTavern();

      if (jsonData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No chat to export'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final characterName = chatService.activeCharacter?.name ?? 'chat';
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = '${characterName}_$timestamp.json';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Chat',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (path == null) return;

      final file = File(path);
      await file.writeAsString(jsonData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat exported successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          title: const Text('Export Failed'),
          content: Text('Error exporting chat: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showEvolutionDialog(
    BuildContext context,
    ChatService chat, {
    CharacterCard? focusedCard,
  }) {
    // Evolve/view the FOCUSED participant (sidebar selection) — not the active /
    // next-queued speaker, which is why a group used to show the wrong character.
    // In a group the dialog gets a top member-picker so any cast member can be
    // viewed/evolved manually. Everything is targeted per-member.
    final members = chat.cast.map((p) => p.card).toList();
    final CharacterCard? initial =
        focusedCard ??
        chat.activeCharacter ??
        (members.isNotEmpty ? members.first : null);
    if (initial == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        CharacterCard selected = initial;
        final personalityController = TextEditingController(
          text: chat.getEvolvedPersonalityFor(selected) ?? selected.personality,
        );
        final scenarioController = TextEditingController(
          text: chat.getEvolvedScenarioFor(selected) ?? selected.scenario,
        );

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final count = chat.getEvolutionCountFor(selected);

            void switchTo(CharacterCard c) {
              selected = c;
              personalityController.text =
                  chat.getEvolvedPersonalityFor(c) ?? c.personality;
              scenarioController.text =
                  chat.getEvolvedScenarioFor(c) ?? c.scenario;
              setLocal(() {});
            }

            return AlertDialog(
              backgroundColor: AppColors.surfaceOf(context),
              title: Row(
                children: [
                  const Icon(
                    Icons.psychology_alt,
                    size: 18,
                    color: Colors.tealAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${selected.name} — Evolution',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Member picker (group only) — pick who to view / evolve.
                      if (members.length > 1) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: members.map((m) {
                            final isSel = m.name == selected.name;
                            return ChoiceChip(
                              label: Text(
                                m.name,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: isSel,
                              onSelected: (_) {
                                if (!isSel) switchTo(m);
                              },
                              selectedColor: Colors.tealAccent.shade700,
                              labelStyle: TextStyle(
                                color: isSel ? Colors.black : Colors.white70,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        count > 0
                            ? 'Evolved $count time${count > 1 ? "s" : ""}'
                            : 'Not yet evolved — personality will evolve as you chat',
                        style: TextStyle(
                          fontSize: 11,
                          color: count > 0
                              ? Colors.tealAccent
                              : Colors.white38,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Evolution settings (global). Hosted here so they are
                      // reachable in a GROUP too (the memory-sidebar copy isn't
                      // shown in groups). Frequency now counts each character's
                      // OWN turns, so adding members doesn't speed everyone up.
                      Builder(
                        builder: (ctx2) {
                          final storage = Provider.of<StorageService>(
                            ctx2,
                            listen: false,
                          );
                          final enabled = storage.characterEvolutionEnabled;
                          final iv = storage.evolutionInterval.clamp(10, 50);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Character Evolution',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.tealAccent,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 20,
                                    child: Switch(
                                      value: enabled,
                                      activeThumbColor: Colors.tealAccent,
                                      onChanged: (val) {
                                        storage.setCharacterEvolutionEnabled(
                                          val,
                                        );
                                        setLocal(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (enabled) ...[
                                Text(
                                  'Evolve every $iv turns'
                                  '${members.length > 1 ? ' (per character)' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                                Slider(
                                  value: iv.toDouble(),
                                  min: 10,
                                  max: 50,
                                  divisions: 8,
                                  label: '$iv',
                                  activeColor: Colors.tealAccent,
                                  onChanged: (v) {
                                    storage.setEvolutionInterval(v.round());
                                    setLocal(() {});
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Original personality (read-only)
                      const Text(
                        'Original Personality',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        constraints: const BoxConstraints(maxHeight: 80),
                        child: SingleChildScrollView(
                          child: Text(
                            selected.personality,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Evolved personality (editable)
                      const Text(
                        'Evolved Personality',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppTextField(
                        controller: personalityController,
                        maxLines: 4,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF111827),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Original scenario (read-only)
                      const Text(
                        'Original Scenario',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        constraints: const BoxConstraints(maxHeight: 80),
                        child: SingleChildScrollView(
                          child: Text(
                            selected.scenario,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Evolved scenario (editable)
                      const Text(
                        'Evolved Scenario',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppTextField(
                        controller: scenarioController,
                        maxLines: 4,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF111827),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                if (count > 0)
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showResetEvolutionConfirmSidebar(
                        context,
                        chat,
                        target: selected,
                      );
                    },
                    child: const Text(
                      'Reset',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                TextButton(
                  onPressed: chat.isEvolvingCharacter
                      ? null
                      : () async {
                          final target = selected;
                          final ok = await chat.triggerEvolutionNow(
                            target: target,
                          );
                          Navigator.of(ctx).pop();
                          if (ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${target.name} evolved!'),
                                backgroundColor: Colors.teal,
                              ),
                            );
                          }
                        },
                  child: Text(
                    chat.isEvolvingCharacter ? 'Evolving...' : 'Evolve Now',
                    style: const TextStyle(color: Colors.tealAccent),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    chat.updateEvolvedPersonality(
                      personalityController.text,
                      target: selected,
                    );
                    chat.updateEvolvedScenario(
                      scenarioController.text,
                      target: selected,
                    );
                    Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade700,
                  ),
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showResetEvolutionConfirmSidebar(
    BuildContext context,
    ChatService chat, {
    CharacterCard? target,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(
          target != null
              ? 'Reset ${target.name}\'s Evolution?'
              : 'Reset Character Evolution?',
        ),
        content: const Text(
          'This will reset the character\'s personality and scenario back to the original card values. '
          'The evolution count will also reset to 0. This cannot be undone.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              chat.resetCharacterEvolution(target: target);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolveNowButton(BuildContext context, ChatService chat) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _runEvolutionWithDialog(context, chat),
        icon: const Icon(
          Icons.auto_fix_high,
          size: 14,
          color: Colors.tealAccent,
        ),
        label: const Text(
          'Evolve Now',
          style: TextStyle(fontSize: 11, color: Colors.tealAccent),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.tealAccent),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
    );
  }

  void _runEvolutionWithDialog(BuildContext context, ChatService chat) {
    // Track the count before evolution to detect success
    final countBefore = chat.characterEvolutionCount;

    // Show the progress dialog immediately
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer<ChatService>(
        builder: (context, chat, _) {
          final isEvolving = chat.isEvolvingCharacter;
          final status = chat.evolutionStatus;
          final error = chat.evolutionError;
          final count = chat.characterEvolutionCount;

          // Evolution failed — show error
          if (!isEvolving && error.isNotEmpty) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceOf(context),
              title: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Evolution Failed',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Text(
                  error,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  child: const Text('Close'),
                ),
              ],
            );
          }

          // Evolution finished successfully — show results
          if (!isEvolving && status.isEmpty && count > countBefore) {
            final evolvedP = chat.getEffectivePersonality;
            final evolvedS = chat.getEffectiveScenario;
            return AlertDialog(
              backgroundColor: AppColors.surfaceOf(context),
              title: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 20,
                    color: AppColors.resolve(
                      context,
                      Colors.tealAccent,
                      Colors.teal.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Evolution Complete!',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Evolved $count time${count > 1 ? "s" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.resolve(
                            context,
                            Colors.tealAccent,
                            Colors.teal.shade700,
                          ),
                        ),
                      ),
                      if (evolvedP != null && evolvedP.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Evolved Personality',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.resolve(
                              context,
                              Colors.tealAccent,
                              Colors.teal.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.resolve(
                                context,
                                Colors.tealAccent.withValues(alpha: 0.3),
                                Colors.teal.shade200.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Text(
                              evolvedP,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (evolvedS != null && evolvedS.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Evolved Scenario',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.resolve(
                              context,
                              Colors.tealAccent,
                              Colors.teal.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.resolve(
                                context,
                                Colors.tealAccent.withValues(alpha: 0.3),
                                Colors.teal.shade200.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Text(
                              evolvedS,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade700,
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          }

          // Evolution in progress — show spinner + status
          return AlertDialog(
            backgroundColor: AppColors.surfaceOf(context),
            title: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.tealAccent,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Evolving Character...',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.isNotEmpty ? status : 'Starting...',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  color: Colors.tealAccent,
                  backgroundColor: Color(0xFF374151),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The LLM is analyzing the conversation history and rewriting the character\'s personality and scenario.',
                  style: TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Trigger the evolution
    chat.triggerEvolutionNow().then((ok) {
      if (!ok && mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot evolve: need an active LLM and some chat history',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  void _showClearChatConfirmation(BuildContext context) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('New Chat'),
        content: const Text(
          'This will clear the current conversation and start fresh. This can\'t be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              chatService.startNewChat();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text(
              'New Chat',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    var sessions = await chatService.getSessions();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          title: const Text('Chat History'),
          content: SizedBox(
            width: 420,
            height: 350,
            child: sessions.isEmpty
                ? const Center(child: Text('No previous chats found.'))
                : ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final s = sessions[index];
                      final date = s['date'] as DateTime;
                      final dateStr =
                          '${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute.toString().padLeft(2, "0")}';
                      final isCurrent = s['id'] == chatService.currentSessionId;
                      final isBranch = s['parent_session'] != null;
                      final description = s['session_description'] as String?;

                      return ListTile(
                        leading: isBranch
                            ? const Icon(
                                Icons.call_split,
                                size: 18,
                                color: Colors.blueAccent,
                              )
                            : null,
                        title: Text(
                          s['preview'],
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                            if (description != null && description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  description,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white38,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (isBranch)
                              Text(
                                '↳ Branched at message #${(s['fork_index'] ?? 0) + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueAccent,
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white38,
                              ),
                              tooltip: 'Edit name & description',
                              onPressed: () => _showEditSessionDialog(
                                context,
                                chatService,
                                s,
                                onSaved: () async {
                                  sessions = await chatService.getSessions();
                                  setDialogState(() {});
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Delete chat',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.surfaceOf(
                                      context,
                                    ),
                                    title: const Text('Delete Chat?'),
                                    content: Text(
                                      'This will permanently delete this chat and all its messages.\n\n"${s['preview']}"',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await chatService.deleteSession(s['id']);
                                  if (isCurrent) {
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  } else {
                                    sessions = await chatService.getSessions();
                                    setDialogState(() {});
                                  }
                                }
                              },
                            ),
                            if (isCurrent)
                              const Padding(
                                padding: EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.greenAccent,
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          chatService.loadSession(s['id']);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSessionDialog(
    BuildContext context,
    ChatService chatService,
    Map<String, dynamic> session, {
    required VoidCallback onSaved,
  }) {
    final nameController = TextEditingController(
      text: session['session_name'] ?? '',
    );
    final descController = TextEditingController(
      text: session['session_description'] ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Edit Chat Session'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Session Name',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'e.g. "Adventure in the forest"',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF374151),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'Optional — appears under the timestamp',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF374151),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await chatService.renameSession(
                session['id'],
                nameController.text.trim(),
              );
              await chatService.updateSessionDescription(
                session['id'],
                descController.text.trim(),
              );
              Navigator.of(ctx).pop();
              onSaved();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showImageGenDialog(
    BuildContext context,
    ChatService chatService,
  ) async {
    // Note: mode param removed (user spec: types are buttons inside Image Studio now; launcher is neutral).
    // We launch with customPrompt as safe neutral starter; user taps a type button inside immediately.
    // Special pre-dialog for "custom" removed (typing in the main prompt box + Craft covers it cleanly, no boiler).
    // onAccept captured here is for legacy direct callers; studio _accept now uses _activeMode for side effects
    // where possible (bg set, user avatar) via providers. Portrait set (needs full Character) kept for launch-time
    // wiring if provided. Keep thin launcher + sync comments with studio show/ctor/_active, service, builder, ctx.

    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final character = chatService.activeCharacter;

    // Get the active LLM service for smart prompt generation
    final llmService = llmProvider.activeService.isReady
        ? llmProvider.activeService
        : null;

    // Get world info if available
    String? worldInfo;
    try {
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final worlds = worldRepo.worlds;
      if (worlds.isNotEmpty) {
        worldInfo = worlds.first.description;
      }
    } catch (_) {}

    // Get recent messages for scene visualization
    List<String>? recentMessages;
    String? lastMessage;
    final messages = chatService.messages;

    String _cleanImageSourceText(String text) {
      if (text.isEmpty) return text;
      // Remove think blocks (completed + unclosed tails) and "Auto-imported from character card: ..." lines
      // so polluted card import junk and internal <think> never reach the Image Studio context, pills, or prompts.
      // This directly addresses the original "Aerin" / "</think>" / raw thoughts garbage leaking into visualize.
      text = text.replaceAll(
        RegExp(r'<\/?think>.*?<\/think>', dotAll: true, caseSensitive: false),
        '',
      );
      final idx = text.toLowerCase().lastIndexOf('<think>');
      if (idx != -1) text = text.substring(0, idx);
      text = text.replaceAll(
        RegExp(r'<\/?think[^>]*>', caseSensitive: false),
        '',
      );
      text = text.replaceAll(
        RegExp(
          r'Auto-imported from character card:.*?(?:\n|$)',
          caseSensitive: false,
        ),
        '',
      );
      text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      return text;
    }

    if (messages.isNotEmpty) {
      // User spec: collect more (12) so the visualize slider (1-10) in studio has headroom. The N chosen
      // is stripped of <think> in builder (simple, pre-generated msgs). Keep collection + studio slider + builder
      // recent limit + service ctx + ImageGenContext in sync. (1:1/group via same public surface + speaker preference).
      recentMessages = messages.reversed
          .take(12)
          .map((m) => m.displayText)
          .where((m) => m.isNotEmpty)
          .map(_cleanImageSourceText)
          .where((m) => m.isNotEmpty)
          .toList()
          .reversed
          .toList();

      // For visualizeScene (N=1 is the spiritual successor to the removed "Message Illustration" / fromLastMessage
      // mode), prefer the most recent *AI/non-user* turn's displayText as a strong narrative anchor.
      // This ensures the visualization is based on the character's described action/scene/pose rather than
      // the user's just-typed input (common when studio is opened immediately after user send).
      // In normal 1:1 the absolute last is usually the AI response. Safe fallback to absolute last.
      // Mirrors the currentSpeakerId preference (below) for group under non-observer. Keep in sync with
      // ModeInfoCard, builder visualize handling, studio _ctx, service thin, and tests.
      final userName = personaService.persona.name;
      for (final m in messages.reversed) {
        final txt = _cleanImageSourceText(m.displayText);
        if (txt.isNotEmpty && m.sender != userName) {
          lastMessage = txt;
          break;
        }
      }
      lastMessage ??= _cleanImageSourceText(messages.last.displayText);
    }

    // Stage 4: collect richer context from public ChatService surface for ImageStudio (expression from Realism/ExpressionClassifier,
    // timeOfDay from TimeService, group non-observer + speaker id for correct char targeting in fromLast/visualize under impersonation).
    // Keep collection + ImageStudio.show call + studio ctor/_ctx + service thins/_build + builder use "in sync".
    // currentSpeakerId prefers the *most recent AI (non-user) sender* for illustration modes (fromLast/visualize) when in group
    // (so "Focus on X" targets the character whose narrative is being illustrated, not the user if last turn was user).
    // Iterate reversed; fall back safely. Qualifies 1:1 vs group dispatch (flag + speaker only relevant under non-obs group).
    // No private _ methods touched in chat god; only public getters (currentExpressionLabel, timeService, isGroupMode, observerMode).
    // Keep blocks in sync with ImageGenContext ctor, service _buildPromptContext (all 3 sites), studio _ctx + _craft, builder
    // consumption (static + _generateSmartWith), workspace pills, and builder_test roundtrips/edges. (incomplete zeroing of
    // secondary config on group/0-session/new-chat now complete — N/A for per-invocation stateless snapshot; see both
    // startNew paths + setActiveGroup + load in chat_service for precedent).
    final currentExpression = chatService.currentExpressionLabel;
    final timeOfDay = chatService.timeService.timeOfDay;
    final bool isGroupNonObserver =
        chatService.isGroupMode && !chatService.observerMode;
    String? currentSpeakerId;
    if (isGroupNonObserver && messages.isNotEmpty) {
      final userName = personaService.persona.name; // already obtained above
      for (final m in messages.reversed) {
        final s = m.sender;
        if (s.isNotEmpty && s != userName) {
          currentSpeakerId = s;
          break;
        }
      }
    }
    // lightingHint intentionally omitted at launch (timeOfDay primary from chatService.timeService; richer lightingHint
    // support available via ctx for future callers). Stage 4 wiring complete for all declared fields
    // (currentExpression/timeOfDay/isGroupNonObserver/currentSpeakerId + optional lightingHint); see _showImageGenDialog
    // + ImageGenContext + service thins + builder.

    if (!context.mounted) return;

    // onAccept: for legacy direct launchers. For the new button-inside flow the studio _accept decides
    // crop/saveAvatar vs bg set vs user avatar update based on the *chosen* _activeMode at accept time
    // (using providers for storage/persona; portrait char set requires full object so limited here).
    // Pass null for the neutral launch (custom starter); sides for special types work via internal studio logic or save.
    void Function(String path)? onAccept;

    // Stage 3: launch the new from-scratch Image Studio (pre-gen editable workspace first-class).
    // User spec: neutral open (custom as starter), types via internal buttons (popup removed), no pregen boilerplate,
    // visualize uses slider N + think strip on craft, user box text + persona + char visual (no pers) + style to LLM.
    // Re-uses collected raw context. No new private methods added to this surface (thin).
    await ImageStudio.show(
      context,
      mode: ImageGenMode.customPrompt,
      customPrompt: null,
      lastMessage: lastMessage,
      characterName: character?.name,
      characterDescription: character?.description,
      characterPersonality: character?.personality,
      scenario: _cleanImageSourceText(character?.scenario ?? ''),
      worldInfo: _cleanImageSourceText(worldInfo ?? ''),
      personaName: personaService.persona.name,
      personaText: personaService.persona.persona,
      recentMessages: recentMessages,
      llmService: llmService,
      onAccept: onAccept,
      // Stage 4: pass collected richer fields (keep launch site + studio show/ctor/_ctx + service thins + builder + workspace pills in sync).
      currentExpression: currentExpression,
      timeOfDay: timeOfDay,
      lightingHint: null,
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: currentSpeakerId,
    );
  }

  /// The "type /" command list shown above the input. Tapping a row fills the
  /// input with that command (trailing space) and keeps focus so the user can
  /// continue typing arguments.
  Widget _buildCommandHelper(
    BuildContext context,
    List<SlashCommandInfo> matches,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: matches.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 1,
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
        itemBuilder: (context, i) {
          final c = matches[i];
          return InkWell(
            onTap: () {
              final text = '/${c.command} ';
              _controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              _chatFocusNode.requestFocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(
                      c.example,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: AppColors.relationshipAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ChatService chatService) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Trust repair warning banner ──────────────────────────────────
        // Shown when a severe trust drop has armed the one-shot repair window.
        // Disappears automatically after the user sends their next message.
        if (chatService.pendingTrustRepair)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.resolve(
              context,
              const Color(0xFF7C2D12),
              const Color(0xFFFEF3C7),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trust is on the line — your next message is your only chance to explain yourself.',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Scene Guest activity banner ──────────────────────────────────
        // One inline status line for the /create · /join · detection flow that
        // updates in place (Creating → Entering → ✓ joined) and auto-clears.
        // Replaces the old per-step 'System' chat messages so the scene stays
        // clean and nothing is persisted into history.
        if (chatService.guestActivityStatus != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: chatService.guestActivityIsError
                ? AppColors.resolve(
                    context,
                    const Color(0xFF7C2D12),
                    const Color(0xFFFEF3C7),
                  )
                : AppColors.surfaceContainerOf(context),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: chatService.isGuestBusy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.relationshipAccent,
                        )
                      : Icon(
                          chatService.guestActivityIsError
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline,
                          size: 14,
                          color: chatService.guestActivityIsError
                              ? Colors.orangeAccent
                              : AppColors.relationshipAccent,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chatService.guestActivityStatus!,
                    style: TextStyle(
                      color: chatService.guestActivityIsError
                          ? Colors.orangeAccent
                          : AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Slash-command helper ─────────────────────────────────────────
        // When the input is a command-in-progress ("/", "/cr", …) show the
        // matching commands above the bar; tap one to fill it in. Rendered in
        // the input column (no overlay), and scoped to the controller via a
        // ValueListenableBuilder so only this panel rebuilds per keystroke.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final m = RegExp(r'^/(\w*)$').firstMatch(value.text);
            if (m == null) return const SizedBox.shrink();
            final prefix = m.group(1)!.toLowerCase();
            final matches = ChatCommandHandler.commands
                .where((c) => c.command.startsWith(prefix))
                .toList();
            if (matches.isEmpty) return const SizedBox.shrink();
            return _buildCommandHelper(context, matches);
          },
        ),

        // ── Input bar ────────────────────────────────────────────────────
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resize handle — drag up/down to adjust input height
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onVerticalDragStart: (_) => _dragAccumulator = 0,
                onVerticalDragUpdate: (details) =>
                    _handleInputResize(details.delta.dy),
                onVerticalDragEnd: (_) => _dragAccumulator = 0,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      height: 3,
                      width: 50,
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          Colors.white38,
                          Colors.black38,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                border: Border(
                  top: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,

                children: [
                  // Persona Switcher
                  Consumer<UserPersonaService>(
                    builder: (context, personaService, _) {
                      final persona = personaService.persona;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 6),
                        child: GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => const UserPersonaDialog(),
                          ),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.resolve(
                              context,
                              Colors.white24,
                              Colors.black12,
                            ),
                            backgroundImage: persona.avatarPath != null
                                ? FileImage(File(persona.avatarPath!))
                                : null,
                            child: persona.avatarPath == null
                                ? Icon(
                                    Icons.person,
                                    size: 18,
                                    color: AppColors.iconSecondary(context),
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),

                  // Chat Management Menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.folder_open,
                      color: AppColors.iconSecondary(context),
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Chat Management',
                    onSelected: (value) {
                      if (value == 'new_chat') {
                        _showClearChatConfirmation(context);
                      } else if (value == 'history') {
                        _showHistoryDialog(context);
                      } else if (value == 'import') {
                        _importChat();
                      } else if (value == 'export') {
                        _exportChat();
                      } else if (value == 'evolution') {
                        _showEvolutionDialog(
                          context,
                          chatService,
                          focusedCard: _focusedParticipant(chatService)?.card,
                        );
                      } else if (value == 'context') {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              ContextViewerDialog(chatService: chatService),
                        );
                      } else if (value == 'fork_group') {
                        _showConvertToGroupPicker(chatService);
                      } else if (value == 'kobold_log') {
                        showDialog(
                          context: context,
                          builder: (_) => const KoboldLogDialog(),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'new_chat',
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 20),
                            SizedBox(width: 12),
                            Text('New Chat'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'history',
                        child: Row(
                          children: [
                            Icon(Icons.history, size: 20),
                            SizedBox(width: 12),
                            Text('Chat History'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'import',
                        child: Row(
                          children: [
                            Icon(Icons.file_upload, size: 20),
                            SizedBox(width: 12),
                            Text('Import Chat'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: Row(
                          children: [
                            Icon(Icons.file_download, size: 20),
                            SizedBox(width: 12),
                            Text('Export Chat'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'context',
                        child: Row(
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              size: 20,
                              color: Colors.cyanAccent,
                            ),
                            SizedBox(width: 12),
                            Text('Context Budget'),
                          ],
                        ),
                      ),
                      // Show in a 1:1 OR a group (activeCharacter is null in a
                      // group, which used to hide this entirely), and regardless
                      // of the enabled flag — the dialog itself hosts the on/off
                      // toggle, so it must be reachable to turn evolution back on.
                      if (chatService.activeCharacter != null ||
                          chatService.isGroupMode)
                        PopupMenuItem(
                          value: 'evolution',
                          child: Row(
                            children: [
                              Icon(
                                Icons.psychology_alt,
                                size: 20,
                                color: Colors.tealAccent,
                              ),
                              SizedBox(width: 12),
                              Text('Character Evolution'),
                            ],
                          ),
                        ),
                      if (chatService.activeCharacter != null &&
                          chatService.activeGroup == null)
                        const PopupMenuItem(
                          value: 'fork_group',
                          child: Row(
                            children: [
                              Icon(
                                Icons.group_add,
                                size: 20,
                                color: Colors.purpleAccent,
                              ),
                              SizedBox(width: 12),
                              Text('Add Character (Group)…'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'kobold_log',
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 20,
                              color: Colors.greenAccent,
                            ),
                            SizedBox(width: 12),
                            Text('KoboldCpp Log'),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Image Generation (user spec): direct button (no PopupMenuButton<ImageGenMode>).
                  // The 6 types are now buttons *inside* the Image Studio UI. Magic wand opens neutral studio
                  // (starter mode custom; user picks type button immediately for clean UX). All assembly (incl.
                  // visualize N slider + think strip + user box as instr + persona + char visual no pers + style)
                  // handled inside on Craft. Keep launcher thin + "keep in sync" with studio show/ctor, service thins,
                  // builder, ImageGenContext, ModeInfoCard, _show (now mode-less).
                  Consumer<StorageService>(
                    builder: (context, storage, _) {
                      if (!storage.imageGenEnabled) {
                        return const SizedBox.shrink();
                      }
                      return IconButton(
                        icon: Icon(
                          Icons.auto_awesome,
                          color: AppColors.resolve(
                            context,
                            AppColors.formMasterAccent,
                            AppColors.formMasterAccent,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Image Studio',
                        onPressed: () =>
                            _showImageGenDialog(context, chatService),
                      );
                    },
                  ),

                  const SizedBox(width: 4),

                  Expanded(
                    child: AppTextField(
                      controller: _controller,
                      focusNode: _chatFocusNode,
                      maxLines: 10,
                      minLines: _inputMinLines,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      spellCheckConfiguration:
                          SpellCheckConfiguration.disabled(),
                      decoration: InputDecoration(
                        hintText: chatService.observerMode
                            ? 'Direct the scene...'
                            : 'Type a message...',
                        hintStyle: TextStyle(
                          color: chatService.observerMode
                              ? Colors.amberAccent.withValues(alpha: 0.6)
                              : AppColors.textTertiary(context),
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceContainerOf(context),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Impersonate button (magic wand — AI writes your next message)
                  Tooltip(
                    message: 'Impersonate (AI writes your message)',
                    child: IconButton(
                      icon: const Icon(
                        Icons.auto_fix_high,
                        color: Colors.amberAccent,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: chatService.isGenerating
                          ? null
                          : () {
                              final prefix = _controller.text;
                              chatService.impersonateUser(
                                prefix: prefix,
                                onToken: (accumulated) {
                                  _controller.text = accumulated;
                                  _controller
                                      .selection = TextSelection.fromPosition(
                                    TextPosition(offset: accumulated.length),
                                  );
                                },
                              );
                            },
                    ),
                  ),
                  // Mic button (push-to-talk STT)
                  Consumer2<SttService, StorageService>(
                    builder: (context, sttService, storage, _) {
                      if (!storage.sttEnabled || !sttService.isEngineUsable) {
                        return const SizedBox.shrink();
                      }
                      if (sttService.isTranscribing) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blueAccent,
                            ),
                          ),
                        );
                      }
                      return Tooltip(
                        message: sttService.isRecording
                            ? 'Stop recording'
                            : 'Voice input',
                        child: IconButton(
                          icon: Icon(
                            sttService.isRecording
                                ? Icons.stop_circle
                                : Icons.mic,
                            color: sttService.isRecording
                                ? Colors.redAccent
                                : AppColors.iconSecondary(context),
                          ),
                          onPressed: chatService.isGenerating
                              ? null
                              : () async {
                                  if (sttService.isRecording) {
                                    final text = await sttService
                                        .stopRecordingAndTranscribe();
                                    if (text != null && text.isNotEmpty) {
                                      if (storage.autoSendTranscription &&
                                          _controller.text.isEmpty) {
                                        chatService.sendMessage(text);
                                      } else {
                                        _controller.text =
                                            _controller.text.isEmpty
                                            ? text
                                            : '${_controller.text} $text';
                                        _controller.selection =
                                            TextSelection.fromPosition(
                                              TextPosition(
                                                offset: _controller.text.length,
                                              ),
                                            );
                                      }
                                    }
                                  } else {
                                    final micOk = await sttService
                                        .checkMicAvailable();
                                    if (!micOk && context.mounted) {
                                      _showNoMicDialog(context);
                                      return;
                                    }
                                    await sttService.startRecording();
                                  }
                                },
                        ),
                      );
                    },
                  ),
                  // Call button (voice call mode)
                  Consumer2<SttService, StorageService>(
                    builder: (context, sttService, storage, _) {
                      if (!storage.sttEnabled ||
                          !sttService.isEngineUsable ||
                          chatService.isGroupMode) {
                        return const SizedBox.shrink();
                      }
                      return Tooltip(
                        message: 'Start voice call',
                        child: IconButton(
                          icon: const Icon(
                            Icons.call,
                            color: Colors.greenAccent,
                          ),
                          onPressed:
                              chatService.isGenerating || sttService.isBusy
                              ? null
                              : () async {
                                  final micOk = await sttService
                                      .checkMicAvailable();
                                  if (!micOk && context.mounted) {
                                    _showNoMicDialog(context);
                                    return;
                                  }
                                  setState(() => _isCallActive = true);
                                },
                        ),
                      );
                    },
                  ),
                  // Auto-play button (observer mode only)
                  if (chatService.isGroupMode &&
                      chatService.observerMode &&
                      !chatService.isGenerating)
                    Tooltip(
                      message: chatService.autoPlayActive
                          ? 'Pause auto-chat'
                          : 'Start auto-chat',
                      child: IconButton(
                        icon: Icon(
                          chatService.autoPlayActive
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: chatService.autoPlayActive
                              ? Colors.orangeAccent
                              : Colors.amberAccent,
                        ),
                        onPressed: () {
                          if (chatService.autoPlayActive) {
                            chatService.stopAutoPlay();
                          } else {
                            chatService.startAutoPlay();
                          }
                        },
                      ),
                    ),
                  // Next Character button (group mode only, not in auto-play)
                  if (chatService.isGroupMode &&
                      !chatService.isGenerating &&
                      !chatService.autoPlayActive)
                    Tooltip(
                      message: chatService.nextCharacter != null
                          ? 'Next: ${chatService.nextCharacter!.name}'
                          : 'Trigger next character',
                      child: IconButton(
                        icon: const Icon(
                          Icons.group,
                          color: Colors.purpleAccent,
                        ),
                        onPressed: () => chatService.triggerNextCharacter(),
                      ),
                    ),
                  chatService.isGenerating
                      ? IconButton(
                          icon: const Icon(
                            Icons.stop_circle,
                            color: Colors.redAccent,
                          ),
                          tooltip: chatService.autoPlayActive
                              ? 'Stop Auto-Chat'
                              : 'Stop Generation',
                          onPressed: () {
                            chatService.stopAutoPlay();
                            chatService.stopGeneration();
                          },
                        )
                      : Tooltip(
                          message: chatService.observerMode
                              ? 'Send director note'
                              : 'Send message',
                          child: IconButton(
                            icon: Icon(
                              chatService.observerMode
                                  ? Icons.movie_creation
                                  : Icons.send,
                              color: chatService.isGuestBusy
                                  ? AppColors.iconSecondary(context)
                                  : (chatService.observerMode
                                        ? Colors.amberAccent
                                        : Colors.blueAccent),
                            ),
                            onPressed: () {
                              if (_controller.text.isNotEmpty &&
                                  !chatService.isGenerating &&
                                  !chatService.isGuestBusy) {
                                chatService.sendMessage(_controller.text);
                                _controller.clear();
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _scrollToBottom(),
                                );
                              }
                            },
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showNoMicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        icon: const Icon(Icons.mic_off, color: Colors.redAccent, size: 40),
        title: const Text(
          'No Microphone Detected',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'No microphone was found or microphone permission was denied.\n\n'
          '• Check that a microphone is connected\n'
          '• Grant microphone permission if prompted\n'
          '• Select a specific microphone in Settings → Voice Input',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Wraps a sidebar widget with a draggable resize handle on its left edge.
  Widget _buildResizableSidebar({required Widget child}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                double newWidth = _sidebarWidth - details.delta.dx;
                if (newWidth < 150) {
                  _sidebarWidth = 0; // Snap to closed
                } else {
                  _sidebarWidth = newWidth.clamp(150, 600);
                }
              });
            },
            child: Container(
              width: 6,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.white24,
                      Colors.black12,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_sidebarWidth > 0) SizedBox(width: _sidebarWidth, child: child),
      ],
    );
  }

  Widget _buildRightSidebar(ChatService chatService) {
    final focused = _focusedParticipant(chatService);
    if (focused == null) return const SizedBox.shrink();
    final character = focused.card;
    final isGroup = chatService.isGroupMode;
    final cast = chatService.cast;
    final userName = Provider.of<UserPersonaService>(
      context,
      listen: false,
    ).persona.name;
    String replace(String text) {
      return MacroResolver().resolve(
        text,
        MacroContext(userName: userName, characterName: character.name),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          left: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          // Expression image or default character portrait
          Consumer<ChatService>(
            builder: (context, chat, _) {
              final storage = Provider.of<StorageService>(
                context,
                listen: false,
              );
              final isExpressionEnabled = storage.expressionEnabled;
              final hasAvatars =
                  character.avatarImages != null &&
                  character.avatarImages!.isNotEmpty;

              File? expressionFile;
              String? expressionKey;
              String? expressionEmoji;

              if (isExpressionEnabled &&
                  hasAvatars &&
                  !chat.isEvaluatingRealism) {
                final avatar = chat.resolveExpressionAvatar(
                  character,
                  rerollIfSame: storage.expressionRerollSame,
                );
                if (avatar != null) {
                  final avatarDir = storage.characterAvatarDir(character.name);
                  expressionFile = File('${avatarDir.path}/${avatar.filename}');
                  expressionKey = avatar.id;
                  final label = chat.currentExpressionLabel;
                  expressionEmoji = label != null
                      ? EmotionLabels.emoji[label]
                      : null;
                }
              }

              File? displayFile;
              Widget? fallbackWidget;

              if (expressionFile != null) {
                displayFile = expressionFile;
              } else if (isExpressionEnabled) {
                // Apply fallback behavior
                final fallback = storage.expressionFallback;
                if (fallback == 'none') {
                  return const SizedBox.shrink();
                } else if (fallback == 'emoji') {
                  final label = chat.currentExpressionLabel ?? 'neutral';
                  final emoji = EmotionLabels.emoji[label] ?? '🎭';
                  fallbackWidget = Center(
                    child: Text(
                      emoji,
                      style: TextStyle(fontSize: _sidebarWidth * 0.5),
                    ),
                  );
                } else if (fallback == 'prime' && hasAvatars) {
                  // Show prime avatar
                  final primeAvatar =
                      character.avatarImages!
                          .where(
                            (a) =>
                                a.displayOrder + 1 ==
                                character.primeAvatarIndex,
                          )
                          .isEmpty
                      ? character.avatarImages!.first
                      : character.avatarImages!.firstWhere(
                          (a) =>
                              a.displayOrder + 1 == character.primeAvatarIndex,
                        );
                  final avatarDir = storage.characterAvatarDir(character.name);
                  displayFile = File(
                    '${avatarDir.path}/${primeAvatar.filename}',
                  );
                  expressionKey = primeAvatar.id;
                } else {
                  // 'neutral' or default: show neutral avatar if available, else character image
                  if (hasAvatars) {
                    final neutralAvatar = character.avatarImages!
                        .where((a) => a.label?.toLowerCase() == 'neutral')
                        .toList();
                    if (neutralAvatar.isNotEmpty) {
                      final avatarDir = storage.characterAvatarDir(
                        character.name,
                      );
                      displayFile = File(
                        '${avatarDir.path}/${neutralAvatar.first.filename}',
                      );
                      expressionKey = neutralAvatar.first.id;
                      expressionEmoji = EmotionLabels.emoji['neutral'];
                    }
                  }
                  if (displayFile == null && character.imagePath != null) {
                    displayFile = _resolveCharImage(character.imagePath!);
                  }
                }
              } else {
                // Expressions disabled, show character image
                if (character.imagePath != null) {
                  displayFile = _resolveCharImage(character.imagePath!);
                }
              }

              if (fallbackWidget != null) return fallbackWidget;
              if (displayFile == null) return const SizedBox.shrink();

              final avatarLocked =
                  character.frontPorchExtensions?.avatarLocked ?? false;
              final avatarSize = avatarLocked
                  ? _sidebarWidth.clamp(0, 300).toDouble()
                  : _sidebarWidth;

              Widget avatar = SizedBox(
                height: avatarSize,
                width: avatarSize,
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: Image.file(
                        displayFile,
                        key: ValueKey(expressionKey ?? 'default'),
                        width: avatarSize,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.resolve(
                            context,
                            Colors.black26,
                            Colors.black.withValues(alpha: 0.1),
                          ),
                          child: Icon(
                            Icons.person,
                            color: AppColors.iconSecondary(context),
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                    // Emotion label badge
                    if (expressionEmoji != null)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              context,
                              Colors.black.withValues(alpha: 0.7),
                              Colors.black.withValues(alpha: 0.45),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                expressionEmoji,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
              if (avatarLocked && _sidebarWidth > 300) {
                avatar = Align(alignment: Alignment.topRight, child: avatar);
              }
              return avatar;
            },
          ),

          // Settings Button
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borderOf(context).withValues(alpha: 0.35),
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: PopupMenuButton<String>(
                color: AppColors.surfaceContainerOf(context),
                elevation: 8,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                  side: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
                ),
                offset: const Offset(0, 8),
                onSelected: (value) async {
                  switch (value) {
                    case 'edit_character':
                      final result = await showDialog(
                        context: context,
                        builder: (context) =>
                            EditCharacterDialog(character: character),
                      );
                      if (result == true) {
                        setState(() {});
                      }
                      break;
                    case 'expressions':
                      final storage = Provider.of<StorageService>(
                        context,
                        listen: false,
                      );
                      final repo = Provider.of<CharacterRepository>(
                        context,
                        listen: false,
                      );
                      // In a group, members are single-avatar copies — editing
                      // one would write to a throwaway id and never inherit. Route
                      // the editor at the real LIBRARY character (the shared home)
                      // so expression edits persist and flow back to the group.
                      // 1:1 already passes the library character itself.
                      final exprTarget = isGroup
                          ? (chatService.originLibraryCardFor(character) ??
                                character)
                          : character;
                      final result = await CharacterAvatarsDialog.show(
                        context: context,
                        character: exprTarget,
                        repository: repo,
                        storage: storage,
                      );
                      if (result == true) {
                        // Push the freshly edited library expressions onto the
                        // live member card so the group reflects them immediately
                        // (inheritance otherwise skips members already populated).
                        if (!identical(exprTarget, character)) {
                          character.avatarImages =
                              exprTarget.avatarImages == null
                              ? null
                              : List<AvatarImage>.from(
                                  exprTarget.avatarImages!,
                                );
                        }
                        setState(() {});
                      }
                      break;
                    case 'ui':
                      showDialog(
                        context: context,
                        builder: (context) =>
                            UiSettingsDialog(character: character),
                      );
                      break;
                    case 'chat':
                      showDialog(
                        context: context,
                        builder: (context) => const ChatSettingsDialog(),
                      );
                      break;
                    case 'model':
                      showDialog(
                        context: context,
                        builder: (context) => const ModelSettingsDialog(),
                      );
                      break;
                    case 'tts':
                      showDialog(
                        context: context,
                        builder: (context) => const TtsSettingsDialog(),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit_character',
                    child: SettingsMenuItem(
                      icon: Icons.edit_outlined,
                      label: 'Edit Character',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'expressions',
                    child: SettingsMenuItem(
                      icon: Icons.mood_outlined,
                      label: 'Expression Images',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ui',
                    child: SettingsMenuItem(
                      icon: Icons.tune_outlined,
                      label: 'UI Settings',
                    ),
                  ),
                  PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'chat',
                    child: SettingsMenuItem(
                      icon: Icons.chat_bubble_outline,
                      label: 'Chat Settings',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'model',
                    child: SettingsMenuItem(
                      icon: Icons.memory_outlined,
                      label: 'Model Settings',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'tts',
                    child: SettingsMenuItem(
                      icon: Icons.volume_up_outlined,
                      label: 'TTS Settings',
                    ),
                  ),
                ],
                child: const Text(
                  'Main Settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),

          // ── Group Settings (group only; sits directly under Main Settings,
          //    above the cast roster, so the whole-group controls are found
          //    before per-character ones) ──
          if (isGroup)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showGroupSettingsDialog(chatService),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Group Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

          // ── Participant roster (only when more than one speaker) ──
          if (cast.length > 1) _buildParticipantRoster(chatService, cast, focused),

          // ── Director controls (group turn-taking) ──
          if (isGroup) _buildDirectorControls(chatService),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Author's Note (chat-level) ──
                AuthorNoteSection(chatService: chatService),
                const SizedBox(height: 16),

                // ── Per-focused-participant detail (dispatched by store) ──
                if (isGroup) ...[
                  GroupMemberCard(
                    character: character,
                    chatService: chatService,
                    avatarColor: _groupCharacterColor(
                      cast.indexWhere((p) => p.id == focused.id) < 0
                          ? 0
                          : cast.indexWhere((p) => p.id == focused.id),
                    ),
                    isNextSpeaker:
                        chatService.nextCharacter?.name == character.name,
                    isExpanded: true,
                    onTap: chatService.isGenerating
                        ? () {}
                        : () => chatService.setNextCharacter(character),
                    avatarFile: character.imagePath != null
                        ? _resolveCharImage(character.imagePath!)
                        : null,
                    evolutionCount: chatService.getEvolutionCountFor(character),
                    // > 1 (not > 2): removing the second-to-last member is
                    // allowed and auto-collapses the group back to a 1:1.
                    canRemove: chatService.groupCharacters.length > 1 &&
                        !chatService.isGenerating,
                    onRemove:
                        (chatService.groupCharacters.length > 1 &&
                            !chatService.isGenerating)
                        ? () async {
                            final groupRepo =
                                Provider.of<GroupChatRepository>(
                                  context,
                                  listen: false,
                                );
                            await chatService.removeCharacterFromGroup(
                              character,
                              groupRepo,
                            );
                          }
                        : null,
                    onOpenObjectives: () {
                      showDialog(
                        context: context,
                        builder: (_) => GroupObjectivesDialog(
                          chatService: chatService,
                          groupCharacters: chatService.groupCharacters,
                          initialCharacter: character,
                        ),
                      );
                    },
                  ),
                  // The sidebar "Add Character" button was removed: adding a
                  // member is now the `/join <name>` macro (always a full member
                  // in a group), surfaced by the "type /" command helper. This
                  // keeps the roster panel clean.
                  const SizedBox(height: 12),
                  Consumer<ChatService>(
                    builder: (context, chat, _) => ChaosModeSection(
                      chat: chat,
                      onSpinRequested: () => _showChanceTimeOverlay(context),
                    ),
                  ),
                  Consumer<ChatService>(
                    builder: (context, chat, _) => SceneTimeSection(chat: chat),
                  ),
                  // NSFW Enhancement (arousal) — chat-wide toggle for the group.
                  // A simple on/off (NOT the 1:1 NsfwEnhancementsSection, whose
                  // per-speaker arousal gauge is volatile here and renders an empty
                  // box when off — per-member arousal already shows in member cards).
                  // Reads the stable group flag; the setter propagates to every
                  // member so each speaker's eval actually evaluates arousal.
                  Consumer<ChatService>(
                    builder: (context, chat, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: Color(0xFFEA580C),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'NSFW Enhancement (arousal)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: 20,
                            child: Switch(
                              value: chat.isGroupNsfwEnabled,
                              activeThumbColor: const Color(0xFFF97316),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) => chat.setNsfwCooldownEnabled(val),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GroupLorebookSection(chatService: chatService),
                  const SizedBox(height: 8),
                  SummarySection(chatService: chatService),
                ] else if (focused.realismEnabled) ...[
                  // ── RAG Memory ──
                  MemorySection(chatService: chatService),
                  const SizedBox(height: 16),

                // ── Active Fixation (always visible when set) ──
                Consumer<ChatService>(
                  builder: (context, chat, _) {
                    if (chat.activeFixation.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.resolve(
                            context,
                            Colors.purpleAccent.withValues(alpha: 0.12),
                            Colors.purple.shade50.withValues(alpha: 0.6),
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.resolve(
                              context,
                              Colors.purpleAccent.withValues(alpha: 0.4),
                              Colors.purple.shade200.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 16,
                              color: AppColors.resolve(
                                context,
                                Colors.purpleAccent,
                                Colors.purple.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CURRENT FIXATION',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppColors.resolve(
                                        context,
                                        Colors.purpleAccent,
                                        Colors.purple.shade700,
                                      ),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    chat.activeFixation,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textPrimary(context),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // ── Realism Mode ──
                RealismSection(chatService: chatService),
                const SizedBox(height: 8),

                // ── Chaos Mode ──
                Consumer<ChatService>(
                  builder: (context, chat, _) => ChaosModeSection(
                    chat: chat,
                    onSpinRequested: () => _showChanceTimeOverlay(context),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Objective ──
                ObjectiveSection(chatService: chatService),
                const SizedBox(height: 16),

                // ── Character Evolution (collapsed by default) ──
                Consumer<ChatService>(
                  builder: (context, chat, _) {
                    final storage = Provider.of<StorageService>(
                      context,
                      listen: false,
                    );
                    if (!storage.characterEvolutionEnabled) {
                      return const SizedBox.shrink();
                    }
                    final evolvedP = chat.getEffectivePersonality;
                    final evolvedS = chat.getEffectiveScenario;
                    final count = chat.characterEvolutionCount;
                    return CollapsibleSidebarSection(
                      icon: Icons.psychology_alt,
                      iconColor: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                      title: 'Character Evolution',
                      trailing: Text(
                        count > 0 ? 'Evolved $count×' : 'Not evolved',
                        style: TextStyle(
                          fontSize: 11,
                          color: count > 0
                              ? AppColors.resolve(
                                  context,
                                  Colors.tealAccent,
                                  Colors.teal.shade700,
                                )
                              : AppColors.textTertiary(context),
                        ),
                      ),
                      initiallyExpanded: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (count > 0) ...[
                            if (evolvedP != null && evolvedP.isNotEmpty) ...[
                              Text(
                                'Evolved Personality',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerOf(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.resolve(
                                      context,
                                      Colors.tealAccent.withValues(alpha: 0.3),
                                      Colors.teal.shade200.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  maxHeight: 100,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    evolvedP,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (evolvedS != null && evolvedS.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Evolved Scenario',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerOf(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.resolve(
                                      context,
                                      Colors.tealAccent.withValues(alpha: 0.3),
                                      Colors.teal.shade200.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  maxHeight: 100,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    evolvedS,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showEvolutionDialog(
                                    context,
                                    chat,
                                    focusedCard:
                                        _focusedParticipant(chat)?.card,
                                  ),
                                  icon: const Icon(
                                    Icons.edit,
                                    size: 14,
                                    color: Colors.tealAccent,
                                  ),
                                  label: const Text(
                                    'Review & Edit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.tealAccent,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.tealAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showResetEvolutionConfirmSidebar(
                                        context,
                                        chat,
                                      ),
                                  icon: const Icon(
                                    Icons.restart_alt,
                                    size: 14,
                                    color: Colors.redAccent,
                                  ),
                                  label: const Text(
                                    'Reset',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildEvolveNowButton(context, chat),
                          ] else ...[
                            _buildEvolveNowButton(context, chat),
                            const SizedBox(height: 4),
                            const Text(
                              'Personality & scenario will evolve as you chat, or tap above to evolve now.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white24,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── Chat Summary ──
                SummarySection(chatService: chatService),
                const SizedBox(height: 16),

                // ── Scenario ──
                Consumer<ChatService>(
                  builder: (context, chat, _) {
                    final storage = Provider.of<StorageService>(
                      context,
                      listen: false,
                    );
                    final evolvedS = chat.getEffectiveScenario;
                    final hasEvolution =
                        storage.characterEvolutionEnabled &&
                        evolvedS != null &&
                        evolvedS.isNotEmpty;
                    if (hasEvolution) return const SizedBox.shrink();
                    return SidebarSection(
                      title: 'Scenario',
                      content: replace(character.scenario),
                    );
                  },
                ),

                  // ── Lorebook Triggers (bottom) ──
                  const SizedBox(height: 16),
                  LorebookSection(character: character),

                  // ── Description ──
                  SidebarSection(
                    title: 'Description',
                    content: replace(character.description),
                  ),
                ] else ...[
                  // ── Lite NPC (Scene Guest) — realism tracking off ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.borderOf(context).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_off,
                          size: 16,
                          color: AppColors.iconSecondary(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lite NPC — no realism or needs tracking for this guest.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SidebarSection(
                    title: 'Scenario',
                    content: replace(character.scenario),
                  ),
                  const SizedBox(height: 8),
                  LorebookSection(character: character),
                  SidebarSection(
                    title: 'Description',
                    content: replace(character.description),
                  ),
                  const SizedBox(height: 16),
                  Consumer<ChatService>(
                    builder: (context, chat, _) => ChaosModeSection(
                      chat: chat,
                      onSpinRequested: () => _showChanceTimeOverlay(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SummarySection(chatService: chatService),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal roster of all cast participants. Tapping one focuses its
  /// per-character sidebar sections. Shown only when more than one speaker is
  /// present (1:1 + guests, or a group).
  Widget _buildParticipantRoster(
    ChatService chatService,
    List<ChatParticipant> cast,
    ChatParticipant focused,
  ) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = cast[i];
          final isFocused = p.id == focused.id;
          final color = _groupCharacterColor(i);
          final img = p.card.imagePath != null
              ? _resolveCharImage(p.card.imagePath!)
              : null;
          return InkWell(
            onTap: () => setState(() => _focusedParticipantId = p.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFocused ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: color,
                    backgroundImage: img != null ? FileImage(img) : null,
                    child: img == null
                        ? Text(
                            p.name.isNotEmpty ? p.name[0] : '?',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 48,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: isFocused
                          ? AppColors.textPrimary(context)
                          : AppColors.textTertiary(context),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Group turn-taking controls (Group Settings + Director Mode + response
  /// delay). Shown when the chat has scheduled speakers (a group).
  Widget _buildDirectorControls(ChatService chatService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.movie_creation,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Director Mode',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Switch(
                value: chatService.observerMode,
                activeTrackColor: Colors.amberAccent,
                onChanged: chatService.isGenerating
                    ? null
                    : (val) => chatService.setObserverMode(val),
              ),
            ],
          ),
          if (chatService.observerMode) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Characters chat autonomously. Use the input box to direct the scene.',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.amberAccent.withValues(alpha: 0.7),
                ),
              ),
            ),
            Consumer<StorageService>(
              builder: (context, storage, _) {
                chatService.directorDelaySec = storage.directorDelay;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Response Delay',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const Spacer(),
                        Text(
                          '${(_dragDirectorDelay ?? storage.directorDelay).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _dragDirectorDelay ?? storage.directorDelay,
                        min: 0.5,
                        max: 60.0,
                        divisions: 119,
                        activeColor: Colors.amberAccent,
                        inactiveColor: Colors.white12,
                        onChanged: (val) =>
                            setState(() => _dragDirectorDelay = val),
                        onChangeEnd: (val) {
                          _dragDirectorDelay = null;
                          storage.setDirectorDelay(val);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

}

Widget _buildRiskItem(IconData icon, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.orangeAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
