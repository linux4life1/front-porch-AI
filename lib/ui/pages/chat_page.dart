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
import 'dart:ui';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/dialogs/character_avatars_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/edit_character_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/user_persona_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/context_viewer_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings_dialog.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/kobold_log_dialog.dart';
import 'package:front_porch_ai/services/embedding_sidecar.dart';
import 'package:front_porch_ai/ui/widgets/call_overlay.dart';
import 'package:front_porch_ai/ui/widgets/chance_time_overlay.dart';
import 'package:front_porch_ai/ui/widgets/onnx_download_overlay.dart';
import 'package:front_porch_ai/services/expression_classifier.dart';
import 'package:file_picker/file_picker.dart';

/// Applies a Google Font to a base TextStyle dynamically.
TextStyle _applyGoogleFont(String? fontFamily, TextStyle baseStyle) {
  if (fontFamily == null || fontFamily.isEmpty) return baseStyle;

  switch (fontFamily) {
    case 'Roboto':
      return GoogleFonts.roboto(textStyle: baseStyle);
    case 'Open Sans':
      return GoogleFonts.openSans(textStyle: baseStyle);
    case 'Lato':
      return GoogleFonts.lato(textStyle: baseStyle);
    case 'Source Sans 3':
      return GoogleFonts.sourceSans3(textStyle: baseStyle);
    case 'Nunito':
      return GoogleFonts.nunito(textStyle: baseStyle);
    case 'Poppins':
      return GoogleFonts.poppins(textStyle: baseStyle);
    case 'Montserrat':
      return GoogleFonts.montserrat(textStyle: baseStyle);
    case 'Raleway':
      return GoogleFonts.raleway(textStyle: baseStyle);
    case 'Work Sans':
      return GoogleFonts.workSans(textStyle: baseStyle);
    case 'DM Sans':
      return GoogleFonts.dmSans(textStyle: baseStyle);
    case 'Quicksand':
      return GoogleFonts.quicksand(textStyle: baseStyle);
    case 'Rubik':
      return GoogleFonts.rubik(textStyle: baseStyle);
    case 'Karla':
      return GoogleFonts.karla(textStyle: baseStyle);
    case 'Merriweather':
      return GoogleFonts.merriweather(textStyle: baseStyle);
    case 'Playfair Display':
      return GoogleFonts.playfairDisplay(textStyle: baseStyle);
    case 'Roboto Mono':
      return GoogleFonts.robotoMono(textStyle: baseStyle);
    case 'Fira Code':
      return GoogleFonts.firaCode(textStyle: baseStyle);
    default:
      return baseStyle;
  }
}

class _StyledTextController extends TextEditingController {
  static final _pattern = RegExp(r'("[^"]*")|(\*[^*]*\*)');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final matches = _pattern.allMatches(text);

    if (matches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final List<TextSpan> spans = [];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(text: text.substring(lastEnd, match.start), style: style),
        );
      }
      final matchText = match.group(0)!;
      if (matchText.startsWith('"')) {
        spans.add(
          TextSpan(
            text: matchText,
            style: style?.copyWith(
              color: AppColors.resolve(context, Colors.amberAccent, const Color(0xFFB45309)),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: matchText,
            style: style?.copyWith(color: AppColors.resolve(context, const Color(0xFF90CAF9), const Color(0xFF1565C0))),
          ),
        );
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: style));
    }

    return TextSpan(children: spans, style: style);
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _StyledTextController _controller = _StyledTextController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _chatFocusNode;
  bool _autoScroll = true;
  double _sidebarWidth = 300;
  int _inputMinLines = 1;
  double _dragAccumulator = 0;
  bool _isCallActive = false;
  bool? _externalImagesAllowed;
  bool _imageConsentChecked = false;
  TtsService? _ttsService;
  ChatService? _chatService;

  // Slider drag tracking — store live value during drag, null on release
  double? _dragDirectorDelay;

  /// Resolve a character [imagePath] (basename or full path) to a [File].
  /// Always use this instead of [File(imagePath)] directly.
  File _resolveCharImage(String imagePath) {
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(imagePath);
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
  }

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
  }

  void _showChanceTimeOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChanceTimeOverlay(),
    );
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
              appBar: isGroup
                  ? _buildGroupAppBar(context, chatService)
                  : _buildAppBar(context, character!),
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
                              final hasCustomBg = customEntry != null &&
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
                                      final storage = Provider.of<StorageService>(
                                        context,
                                        listen: false,
                                      );
                                      final displayMode =
                                          storage.expressionDisplayMode;
                                      final isEnabled = storage.expressionEnabled;
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
                                        final avatar = chat.resolveExpressionAvatar(
                                        char,
                                        rerollIfSame: storage.expressionRerollSame,
                                      );
                                      if (avatar == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final avatarDir = storage.characterAvatarDir(
                                        char.name,
                                      );
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
                                                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                                  ),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.85),
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
                                                 File(
                                                   customEntry['filePath']!,
                                                 ),
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
                                      // In group mode, pass the character's image based on sender
                                      File? senderImage;
                                      Color? senderColor;
                                      if (isGroup && !msg.isUser) {
                                        final senderChar = chatService
                                            .groupCharacters
                                            .where((c) => c.name == msg.sender)
                                            .firstOrNull;
                                        senderImage =
                                            senderChar?.imagePath != null
                                            ? _resolveCharImage(
                                                senderChar!.imagePath!,
                                              )
                                            : null;
                                        final senderIdx = chatService
                                            .groupCharacters
                                            .indexWhere(
                                              (c) => c.name == msg.sender,
                                            );
                                        senderColor = _groupCharacterColor(
                                          senderIdx >= 0 ? senderIdx : 0,
                                        );
                                      } else {
                                        senderImage =
                                            character?.imagePath != null
                                            ? _resolveCharImage(
                                                character!.imagePath!,
                                              )
                                            : null;
                                      }
                                       return _MessageBubble(
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
                                                 .where((c) => c.name == msg.sender)
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
                          _GenerationStatusBar(chatService: chatService),
                        _buildInputArea(context, chatService),
                      ],
                    ),
                  ),
                  if (isGroup)
                    _buildResizableSidebar(
                      child: _buildGroupSidebar(chatService),
                    )
                  else if (character != null)
                    _buildResizableSidebar(
                      child: _buildRightSidebar(character, chatService),
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
                chatService.isProcessingGreeting)
              _RealismProcessingOverlay(
                chatService: chatService,
                isGreeting: chatService.isProcessingGreeting,
              ),
            // Objective completion check overlay (only when realism isn't already showing)
            if (chatService.isCheckingCompletion &&
                !chatService.isEvaluatingRealism &&
                !chatService.isProcessingGreeting)
              _ObjectiveCheckOverlay(chatService: chatService),
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

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    CharacterCard character,
  ) {
    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          CircleAvatar(
            backgroundImage: character.imagePath != null
                ? FileImage(_resolveCharImage(character.imagePath!))
                : null,
            child: character.imagePath == null
                ? const Icon(Icons.person)
                : null,
            onBackgroundImageError: (_, _) {},
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (character.description.isNotEmpty)
                Text(
                  character.description.length > 30
                      ? '${character.description.substring(0, 30)}...'
                      : character.description,
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
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

  PreferredSizeWidget _buildGroupAppBar(
    BuildContext context,
    ChatService chatService,
  ) {
    final group = chatService.activeGroup!;
    final chars = chatService.groupCharacters;
    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          // Stacked avatars
          SizedBox(
            width: 24.0 + (chars.length.clamp(0, 4) - 1) * 16,
            height: 32,
            child: Stack(
              children: [
                for (int i = 0; i < chars.length.clamp(0, 4); i++)
                  Positioned(
                    left: i * 16.0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: _groupCharacterColor(i),
                      backgroundImage: chars[i].imagePath != null
                          ? FileImage(_resolveCharImage(chars[i].imagePath!))
                          : null,
                      child: chars[i].imagePath == null
                          ? Text(
                              chars[i].name[0],
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              Text(
                '${chars.length} characters • ${group.turnOrder.name}',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
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

  /// Simple emotion → accent color for the realism ring around avatars.
  Color _emotionColor(String? emotion) {
    if (emotion == null) return Colors.grey;
    switch (emotion.toLowerCase()) {
      case 'joy':
      case 'amusement':
      case 'excitement':
        return Colors.amber;
      case 'sadness':
      case 'grief':
      case 'disappointment':
        return Colors.blueGrey;
      case 'anger':
      case 'annoyance':
        return Colors.redAccent;
      case 'fear':
      case 'nervousness':
        return Colors.deepPurpleAccent;
      case 'love':
      case 'affection':
      case 'caring':
        return Colors.pinkAccent;
      case 'surprise':
      case 'curiosity':
        return Colors.cyanAccent;
      default:
        return Colors.tealAccent;
    }
  }

  // ── Helpers for full per-character realism UI in group sidebar (reusing 1:1 visual style) ──

  int _calculateGroupTier(int score) {
    final abs = score.abs();
    if (abs < 5) return 0;
    if (abs < 15) return score > 0 ? 1 : -1;
    if (abs < 30) return score > 0 ? 2 : -2;
    if (abs < 50) return score > 0 ? 3 : -3;
    if (abs < 75) return score > 0 ? 4 : -4;
    if (abs < 110) return score > 0 ? 5 : -5;
    if (abs < 150) return score > 0 ? 6 : -6;
    if (abs < 200) return score > 0 ? 7 : -7;
    if (abs < 250) return score > 0 ? 8 : -8;
    if (abs < 300) return score > 0 ? 9 : -9;
    return score > 0 ? 10 : -10;
  }

  String _getGroupBondTierName(int tier) {
    switch (tier) {
      case 10: return 'Devoted';
      case 9: return 'Enamored';
      case 8: return 'Smitten';
      case 7: return 'Affectionate';
      case 6: return 'Fond';
      case 5: return 'Warm';
      case 4: return 'Friendly';
      case 3: return 'Neutral+';
      case 2: return 'Neutral';
      case 1: return 'Cool';
      case 0: return 'Indifferent';
      case -1: return 'Distant';
      case -2: return 'Cold';
      case -3: return 'Hostile';
      case -4: return 'Resentful';
      case -5: return 'Bitter';
      case -6: return 'Hateful';
      case -7: return 'Despising';
      case -8: return 'Loathing';
      case -9: return 'Reviling';
      case -10: return 'Abhorrent';
      default: return 'Unknown';
    }
  }

  Color _getGroupTierColor(int tier) {
    if (tier >= 10) return Colors.deepPurpleAccent;
    if (tier >= 9) return Colors.purpleAccent;
    if (tier >= 8) return Colors.pinkAccent;
    if (tier >= 7) return Colors.pink;
    if (tier >= 6) return Colors.pink.shade200;
    if (tier >= 5) return Colors.orangeAccent;
    if (tier >= 4) return Colors.greenAccent;
    if (tier >= 3) return AppColors.resolve(context, Colors.lightBlue, Colors.blue.shade700);
    if (tier >= 2) return AppColors.resolve(context, Colors.blueGrey, Colors.blueGrey.shade700);
    if (tier >= 1) return AppColors.resolve(context, Colors.grey.shade400, Colors.grey.shade700);
    if (tier == 0) return AppColors.textTertiary(context);
    if (tier >= -1) return AppColors.resolve(context, Colors.orangeAccent.shade100, Colors.orange.shade700);
    if (tier >= -2) return AppColors.resolve(context, Colors.redAccent.shade100, Colors.red.shade600);
    if (tier >= -3) return Colors.redAccent;
    if (tier >= -4) return Colors.red;
    if (tier >= -5) return AppColors.resolve(context, Colors.red.shade900, Colors.red.shade800);
    if (tier >= -6) return AppColors.resolve(context, Colors.brown.shade900, Colors.brown.shade700);
    if (tier >= -7) return AppColors.resolve(context, Colors.deepOrange.shade900, Colors.deepOrange.shade700);
    if (tier >= -8) return AppColors.resolve(context, Colors.amber.shade900, Colors.amber.shade800);
    if (tier >= -9) return AppColors.resolve(context, Colors.orange.shade900, Colors.orange.shade800);
    return AppColors.textPrimary(context);
  }

  Widget _buildGroupRealismRichRow({
    required BuildContext context, // Added for AppColors access in light-mode chrome hardening of sidebar realism panels (per rules, edit to existing helper)
    required String label,
    required int value,
    required int tier,
    required String tierName,
    required Color color,
    required IconData icon,
    int maxValue = 300,
  }) {
    final isNegative = value < 0;
    final displayColor = isNegative ? Colors.redAccent : color;
    final absVal = value.abs();
    final target = maxValue;
    final norm = ((value + maxValue) / (maxValue * 2.0)).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: label == 'Bond'
              ? 'Bond: Current relationship strength with this character in the group.'
              : (label.contains('Trust')
                  ? 'Trust: How much the character believes and relies on you.'
                  : 'Arousal: Physical/sexual tension level.'),
          child: Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: displayColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '$label: $tierName',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: displayColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$absVal/$target',
                style: TextStyle(fontSize: 10, color: AppColors.textTertiary(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: norm,
            minHeight: 5,
            backgroundColor: AppColors.resolve(context, Colors.white10, Colors.black.withValues(alpha: 0.08)),
            valueColor: AlwaysStoppedAnimation<Color>(displayColor),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCharacterFullRealismUI(BuildContext context, ChatService chatService, CharacterCard character) {
    // Added BuildContext param (documented) to existing private helper for AppColors in light-mode sidebar realism UI; required to pass to _buildGroupRealismRichRow
    if (!chatService.isGroupRealismActive) return const SizedBox.shrink();

    final affection = chatService.getAffectionForGroupCharacter(character);
    final trust = chatService.getTrustForGroupCharacter(character);
    final arousal = chatService.getArousalForGroupCharacter(character);
    final emotion = chatService.getEmotionForGroupCharacter(character) ?? 'neutral';
    final intensity = chatService.getEmotionIntensityForGroupCharacter(character) ?? '';
    final isDirector = chatService.observerMode;
    final opacity = isDirector ? 0.35 : 1.0;

    final bondTier = _calculateGroupTier(affection);
    final bondName = _getGroupBondTierName(bondTier);
    final bondColor = _getGroupTierColor(bondTier);

    final trustTier = _calculateGroupTier(trust);
    final trustName = _getGroupBondTierName(trustTier); // reuse similar naming for simplicity
    final trustColor = _getGroupTierColor(trustTier);

    final arousalTier = _calculateGroupTier(arousal);
    final arousalName = _getGroupBondTierName(arousalTier);
    final arousalColor = _getGroupTierColor(arousalTier);

    final needs = chatService.getTopUrgentNeedsForGroupCharacter(character, count: 2);
    final fixation = chatService.getFixationForGroupCharacter(character); // I see it's likely WIP - and I like where it going.

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emotion
            Row(
              children: [
                Text(
                  EmotionLabels.emoji[emotion] ?? '🎭',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  '${emotion[0].toUpperCase()}${emotion.substring(1)}${intensity.isNotEmpty ? ' ($intensity)' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _emotionColor(emotion),
                  ),
                ),
                if (isDirector)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.pause_circle_outline, size: 11, color: Colors.amberAccent),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Short-Term Bond (full 1:1 visual treatment using group affection)
            _buildGroupRealismRichRow(
              context: context,
              label: 'Short-Term Bond',
              value: affection,
              tier: bondTier,
              tierName: bondName,
              color: bondColor,
              icon: affection < 0 ? Icons.heart_broken : Icons.favorite,
            ),
            const SizedBox(height: 10),

            // Long-Term Bond (same data for groups, full visual so it looks complete)
            _buildGroupRealismRichRow(
              context: context,
              label: 'Long-Term Bond',
              value: affection,
              tier: bondTier,
              tierName: bondName,
              color: bondColor,
              icon: affection < 0 ? Icons.heart_broken_sharp : Icons.monitor_heart,
            ),
            const SizedBox(height: 10),

            // Trust (full style)
            _buildGroupRealismRichRow(
              context: context,
              label: 'Trust',
              value: trust,
              tier: trustTier,
              tierName: trustName,
              color: trustColor,
              icon: trust < 0 ? Icons.vpn_key_off : Icons.vpn_key,
              maxValue: 100,
            ),
            const SizedBox(height: 10),

            // Arousal (full style)
            _buildGroupRealismRichRow(
              context: context,
              label: 'Arousal',
              value: arousal,
              tier: arousalTier,
              tierName: arousalName,
              color: arousalColor,
              icon: Icons.local_fire_department,
              maxValue: 100,
            ),
            const SizedBox(height: 8),

            // Needs info button (only shown when Needs Simulation has actually run for this character)
            if (needs.isNotEmpty)
              Row(
                children: [
                  Text('Needs', style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _showGroupCharacterNeedsPopup(chatService, character),
                    borderRadius: BorderRadius.circular(10),
                    child: Tooltip(
                      message: 'View full needs details for ${character.name}',
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.info_outline, size: 14, color: AppColors.iconSecondary(context)),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    needs.map((n) => '${n.$1} ${n.$2.toStringAsFixed(0)}%').join(' · '),
                    style: const TextStyle(fontSize: 9, color: Colors.orangeAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showGroupCharacterNeedsPopup(ChatService chatService, CharacterCard character) {
    final needs = chatService.getNeedsForGroupCharacter(character);
    if (needs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active needs data for this character.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text('Needs — ${character.name}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: needs.entries.map((e) {
                final pct = (e.value as num).toDouble().clamp(0.0, 100.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(e.key, style: const TextStyle(fontSize: 12)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct / 100.0,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupFixationSmall(String fixation) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.psychology, size: 12, color: Colors.deepPurpleAccent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Fixated on: $fixation',
              style: const TextStyle(
                fontSize: 10, // slightly smaller than typical 1:1 fixation text
                color: Colors.deepPurpleAccent,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupSettingsDialog(ChatService chatService) {
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) => GroupSettingsDialog(
        chatService: chatService,
        groupRepo: groupRepo,
      ),
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

  void _showEvolutionDialog(BuildContext context, ChatService chat) {
    final character = chat.activeCharacter;
    if (character == null) return;
    final charName = character.name;
    final evolvedPersonality =
        chat.getEffectivePersonality ?? character.personality;
    final evolvedScenario = chat.getEffectiveScenario ?? character.scenario;

    final personalityController = TextEditingController(
      text: evolvedPersonality,
    );
    final scenarioController = TextEditingController(text: evolvedScenario);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                '$charName — Evolution',
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
                Text(
                  chat.characterEvolutionCount > 0
                      ? 'Evolved ${chat.characterEvolutionCount} time${chat.characterEvolutionCount > 1 ? "s" : ""}'
                      : 'Not yet evolved — personality will evolve as you chat',
                  style: TextStyle(
                    fontSize: 11,
                    color: chat.characterEvolutionCount > 0
                        ? Colors.tealAccent
                        : Colors.white38,
                  ),
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
                      character.personality,
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
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
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
                      character.scenario,
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
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
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
          if (chat.characterEvolutionCount > 0)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showResetEvolutionConfirmSidebar(context, chat);
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
                    final ok = await chat.triggerEvolutionNow();
                    Navigator.of(ctx).pop();
                    if (ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Character evolved!'),
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
              chat.updateEvolvedPersonality(personalityController.text);
              chat.updateEvolvedScenario(scenarioController.text);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade700,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showResetEvolutionConfirmSidebar(
    BuildContext context,
    ChatService chat,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Reset Character Evolution?'),
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
              chat.resetCharacterEvolution();
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
                    color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
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
                          color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                        ),
                      ),
                      if (evolvedP != null && evolvedP.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Evolved Personality',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
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
                              color: AppColors.resolve(context, Colors.tealAccent.withValues(alpha: 0.3), Colors.teal.shade200.withValues(alpha: 0.4)),
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
                            color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
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
                              color: AppColors.resolve(context, Colors.tealAccent.withValues(alpha: 0.3), Colors.teal.shade200.withValues(alpha: 0.4)),
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
                                    backgroundColor: AppColors.surfaceOf(context),
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
    ImageGenMode mode,
  ) async {
    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    final storage = Provider.of<StorageService>(context, listen: false);
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
    if (messages.isNotEmpty) {
      lastMessage = messages.last.displayText;
      recentMessages = messages.reversed
          .take(5)
          .map((m) => m.displayText)
          .where((m) => m.isNotEmpty)
          .toList()
          .reversed
          .toList();
    }

    // For custom prompt, show a text input dialog first
    String? customPrompt;
    if (mode == ImageGenMode.customPrompt) {
      final promptController = TextEditingController();
      customPrompt = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          title: const Row(
            children: [
              Icon(Icons.brush, color: Colors.purpleAccent),
              SizedBox(width: 12),
              Text(
                'Custom Image Prompt',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: AppTextField(
              controller: promptController,
              maxLines: 4,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Describe the image you want to generate...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF374151),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, promptController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
              ),
              child: const Text(
                'Generate',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (customPrompt == null || customPrompt.trim().isEmpty) return;
      customPrompt = customPrompt.trim();
    }

    if (!context.mounted) return;

    // Accept callback for avatar/background modes
    void Function(String path)? onAccept;
    if (mode == ImageGenMode.characterPortrait && character != null) {
      onAccept = (imagePath) async {
        final charRepo = Provider.of<CharacterRepository>(
          context,
          listen: false,
        );
        await charRepo.setCharacterImagePath(character, imagePath);

        // Highly likely redundant — updateCharacter() (called by
        // setCharacterImagePath) already writes V2 data via
        // V2CardService.saveCardAsPng().  Keeping for reference.
        //
        // try {
        //   final v2Service = V2CardService();
        //   final card = CharacterCard(
        //     name: character.name,
        //     description: character.description,
        //     personality: character.personality,
        //     scenario: character.scenario,
        //     firstMessage: character.firstMessage,
        //     mesExample: character.mesExample,
        //     systemPrompt: character.systemPrompt,
        //     postHistoryInstructions: character.postHistoryInstructions,
        //     alternateGreetings: character.alternateGreetings,
        //     tags: character.tags,
        //   );
        //   await v2Service.saveCardAsPng(card, imagePath, imagePath);
        //   debugPrint('Embedded V2 card data into avatar: $imagePath');
        // } catch (e) {
        //   debugPrint('Failed to embed V2 card data: $e');
        // }
      };
    } else if (mode == ImageGenMode.chatBackground) {
      onAccept = (path) {
        storage.setChatBackground(path);
      };
    } else if (mode == ImageGenMode.userAvatar) {
      onAccept = (path) {
        final updatedPersona = personaService.persona.copyWith(
          avatarPath: path,
        );
        personaService.updatePersona(updatedPersona);
      };
    }

    // Pass raw context to the dialog — it will use the LLM to craft the prompt
    ImageGenDialog.show(
      context,
      mode: mode,
      customPrompt: customPrompt,
      lastMessage: lastMessage,
      characterName: character?.name,
      characterDescription: character?.description,
      characterPersonality: character?.personality,
      scenario: character?.scenario,
      worldInfo: worldInfo,
      personaName: personaService.persona.name,
                  personaText: personaService.persona.persona,
      recentMessages: recentMessages,
      llmService: llmService,
      onAccept: onAccept,
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

        // ── Input bar ────────────────────────────────────────────────────
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resize handle — drag up/down to adjust input height
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onVerticalDragStart: (_) => _dragAccumulator = 0,
                onVerticalDragUpdate: (details) => _handleInputResize(details.delta.dy),
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
                        color: AppColors.resolve(context, Colors.white38, Colors.black38),
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
                border: Border(top: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.35))),
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
                        backgroundColor: AppColors.resolve(context, Colors.white24, Colors.black12),
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
                icon: Icon(Icons.folder_open, color: AppColors.iconSecondary(context)),
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
                    _showEvolutionDialog(context, chatService);
                  } else if (value == 'context') {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          ContextViewerDialog(chatService: chatService),
                    );
                  } else if (value == 'fork_group') {
                    _showForkToGroupDialog(context, chatService);
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
                  if (chatService.activeCharacter != null &&
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).characterEvolutionEnabled)
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
                  if (chatService.activeCharacter != null)
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
                          Text('Fork to Group Chat'),
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

              // Image Generation Menu
              Consumer<StorageService>(
                builder: (context, storage, _) {
                  if (!storage.imageGenEnabled) return const SizedBox.shrink();
                  return PopupMenuButton<ImageGenMode>(
                    icon: const Icon(
                      Icons.auto_awesome,
                      color: Colors.purpleAccent,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Generate Image',
                    onSelected: (mode) =>
                        _showImageGenDialog(context, chatService, mode),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: ImageGenMode.customPrompt,
                        child: Row(
                          children: [
                            Icon(
                              Icons.brush,
                              size: 20,
                              color: Colors.purpleAccent,
                            ),
                            SizedBox(width: 12),
                            Text('Custom Prompt'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ImageGenMode.visualizeScene,
                        child: Row(
                          children: [
                            Icon(
                              Icons.landscape,
                              size: 20,
                              color: Colors.green,
                            ),
                            SizedBox(width: 12),
                            Text('Visualize Scene'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ImageGenMode.fromLastMessage,
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: Colors.blueAccent,
                            ),
                            SizedBox(width: 12),
                            Text('From Last Message'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: ImageGenMode.characterPortrait,
                        child: Row(
                          children: [
                            Icon(Icons.face, size: 20, color: Colors.amber),
                            SizedBox(width: 12),
                            Text('Character Portrait'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ImageGenMode.chatBackground,
                        child: Row(
                          children: [
                            Icon(Icons.wallpaper, size: 20, color: Colors.teal),
                            SizedBox(width: 12),
                            Text('Chat Background'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ImageGenMode.userAvatar,
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 20, color: Colors.orange),
                            SizedBox(width: 12),
                            Text('User Avatar'),
                          ],
                        ),
                      ),
                    ],
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
                              _controller.selection =
                                  TextSelection.fromPosition(
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
                        sttService.isRecording ? Icons.stop_circle : Icons.mic,
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
                                    _controller.text = _controller.text.isEmpty
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
                      icon: const Icon(Icons.call, color: Colors.greenAccent),
                      onPressed: chatService.isGenerating || sttService.isBusy
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
                    icon: const Icon(Icons.group, color: Colors.purpleAccent),
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
                          color: chatService.observerMode
                              ? Colors.amberAccent
                              : Colors.blueAccent,
                        ),
                        onPressed: () {
                          if (_controller.text.isNotEmpty &&
                              !chatService.isGenerating) {
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
                    color: AppColors.resolve(context, Colors.white24, Colors.black12),
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

  Widget _buildRightSidebar(CharacterCard character, ChatService chatService) {
    final userName = Provider.of<UserPersonaService>(
      context,
      listen: false,
    ).persona.name;
    String replace(String text) {
      return text
          .replaceAll('{{char}}', character.name)
          .replaceAll('{{user}}', userName);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(left: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.35))),
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
              final hasAvatars = character.avatarImages != null &&
                  character.avatarImages!.isNotEmpty;

              File? expressionFile;
              String? expressionKey;
              String? expressionEmoji;

              if (isExpressionEnabled && hasAvatars && !chat.isEvaluatingRealism) {
                final avatar = chat.resolveExpressionAvatar(
                  character,
                  rerollIfSame: storage.expressionRerollSame,
                );
                if (avatar != null) {
                  final avatarDir = storage.characterAvatarDir(
                    character.name,
                  );
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
                      style: TextStyle(
                        fontSize: _sidebarWidth * 0.5,
                      ),
                    ),
                  );
                } else if (fallback == 'prime' && hasAvatars) {
                  // Show prime avatar
                  final primeAvatar = character.avatarImages!.where(
                    (a) => a.displayOrder + 1 == character.primeAvatarIndex,
                  ).isEmpty
                      ? character.avatarImages!.first
                      : character.avatarImages!.firstWhere(
                          (a) => a.displayOrder + 1 == character.primeAvatarIndex,
                        );
                  final avatarDir = storage.characterAvatarDir(character.name);
                  displayFile = File('${avatarDir.path}/${primeAvatar.filename}');
                  expressionKey = primeAvatar.id;
                } else {
                  // 'neutral' or default: show neutral avatar if available, else character image
                  if (hasAvatars) {
                    final neutralAvatar = character.avatarImages!.where(
                      (a) => a.label?.toLowerCase() == 'neutral',
                    ).toList();
                    if (neutralAvatar.isNotEmpty) {
                      final avatarDir = storage.characterAvatarDir(character.name);
                      displayFile =
                          File('${avatarDir.path}/${neutralAvatar.first.filename}');
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
                          color: AppColors.resolve(context, Colors.black26, Colors.black.withValues(alpha: 0.1)),
                          child: Icon(Icons.person, color: AppColors.iconSecondary(context), size: 64),
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
                            color: AppColors.resolve(context, Colors.black.withOpacity(0.7), Colors.black.withOpacity(0.45)),
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
              border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.35))),
            ),
            child: SizedBox(
              width: double.infinity,
              child: PopupMenuButton<String>(
                color: AppColors.surfaceContainerOf(context),
                elevation: 8,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                  side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.3)),
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
                    final result = await CharacterAvatarsDialog.show(
                      context: context,
                      character: character,
                      repository: repo,
                      storage: storage,
                    );
                    if (result == true) {
                      setState(() {});
                    }
                    break;
                  case 'ui':
                    showDialog(
                      context: context,
                      builder: (context) => UiSettingsDialog(character: character),
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
                  child: _SettingsMenuItem(
                    icon: Icons.edit_outlined,
                    label: 'Edit Character',
                  ),
                ),
                PopupMenuItem(
                  value: 'expressions',
                  child: _SettingsMenuItem(
                    icon: Icons.mood_outlined,
                    label: 'Expression Images',
                  ),
                ),
                PopupMenuItem(
                  value: 'ui',
                  child: _SettingsMenuItem(
                    icon: Icons.tune_outlined,
                    label: 'UI Settings',
                  ),
                ),
                PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'chat',
                  child: _SettingsMenuItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat Settings',
                  ),
                ),
                PopupMenuItem(
                  value: 'model',
                  child: _SettingsMenuItem(
                    icon: Icons.memory_outlined,
                    label: 'Model Settings',
                  ),
                ),
                PopupMenuItem(
                  value: 'tts',
                  child: _SettingsMenuItem(
                    icon: Icons.volume_up_outlined,
                    label: 'TTS Settings',
                  ),
                ),
              ],
                child: const Text(
                  'Settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
            ),
              ),
            ),

            Expanded(
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Author's Note ──
                _AuthorNoteSection(chatService: chatService),
                const SizedBox(height: 16),

                // ── RAG Memory ──
                _MemorySection(chatService: chatService),
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
                          color: AppColors.resolve(context, Colors.purpleAccent.withValues(alpha: 0.12), Colors.purple.shade50.withValues(alpha: 0.6)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.resolve(context, Colors.purpleAccent.withValues(alpha: 0.4), Colors.purple.shade200.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 16,
                              color: AppColors.resolve(context, Colors.purpleAccent, Colors.purple.shade700),
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
                                      color: AppColors.resolve(context, Colors.purpleAccent, Colors.purple.shade700),
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
                _RealismSection(chatService: chatService),
                const SizedBox(height: 8),

                // ── Chaos Mode ──
                Consumer<ChatService>(
                  builder: (context, chat, _) => _ChaosModeSection(
                    chat: chat,
                    onSpinRequested: () => _showChanceTimeOverlay(context),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Objective ──
                _ObjectiveSection(chatService: chatService),
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
                    return _CollapsibleSidebarSection(
                      icon: Icons.psychology_alt,
                      iconColor: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                      title: 'Character Evolution',
                      trailing: Text(
                        count > 0 ? 'Evolved $count×' : 'Not evolved',
                        style: TextStyle(
                          fontSize: 11,
                          color: count > 0 ? AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700) : AppColors.textTertiary(context),
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
                                    color: AppColors.resolve(context, Colors.tealAccent.withValues(alpha: 0.3), Colors.teal.shade200.withValues(alpha: 0.4)),
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
                                    color: AppColors.resolve(context, Colors.tealAccent.withValues(alpha: 0.3), Colors.teal.shade200.withValues(alpha: 0.4)),
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
                                  onPressed: () =>
                                      _showEvolutionDialog(context, chat),
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
                                      color: Colors.tealAccent.withOpacity(0.3),
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
                                      color: Colors.redAccent.withOpacity(0.3),
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
                _SummarySection(chatService: chatService),
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
                    return _SidebarSection(
                      title: 'Scenario',
                      content: replace(character.scenario),
                    );
                  },
                ),

                // ── Lorebook Triggers (bottom) ──
                const SizedBox(height: 16),
                _LorebookSection(character: character),

                // ── Description ──
                _SidebarSection(
                  title: 'Description',
                  content: replace(character.description),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sidebar showing all characters in a group.
  Widget _buildGroupSidebar(ChatService chatService) {
    final chars = chatService.groupCharacters;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(left: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Settings buttons ──
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.35))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const ChatSettingsDialog(),
                          );
                        },
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text(
                          'Chat',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const ModelSettingsDialog(),
                          );
                        },
                        icon: const Icon(Icons.memory, size: 16),
                        label: const Text(
                          'Model',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const TtsSettingsDialog(),
                          );
                        },
                        icon: const Icon(Icons.volume_up, size: 16),
                        label: const Text(
                          'TTS',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary(context),
                          side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showGroupSettingsDialog(chatService),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('Group Settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // ── Director Mode toggle ──
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
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
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
                  // Delay slider
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
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
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
                              onChanged: (val) => setState(() => _dragDirectorDelay = val),
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
          ),

          // ── Author's Note ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _AuthorNoteSection(chatService: chatService),
          ),

          // ── Summary ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _SummarySection(chatService: chatService),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Text(
                  'Characters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Tap a character to make them respond next',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context).withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: chars.length,
              itemBuilder: (context, index) {
                final ch = chars[index];
                final color = _groupCharacterColor(index);
                final isNext = chatService.nextCharacter?.name == ch.name;
                final evolutionCount = chatService.getEvolutionCountFor(ch);
                final canRemove = chars.length > 2 && !chatService.isGenerating;
                return GestureDetector(
                  onTap: chatService.isGenerating
                      ? null
                      : () => chatService.setNextCharacter(ch),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isNext
                          ? color.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isNext
                          ? Border.all(color: color.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: ListTile(
                      leading: chatService.isGroupRealismActive
                          ? Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _emotionColor(chatService.getEmotionForGroupCharacter(ch)),
                                  width: 2.5,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: color,
                                backgroundImage: ch.imagePath != null
                                    ? FileImage(_resolveCharImage(ch.imagePath!))
                                    : null,
                                child: ch.imagePath == null
                                    ? Text(
                                        ch.name[0],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                            )
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: color,
                              backgroundImage: ch.imagePath != null
                                  ? FileImage(_resolveCharImage(ch.imagePath!))
                                  : null,
                              child: ch.imagePath == null
                                  ? Text(
                                      ch.name[0],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              ch.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          if (Provider.of<StorageService>(
                                context,
                                listen: false,
                              ).characterEvolutionEnabled &&
                              evolutionCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.resolve(
                                  context,
                                  Colors.tealAccent.withValues(alpha: 0.15),
                                  Colors.teal.shade100.withValues(alpha: 0.5),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Evolved $evolutionCount\u00d7',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ch.description.length > 40
                                ? '${ch.description.substring(0, 40)}...'
                                : ch.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                          // Fixation under character summary (smaller text, per user request)
                          if (chatService.isGroupRealismActive)
                            () {
                              final fix = chatService.getFixationForGroupCharacter(ch);
                              return (fix != null && fix.isNotEmpty)
                                  ? _buildGroupFixationSmall(fix)
                                  : const SizedBox.shrink();
                            }(),
                          // Full realism UI per character (rich 1:1 style bars + needs info button)
                          if (chatService.isGroupRealismActive)
                            _buildGroupCharacterFullRealismUI(context, chatService, ch),
                          Wrap(
                            spacing: 4,
                            runSpacing: 0,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    _showVoicePickerForCharacter(ch),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 24),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  Icons.record_voice_over,
                                  size: 12,
                                  color: ch.ttsVoice != null
                                      ? Colors.amberAccent
                                      : Colors.white24,
                                ),
                                label: Text(
                                  ch.ttsVoice ?? 'Default voice',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: ch.ttsVoice != null
                                        ? Colors.amberAccent
                                        : Colors.white24,
                                  ),
                                ),
                              ),
                              if (Provider.of<StorageService>(
                                context,
                                listen: false,
                              ).characterEvolutionEnabled)
                                TextButton.icon(
                                  onPressed: chatService.isEvolvingCharacter
                                      ? null
                                      : () async {
                                          await chatService.triggerEvolutionNow(
                                            target: ch,
                                          );
                                        },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: Icon(
                                    Icons.psychology_alt,
                                    size: 12,
                                    color: Colors.tealAccent.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  label: Text(
                                    'Evolve',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.tealAccent.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isNext)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.purpleAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Next ▶',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (canRemove)
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Remove from group',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () async {
                                final groupRepo =
                                    Provider.of<GroupChatRepository>(
                                      context,
                                      listen: false,
                                    );
                                await chatService.removeCharacterFromGroup(
                                  ch,
                                  groupRepo,
                                );
                              },
                            ),
                        ],
                      ),
                      dense: true,
                    ),
                  ),
                );
              },
            ),
          ),
          // ── Add Character Button ──
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: chatService.isGenerating
                    ? null
                    : () =>
                          _showAddCharacterToGroupDialog(context, chatService),
                icon: const Icon(
                  Icons.person_add,
                  size: 16,
                  color: Colors.purpleAccent,
                ),
                label: const Text(
                  'Add Character',
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Colors.purpleAccent.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVoicePickerForCharacter(CharacterCard character) {
    final tts = Provider.of<TtsService>(context, listen: false);
    final voices = tts.activeVoices;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          title: Text(
            'Voice for ${character.name}',
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: 300,
            height: 400,
            child: voices.isEmpty
                ? const Center(
                    child: Text(
                      'No voices available.\nConfigure a TTS engine in TTS Settings first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.block, color: Colors.white38),
                        title: const Text(
                          'Use global default',
                          style: TextStyle(color: Colors.white70),
                        ),
                        selected: character.ttsVoice == null,
                        selectedTileColor: Colors.blueAccent.withValues(
                          alpha: 0.1,
                        ),
                        onTap: () {
                          Provider.of<CharacterRepository>(
                            ctx,
                            listen: false,
                          ).setTtsVoice(character, null);
                          Navigator.pop(ctx);
                          setState(() {});
                        },
                      ),
                      ...voices.map(
                        (v) => ListTile(
                          leading: Icon(
                            v.gender == 'Female'
                                ? Icons.female
                                : v.gender == 'Male'
                                ? Icons.male
                                : Icons.record_voice_over,
                            size: 18,
                            color: v.gender == 'Female'
                                ? Colors.pinkAccent
                                : v.gender == 'Male'
                                ? Colors.cyanAccent
                                : Colors.amberAccent,
                          ),
                          title: Text(
                            v.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            () {
                              final base = '${v.language} · ${v.gender}';
                              final currentEngine =
                                  Provider.of<StorageService>(ctx, listen: false)
                                      .ttsEngine;
                              if (v.engine != currentEngine) {
                                return '$base (incompatible with $currentEngine)';
                              }
                              return base;
                            }(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                          selected: character.ttsVoice == v.id,
                          selectedTileColor: Colors.blueAccent.withValues(
                            alpha: 0.1,
                          ),
                          onTap: () {
                            Provider.of<CharacterRepository>(
                              ctx,
                              listen: false,
                            ).setTtsVoice(character, v.id);
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// Show dialog to fork current 1:1 chat into a group chat.
  void _showForkToGroupDialog(BuildContext context, ChatService chatService) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final currentCharId = chatService.activeCharacter != null
        ? (chatService.activeCharacter!.imagePath != null
              ? p.basenameWithoutExtension(
                  chatService.activeCharacter!.imagePath!,
                )
              : chatService.activeCharacter!.name
                    .replaceAll(RegExp(r'[^\w\s]'), '')
                    .replaceAll(' ', '_'))
        : '';

    // Get all characters except the current one
    final available = charRepo.characters.where((c) {
      final id = c.imagePath != null
          ? p.basenameWithoutExtension(c.imagePath!)
          : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      return id != currentCharId;
    }).toList();

    final selected = <CharacterCard>{};
    final nameController = TextEditingController(
      text: chatService.activeCharacter?.name ?? 'Group',
    );
    final scenarioController = TextEditingController();
    var turnOrder = TurnOrder.roundRobin;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.purpleAccent, width: 0.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.group_add, color: Colors.purpleAccent),
              SizedBox(width: 10),
              Text(
                'Fork to Group Chat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            height: 450,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.purpleAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: scenarioController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Scenario (optional)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Set the scene for the group conversation...',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.purpleAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Turn Order:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Round Robin'),
                      selected: turnOrder == TurnOrder.roundRobin,
                      selectedColor: Colors.purpleAccent,
                      onSelected: (_) => setDialogState(
                        () => turnOrder = TurnOrder.roundRobin,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Random'),
                      selected: turnOrder == TurnOrder.random,
                      selectedColor: Colors.purpleAccent,
                      onSelected: (_) =>
                          setDialogState(() => turnOrder = TurnOrder.random),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Select characters to add (${selected.length} selected):',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: available.isEmpty
                      ? const Center(
                          child: Text(
                            'No other characters available.\nImport or create characters first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          itemCount: available.length,
                          itemBuilder: (context, index) {
                            final ch = available[index];
                            final isSelected = selected.contains(ch);
                            return CheckboxListTile(
                              value: isSelected,
                              activeColor: Colors.purpleAccent,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selected.add(ch);
                                  } else {
                                    selected.remove(ch);
                                  }
                                  // Update group name
                                  final names = [
                                    chatService.activeCharacter!.name,
                                    ...selected.map((c) => c.name),
                                  ];
                                  nameController.text = names.join(' & ');
                                });
                              },
                              secondary: CircleAvatar(
                                radius: 18,
                                backgroundImage: ch.imagePath != null
                                    ? FileImage(
                                        _resolveCharImage(ch.imagePath!),
                                      )
                                    : null,
                                child: ch.imagePath == null
                                    ? Text(ch.name[0])
                                    : null,
                              ),
                              title: Text(
                                ch.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                ch.description.length > 50
                                    ? '${ch.description.substring(0, 50)}...'
                                    : ch.description,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white38,
                                ),
                              ),
                              dense: true,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.call_split),
              label: const Text('Fork'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final groupRepo = Provider.of<GroupChatRepository>(
                        context,
                        listen: false,
                      );
                      final group = await chatService.forkToGroupChat(
                        selected.toList(),
                        groupRepo,
                        groupName: nameController.text.trim(),
                        scenario: scenarioController.text.trim(),
                        turnOrder: turnOrder,
                      );
                      if (group != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Group "${group.name}" created from fork!',
                            ),
                            backgroundColor: Colors.purpleAccent.shade700,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Show dialog to add a character to the active group chat.
  void _showAddCharacterToGroupDialog(
    BuildContext context,
    ChatService chatService,
  ) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final currentIds = chatService.activeGroup?.characterIds ?? [];

    // Get characters not already in the group
    final available = charRepo.characters.where((c) {
      final id = c.imagePath != null
          ? p.basenameWithoutExtension(c.imagePath!)
          : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      return !currentIds.contains(id);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.purpleAccent, width: 0.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Colors.purpleAccent),
            SizedBox(width: 10),
            Text(
              'Add Character',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          height: 350,
          child: available.isEmpty
              ? const Center(
                  child: Text(
                    'All characters are already in this group.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (context, index) {
                    final ch = available[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundImage: ch.imagePath != null
                            ? FileImage(_resolveCharImage(ch.imagePath!))
                            : null,
                        child: ch.imagePath == null ? Text(ch.name[0]) : null,
                      ),
                      title: Text(
                        ch.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        ch.description.length > 50
                            ? '${ch.description.substring(0, 50)}...'
                            : ch.description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final groupRepo = Provider.of<GroupChatRepository>(
                          context,
                          listen: false,
                        );
                        final success = await chatService.addCharacterToGroup(
                          ch,
                          groupRepo,
                        );
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${ch.name} added to group!'),
                              backgroundColor: Colors.purpleAccent.shade700,
                            ),
                          );
                        }
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hoverColor: Colors.white10,
                      dense: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final File? characterImage;
  final int index;
  final Color? senderColor;
  final bool? externalImagesAllowed;
  final Future<bool> Function()? onRequestImagePermission;
  final CharacterCard? character;
  final ChatService? chatService;

  const _MessageBubble({
     required this.message,
     this.characterImage,
     required this.index,
     this.senderColor,
     this.externalImagesAllowed,
     this.onRequestImagePermission,
     this.character,
     this.chatService,
   });

   @override
   State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _thoughtExpanded = false;

  ChatMessage get message => widget.message;
  File? get characterImage => widget.characterImage;
  int get index => widget.index;
  CharacterCard? get character => widget.character;

  @override
  Widget build(BuildContext context) {
    final isDirectorNote = message.characterId == '__director__';
    final isChanceTimeNarration =
        message.activeMetadata?['is_chance_time_narration'] == true;
     final bubbleOpacity = Provider.of<StorageService>(context).bubbleOpacity;
     final storage = Provider.of<StorageService>(context);

     // Chance Time narrations get a special centered banner
    if (isChanceTimeNarration) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              const Color(0xFFFFD166).withValues(alpha: 0.12),
              const Color(0xFFF59E0B).withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.resolve(
                context,
                const Color(0xFFFFD166).withValues(alpha: 0.35),
                const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎰', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.text
                      .replaceAll('[🎰 CHANCE TIME! ', '')
                      .replaceAll(']', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.resolve(context, const Color(0xFFFFD166), const Color(0xFFB45309)),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isDirectorNote
            ? MainAxisAlignment.center
            : (message.isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start),
        children: [
          if (!message.isUser && !isDirectorNote)
            CircleAvatar(
              backgroundImage: characterImage != null
                  ? FileImage(characterImage!)
                  : null,
              radius: 16,
              child: characterImage == null ? const Icon(Icons.person) : null,
            ),
          if (!message.isUser && !isDirectorNote) const SizedBox(width: 12),

          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                  color: isDirectorNote
                      ? AppColors.resolve(
                          context,
                          Colors.amberAccent.withValues(alpha: 0.1 * bubbleOpacity),
                          const Color(0xFFD97706).withValues(alpha: 0.12 * bubbleOpacity),
                        )
                      : message.isUser
                      ? storage.getUserBubbleColor(character).withValues(alpha: bubbleOpacity)
                      : storage.getAiBubbleColor(character).withValues(alpha: bubbleOpacity),
                 borderRadius: BorderRadius.only(
                   topLeft: const Radius.circular(12),
                   topRight: const Radius.circular(12),
                   bottomLeft: message.isUser && !isDirectorNote
                       ? const Radius.circular(12)
                       : Radius.zero,
                   bottomRight: message.isUser && !isDirectorNote
                       ? Radius.zero
                       : const Radius.circular(12),
                 ),
                 border: isDirectorNote
                     ? Border.all(
                         color: AppColors.resolve(
                           context,
                           Colors.amberAccent.withValues(alpha: 0.3),
                           const Color(0xFFD97706).withValues(alpha: 0.35),
                         ),
                       )
                     : null,
               ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDirectorNote) ...[
                        Icon(
                          Icons.movie_creation,
                          size: 14,
                          color: AppColors.resolve(context, Colors.amberAccent, const Color(0xFFD97706)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Director',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.resolve(context, Colors.amberAccent, const Color(0xFFD97706)),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const Spacer(),
                      ] else if (!message.isUser) ...[
                        Builder(
                          builder: (context) {
                            final chatService = Provider.of<ChatService>(
                              context,
                              listen: false,
                            );
                             final nameWidget = Text(
                               message.sender,
                               style: TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 12,
                                 color: widget.senderColor ?? storage.getDialogueColor(character),
                               ),
                             );
                            if (chatService.isGroupMode) {
                              return GestureDetector(
                                onTap: () {
                                  final ch = chatService.groupCharacters
                                      .where((c) => c.name == message.sender)
                                      .firstOrNull;
                                  if (ch != null) {
                                    chatService.setNextCharacter(ch);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${message.sender} will respond next',
                                        ),
                                        duration: const Duration(seconds: 1),
                                        backgroundColor:
                                            widget.senderColor ??
                                            Colors.blueAccent,
                                      ),
                                    );
                                  }
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: nameWidget,
                                ),
                              );
                            }
                            return nameWidget;
                          },
                        ),
                        const Spacer(),
                      ],
                      // TTS speaker button
                      if (!message.isUser &&
                          message.sender != 'System' &&
                          !isDirectorNote)
                        Consumer2<TtsService, StorageService>(
                          builder: (context, tts, storage, _) {
                            if (!storage.ttsEnabled) {
                              return const SizedBox.shrink();
                            }
                            final msgId = 'msg_${widget.index}';
                            final isThisMsg = tts.currentMessageId == msgId;
                            final isGeneratingThis =
                                isThisMsg && tts.isGenerating;
                            final isSpeakingThis =
                                isThisMsg &&
                                tts.isSpeaking &&
                                !tts.isGenerating;

                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: isGeneratingThis
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => tts.stop(),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.stop_circle,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  value:
                                                      tts.generationProgress > 0
                                                      ? tts.generationProgress
                                                      : null,
                                                  strokeWidth: 2,
                                                  color: Colors.blueAccent,
                                                ),
                                              ),
                                              if (tts.generationProgress > 0)
                                                Text(
                                                  '${(tts.generationProgress * 100).toInt()}',
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 7,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        isSpeakingThis
                                            ? Icons.stop_circle
                                            : Icons.volume_up,
                                        size: 16,
                                        color: isSpeakingThis
                                            ? Colors.orangeAccent
                                            : Colors.white38,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: isSpeakingThis
                                          ? 'Stop speaking'
                                          : 'Speak message',
                                      onPressed: () {
                                        if (isSpeakingThis) {
                                          tts.stop();
                                        } else {
                                          final chatService =
                                              Provider.of<ChatService>(
                                                context,
                                                listen: false,
                                              );
                                          String? voiceKey;
                                          if (chatService.activeGroup != null) {
                                            final charMatch = chatService
                                                .groupCharacters
                                                .where(
                                                  (c) =>
                                                      c.name == message.sender,
                                                )
                                                .firstOrNull;
                                            voiceKey = charMatch?.ttsVoice;
                                          } else {
                                            voiceKey = chatService
                                                .activeCharacter
                                                ?.ttsVoice;
                                          }
                                          tts.speak(
                                            message.displayText,
                                            voiceKey: voiceKey,
                                            messageId: msgId,
                                          );
                                        }
                                      },
                                    ),
                            );
                          },
                        ),
                      if (message.sender != 'System')
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: Colors.white38,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Edit message',
                          onPressed: () => _showEditDialog(context, index),
                        ),
                      if (message.sender != 'System') const SizedBox(width: 8),
                      if (message.sender != 'System')
                        IconButton(
                          icon: const Icon(
                            Icons.call_split,
                            size: 16,
                            color: Colors.white38,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Fork from here',
                          onPressed: () =>
                              _showForkConfirmation(context, index),
                        ),
                      if (message.sender != 'System') const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.white38,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            _showDeleteConfirmation(context, index),
                      ),
                    ],
                  ),
                  if (!message.isUser) const SizedBox(height: 4),
                  // Collapsible Thought chip
                  if (!message.isUser && message.hasThinking)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _thoughtExpanded = !_thoughtExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _thoughtExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 20,
                              color: Colors.white54,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A4A5A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Thought',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Expanded thinking details
                  if (!message.isUser &&
                      message.hasThinking &&
                      _thoughtExpanded)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, left: 20),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A3A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.thinkingDurationMs > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Thought for ${(message.thinkingDurationMs / 1000).toStringAsFixed(1)}s',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.tealAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (message.thinkingContent != null)
                            Text(
                              message.thinkingContent!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Live thinking timer
                  if (!message.isUser &&
                      message.thinkingStartTime != null &&
                      message.thinkingDurationMs == 0)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        if (!chatService.isGenerating) {
                          return const SizedBox.shrink();
                        }
                        final elapsed =
                            DateTime.now().millisecondsSinceEpoch -
                            message.thinkingStartTime!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.tealAccent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Thinking ${(elapsed / 1000).toStringAsFixed(0)}s...',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white38,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    _StyledChatMessage(
                      text: message.displayText,
                      isUser: message.isUser,
                      externalImagesAllowed: widget.externalImagesAllowed,
                      onRequestImagePermission: widget.onRequestImagePermission,
                      character: widget.character ?? widget.chatService?.activeCharacter,
                    ),
                  if (message.activeMetadata != null)
                    _buildRealismIndicator(message.activeMetadata!),
                  // Swipe arrows for alternate greetings on first message
                  if (index == 0 && !message.isUser)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final character = chatService.activeCharacter;
                        if (character == null) return const SizedBox.shrink();
                        final allGreetings = character.allGreetings;
                        if (allGreetings.length <= 1) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              InkWell(
                                onTap: () => chatService.cycleGreeting(-1),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.chevron_left,
                                    size: 20,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${chatService.greetingIndex + 1}/${allGreetings.length}',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => chatService.cycleGreeting(1),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  // Action buttons: regen, continue, swipe arrows
                  if (!message.isUser && message.sender != 'System')
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final isLastBotMessage =
                            index == chatService.messages.length - 1 &&
                            !chatService.isGenerating;
                        final hasSwipes = message.swipes.length > 1;

                        // Nothing to show if not last message and no swipes
                        if (!isLastBotMessage && !hasSwipes) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Regen button — last bot message only
                              if (isLastBotMessage) ...[
                                Tooltip(
                                  message: 'Regenerate',
                                  child: InkWell(
                                    onTap: () =>
                                        chatService.regenerateLastMessage(),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.refresh,
                                        size: 20,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Continue button
                                Tooltip(
                                  message: 'Continue generation',
                                  child: InkWell(
                                    onTap: () =>
                                        chatService.continueGeneration(),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.arrow_downward,
                                        size: 20,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                                if (hasSwipes) const SizedBox(width: 12),
                              ],
                              // Swipe arrows — only when multiple swipes exist
                              if (hasSwipes) ...[
                                InkWell(
                                  onTap: () =>
                                      chatService.swipeMessage(index, -1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.chevron_left,
                                      size: 20,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${message.swipeIndex + 1}/${message.swipes.length}',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () =>
                                      chatService.swipeMessage(index, 1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  // Suggest actions button + action pills (last bot message only)
                  if (!message.isUser && message.sender != 'System')
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final isLast =
                            index == chatService.messages.length - 1 &&
                            !chatService.isGenerating;
                        if (!isLast) return const SizedBox.shrink();

                        final actions = chatService.suggestedActions;
                        final isGenerating = chatService.isGeneratingActions;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "Suggest actions" button
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: InkWell(
                                onTap: isGenerating
                                    ? null
                                    : () => chatService.generateActions(),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isGenerating)
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Colors.white38,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.lightbulb_outline,
                                          size: 13,
                                          color: Colors.white30,
                                        ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isGenerating
                                            ? 'Thinking...'
                                            : 'Suggest actions',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white30,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Action pills
                            if (actions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: actions.map((action) {
                                    return InkWell(
                                      onTap: () =>
                                          chatService.sendMessage(action),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white12,
                                          ),
                                        ),
                                        child: Text(
                                          action,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          if (message.isUser) const SizedBox(width: 12),
          if (message.isUser)
            Consumer<UserPersonaService>(
              builder: (context, service, _) {
                final persona = service.personas
                    .where((p) => p.name == message.sender)
                    .firstOrNull;
                if (persona?.avatarPath != null) {
                  return CircleAvatar(
                    backgroundImage: FileImage(File(persona!.avatarPath!)),
                    radius: 16,
                  );
                }
                return const CircleAvatar(
                  backgroundColor: Colors.purple,
                  radius: 16,
                  child: Icon(Icons.person, color: Colors.white),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Delete Message'),
        content: const Text(
          'This can\'t be undone. Are you sure you want to delete this message?',
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
              chatService.deleteMessage(index);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showForkConfirmation(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Row(
          children: const [
            Icon(Icons.call_split, color: Colors.blueAccent, size: 22),
            SizedBox(width: 8),
            Text('Fork Conversation'),
          ],
        ),
        content: Text(
          'Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              chatService.forkFromMessage(index);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Conversation forked! You are now on the new branch.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.call_split, size: 18),
            label: const Text('Fork'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildRealismIndicator(Map<String, dynamic> metadata) {
    final bondDelta = metadata['bond_delta'] as int? ?? 0;
    final emotionLabel = metadata['emotion_label'] as String? ?? '';
    final arousalDelta = metadata['arousal_delta'] as int? ?? 0;
    final trustDelta = metadata['trust_delta'] as int? ?? 0;
    final bondReason = metadata['bond_reason'] as String? ?? '';
    final trustReason = metadata['trust_reason'] as String? ?? '';
    final timeSkipTo = metadata['time_skip_to'] as String? ?? '';
    final chanceTimeEvent = metadata['chance_time_event'] as String? ?? '';
    final timeReversal = metadata['time_reversal'] as bool? ?? false;

    if (bondDelta == 0 &&
        emotionLabel.isEmpty &&
        arousalDelta == 0 &&
        trustDelta == 0 &&
        timeSkipTo.isEmpty &&
        chanceTimeEvent.isEmpty &&
        !timeReversal) {
      return const SizedBox.shrink();
    }

    Widget maybeTooltip(Widget child, String tip) {
      if (tip.isEmpty) return child;
      return Tooltip(
        message: tip,
        preferBelow: false,
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );
    }

    final chips = <Widget>[];

    // ── Needs Simulation Chips (deltas + reasons) — built into a separate list
    // so we can render them on their own row underneath the classic realism chips.
    final needsDeltas = metadata['needs_deltas'] as Map<String, dynamic>?;
    final List<Widget> needsChipList = [];

    if (needsDeltas != null && needsDeltas.isNotEmpty) {
      needsDeltas.forEach((need, data) {
        final delta = (data is Map) ? (data['delta'] as int? ?? 0) : 0;
        final reason = (data is Map) ? (data['reason'] as String? ?? '') : '';

        if (delta == 0) return;

        IconData icon;
        Color color;
        String label = need[0].toUpperCase() + need.substring(1);

        switch (need) {
          case 'hunger':      icon = Icons.restaurant;     color = Colors.orangeAccent; break;
          case 'bladder':     icon = Icons.water_drop;     color = Colors.lightBlueAccent; break;
          case 'energy':      icon = Icons.bolt;           color = Colors.amberAccent; break;
          case 'social':      icon = Icons.people;         color = Colors.pinkAccent; break;
          case 'fun':         icon = Icons.celebration;    color = Colors.deepPurpleAccent; break;
          case 'hygiene':     icon = Icons.shower;         color = Colors.cyanAccent; break;
          case 'comfort':     icon = Icons.chair;          color = Colors.greenAccent; break;
          default:            icon = Icons.circle;         color = Colors.grey;
        }

        final chip = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              '$label ${delta > 0 ? '+$delta' : '$delta'}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 10, color: Colors.white38),
            ],
          ],
        );

        needsChipList.add(maybeTooltip(chip, reason));
      });
    }

    if (bondDelta != 0) {
      final chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bondDelta > 0 ? Icons.favorite : Icons.heart_broken,
            size: 11,
            color: bondDelta > 0 ? Colors.pinkAccent : Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Text(
            'Bond: ${bondDelta > 0 ? '+$bondDelta' : '$bondDelta'}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: bondDelta > 0 ? Colors.pinkAccent : Colors.redAccent,
            ),
          ),
          if (bondReason.isNotEmpty) ...[
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, size: 10, color: Colors.white38),
          ],
        ],
      );
      chips.add(maybeTooltip(chip, bondReason));
    }

    if (emotionLabel.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology, size: 11, color: Colors.purpleAccent),
            const SizedBox(width: 4),
            Text(
              'Mood: $emotionLabel',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.purpleAccent,
              ),
            ),
          ],
        ),
      );
    }

    if (arousalDelta != 0) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              arousalDelta > 0 ? Icons.local_fire_department : Icons.ac_unit,
              size: 11,
              color: arousalDelta > 0
                  ? Colors.deepOrangeAccent
                  : Colors.lightBlueAccent,
            ),
            const SizedBox(width: 4),
            Text(
              'Lust: ${arousalDelta > 0 ? '+$arousalDelta' : '$arousalDelta'}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: arousalDelta > 0
                    ? Colors.deepOrangeAccent
                    : Colors.lightBlueAccent,
              ),
            ),
          ],
        ),
      );
    }

    if (trustDelta != 0) {
      final chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            trustDelta > 0 ? Icons.handshake : Icons.gavel,
            size: 11,
            color: trustDelta > 0 ? Colors.blueAccent : Colors.deepPurpleAccent,
          ),
          const SizedBox(width: 4),
          Text(
            'Trust: ${trustDelta > 0 ? '+$trustDelta' : '$trustDelta'}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: trustDelta > 0
                  ? Colors.blueAccent
                  : Colors.deepPurpleAccent,
            ),
          ),
          if (trustReason.isNotEmpty) ...[
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, size: 10, color: Colors.white38),
          ],
        ],
      );
      chips.add(maybeTooltip(chip, trustReason));
    }

    // Time reversal chip
    if (timeReversal) {
      chips.add(
        Tooltip(
          message: 'Time is going backwards?!',
          preferBelow: false,
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '😵‍💫',
                style: TextStyle(fontSize: 11),
              ), // Dizzy face with spirals
              const SizedBox(width: 4),
              const Text(
                'Time Reversal',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.cyanAccent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (timeSkipTo.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward, size: 11, color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              'Time skip: $timeSkipTo',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.amber,
              ),
            ),
          ],
        ),
      );
    }

    if (chanceTimeEvent.isNotEmpty) {
      chips.add(
        Tooltip(
          message: chanceTimeEvent,
          preferBelow: false,
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎰', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  'Chance Time: ${chanceTimeEvent.length > 30 ? chanceTimeEvent.substring(0, 30) + '…' : chanceTimeEvent}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFD166),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final classicRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: chips.expand((c) => [c, const SizedBox(width: 10)]).toList()
        ..removeLast(),
    );

    if (needsChipList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10),
          ),
          child: classicRow,
        ),
      );
    }

    // Two-row layout: Classic Realism chips on top, Needs chips on a dedicated second row below.
    // This prevents the single-row clutter the user was worried about.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Classic Realism (Bond, Trust, Lust, Mood, Time, Chance Time, etc.)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            child: classicRow,
          ),

          const SizedBox(height: 4),

          // Row 2: Needs Simulation deltas (Energy, Hunger, Bladder, etc.)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.07),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: needsChipList.expand((c) => [c, const SizedBox(width: 8)]).toList()
                ..removeLast(),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final controller = TextEditingController(text: message.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Edit Message'),
        content: SizedBox(
          width: 500,
          child: AppTextField(
            controller: controller,
            maxLines: 10,
            minLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF374151),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
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
              chatService.editMessage(index, controller.text);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
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

final _markdownImageRegex = RegExp(r'!\[([^\]]*)\]\((https?://[^)]+)\)');

class _StyledChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool? externalImagesAllowed;
  final Future<bool> Function()? onRequestImagePermission;
  final CharacterCard? character;

  const _StyledChatMessage({
    required this.text,
    required this.isUser,
    this.externalImagesAllowed,
    this.onRequestImagePermission,
    this.character,
  });

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final scaledSize = 14.0 * storageService.textScale;

    // Check for markdown images
    final imageMatches = _markdownImageRegex.allMatches(text).toList();
    if (imageMatches.isEmpty) {
      // No images — use existing fast path
      return _buildStyledText(context, text, scaledSize, character);
    }

    // Split text into segments: [text, image, text, image, text]
    final widgets = <Widget>[];
    int lastEnd = 0;

    for (final match in imageMatches) {
      // Text before this image
      if (match.start > lastEnd) {
        final textBefore = text.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.add(_buildStyledText(context, textBefore, scaledSize, character));
        }
      }

      final altText = match.group(1) ?? '';
      final imageUrl = match.group(2)!;

      // Image placeholder or loaded image
      widgets.add(
        _ExternalImageWidget(
          url: imageUrl,
          altText: altText,
          allowed: externalImagesAllowed,
          onRequestPermission: onRequestImagePermission,
        ),
      );

      lastEnd = match.end;
    }

    // Remaining text after last image
    if (lastEnd < text.length) {
      final textAfter = text.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.add(_buildStyledText(context, textAfter, scaledSize, character));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildStyledText(BuildContext context, String segment, double scaledSize, CharacterCard? character) {
    final storageService = Provider.of<StorageService>(context);
    final fontFamily = storageService.getChatFontFamily(character);
    final textColor = isUser
        ? storageService.getUserTextColor(character)
        : storageService.getAiTextColor(character);
    final plainStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(
        color: textColor,
        fontSize: scaledSize,
      ),
    );
    final dialogueStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(
        color: storageService.getDialogueColor(character),
        fontWeight: FontWeight.w500,
        fontSize: scaledSize,
      ),
    );
    final actionStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(
        color: storageService.getActionColor(character),
        fontSize: scaledSize,
      ),
    );

    final quoteRegex = RegExp(r'"[^"]*"');
    final asteriskRegex = RegExp(r'\*[^*]+\*', dotAll: true);

    List<TextSpan> spans = [];

    // Pass 1: Split on quotes (outer container — quotes always win)
    int lastEnd = 0;
    for (final match in quoteRegex.allMatches(segment)) {
      // Non-quoted text before this quote — parse for actions
      if (match.start > lastEnd) {
        _addColorizedActions(
          spans,
          segment.substring(lastEnd, match.start),
          plainStyle,
          actionStyle,
          asteriskRegex,
        );
      }
      // Quoted text — all dialogue style (yellow), even if it contains *actions*
      spans.add(TextSpan(text: match.group(0)!, style: dialogueStyle));
      lastEnd = match.end;
    }

    // Remaining non-quoted text after last quote — parse for actions
    if (lastEnd < segment.length) {
      _addColorizedActions(
        spans,
        segment.substring(lastEnd),
        plainStyle,
        actionStyle,
        asteriskRegex,
      );
    }

    if (spans.isEmpty) {
      return SelectionArea(
        child: Text(
          segment,
          style: _applyGoogleFont(
            fontFamily,
            TextStyle(
              color: textColor,
              fontSize: scaledSize,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return SelectionArea(
      child: RichText(
        text: TextSpan(
          style: _applyGoogleFont(
            fontFamily,
            TextStyle(
              color: textColor,
              fontSize: scaledSize,
              height: 1.4,
            ),
          ),
          children: spans,
        ),
      ),
    );
  }

  /// Parse *action* blocks within a non-quoted text segment.
  void _addColorizedActions(
    List<TextSpan> spans,
    String segment,
    TextStyle plainStyle,
    TextStyle actionStyle,
    RegExp asteriskRegex,
  ) {
    int lastEnd = 0;
    for (final match in asteriskRegex.allMatches(segment)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: segment.substring(lastEnd, match.start),
            style: plainStyle,
          ),
        );
      }
      spans.add(TextSpan(text: match.group(0)!, style: actionStyle));
      lastEnd = match.end;
    }
    if (lastEnd < segment.length) {
      spans.add(TextSpan(text: segment.substring(lastEnd), style: plainStyle));
    }
  }
}

/// Renders an external image with consent gating.
class _ExternalImageWidget extends StatefulWidget {
  final String url;
  final String altText;
  final bool? allowed;
  final Future<bool> Function()? onRequestPermission;

  const _ExternalImageWidget({
    required this.url,
    required this.altText,
    required this.allowed,
    required this.onRequestPermission,
  });

  @override
  State<_ExternalImageWidget> createState() => _ExternalImageWidgetState();
}

class _ExternalImageWidgetState extends State<_ExternalImageWidget> {
  // ignore: unused_field
  bool _loading = false; // Kept for potential future loading UI in external image widget
  File? _cachedFile;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.allowed == null && widget.onRequestPermission != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onRequestPermission!.call();
        if (mounted) setState(() => _loading = false);
      });
    } else if (widget.allowed == true) {
      _loadCachedImage();
    }
  }

  @override
  void didUpdateWidget(covariant _ExternalImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allowed == true &&
        oldWidget.allowed != true &&
        _cachedFile == null) {
      _loadCachedImage();
    }
  }

  Future<void> _loadCachedImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/image_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final hash = widget.url.hashCode.toRadixString(16);
      final uri = Uri.tryParse(widget.url);
      final ext = (uri?.pathSegments.isNotEmpty == true)
          ? '.${uri!.pathSegments.last.split('.').last.split('?').first}'
          : '.png';
      final file = File('${cacheDir.path}/$hash$ext');

      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _cachedFile = file;
            _loading = false;
          });
        }
        return;
      }

      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(widget.url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          await file.writeAsBytes(bytes);
          if (mounted) {
            setState(() {
              _cachedFile = file;
              _loading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _error = 'HTTP ${response.statusCode}';
              _loading = false;
            });
          }
        }
      } finally {
        httpClient.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Already allowed — show image
    if (widget.allowed == true) {
      if (_cachedFile != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 600),
              child: Image.file(
                _cachedFile!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (_error != null) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        width: 300,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.blueAccent,
                strokeWidth: 2,
              ),
              SizedBox(height: 8),
              Text(
                'Loading image...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    // Denied — show subtle blocked indicator
    if (widget.allowed == false) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 14,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 6),
            Text(
              'Image blocked',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Waiting for consent dialog — show loading placeholder
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.orangeAccent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'External image detected...',
              style: TextStyle(
                color: Colors.orangeAccent.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSection extends StatefulWidget {
  final String title;
  final String content;
  const _SidebarSection({
    required this.title,
    required this.content,
  });

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: Text(
              widget.content,
              style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

/// A generic collapsible sidebar section with icon, colored title, trailing badge, and arbitrary child.
class _CollapsibleSidebarSection extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  const _CollapsibleSidebarSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleSidebarSection> createState() =>
      _CollapsibleSidebarSectionState();
}

class _CollapsibleSidebarSectionState
    extends State<_CollapsibleSidebarSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: widget.iconColor),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.iconColor,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (widget.trailing != null) widget.trailing!,
                const SizedBox(width: 6),
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[const SizedBox(height: 8), widget.child],
      ],
    );
  }
}

class _LorebookSection extends StatefulWidget {
  final CharacterCard character;
  const _LorebookSection({required this.character});

  @override
  State<_LorebookSection> createState() => _LorebookSectionState();
}

class _LorebookSectionState extends State<_LorebookSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Lorebook Triggers',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child:
                widget.character.lorebook != null &&
                    widget.character.lorebook!.entries.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.character.lorebook!.entries
                          .where((e) => e.enabled)
                          .isEmpty)
                        Text(
                          'No enabled entries.',
                          style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
                        ),

                      ...widget.character.lorebook!.entries
                          .where((e) => e.enabled)
                          .map((entry) {
                            Color dotColor = AppColors.resolve(
                              context,
                              Colors.redAccent,
                              Colors.red.shade700,
                            );
                            if (entry.constant) {
                              dotColor = AppColors.resolve(
                                context,
                                Colors.blueAccent,
                                Colors.blue.shade700,
                              );
                            } else if (entry.isTriggered) {
                              dotColor = AppColors.resolve(
                                context,
                                Colors.greenAccent,
                                Colors.green.shade700,
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppColors.resolve(
                                        context,
                                        dotColor,
                                        dotColor.withValues(alpha: 0.85),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key.isEmpty && entry.constant
                                          ? 'Always Active'
                                          : entry.displayName,
                                      style: TextStyle(
                                        color: (entry.isTriggered || entry.constant)
                                            ? AppColors.textPrimary(context)
                                            : AppColors.textSecondary(context),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                    ],
                  )
                : Text(
                    'No lorebook entries.',
                    style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
                  ),
          ),
        ],
      ],
    );
  }
}

class _AuthorNoteSection extends StatefulWidget {
  final ChatService chatService;
  const _AuthorNoteSection({required this.chatService});

  @override
  State<_AuthorNoteSection> createState() => _AuthorNoteSectionState();
}

class _AuthorNoteSectionState extends State<_AuthorNoteSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.chatService.authorNote);
  }

  @override
  void didUpdateWidget(covariant _AuthorNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.chatService.authorNote) {
      _controller.text = widget.chatService.authorNote;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.chatService.activeGroup != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sticky_note_2_outlined,
              size: 16,
              color: Colors.amber,
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: isGroup
                  ? 'Group Author\'s Note — injected for every character in the group.\n'
                    'For per-character author\'s notes, go to Group Settings → Prompt Engineering.'
                  : 'Author\'s Note — injected into the character\'s context.',
              child: Text(
                isGroup ? "Group Author's Note" : "Author's Note",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: _controller,
          maxLines: 4,
          minLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Instructions injected into context...',
            hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.resolve(context, Colors.blueAccent, Colors.blue.shade700)),
            ),
            contentPadding: const EdgeInsets.all(10),
          ),
          onChanged: (val) {
            widget.chatService.setAuthorNote(
              val,
              strength: widget.chatService.authorNoteStrength,
            );
          },
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final strength = widget.chatService.authorNoteStrength;
            Color sliderColor;
            String tierLabel;
            if (strength <= 3) {
              sliderColor = Colors.blueAccent;
              tierLabel = 'Subtle';
            } else if (strength <= 7) {
              sliderColor = Colors.amberAccent;
              tierLabel = 'Moderate';
            } else {
              sliderColor = Colors.redAccent;
              tierLabel = 'Strong';
            }
            return Column(
              children: [
                Row(
                  children: [
                    Tooltip(
                      message:
                          'Controls how forcefully the author\'s note is applied.\n'
                          'Subtle: a gentle suggestion the AI may follow.\n'
                          'Moderate: standard injection into context.\n'
                          'Strong: an urgent directive the AI should apply immediately.',
                      child: Text(
                        'Strength: ',
                        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          activeTrackColor: sliderColor,
                          inactiveTrackColor: AppColors.borderOf(context).withValues(alpha: 0.3),
                          thumbColor: sliderColor,
                        ),
                        child: Slider(
                          value: strength.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$strength — $tierLabel',
                          onChanged: (val) {
                            widget.chatService.setAuthorNote(
                              widget.chatService.authorNote,
                              strength: val.round(),
                            );
                          },
                        ),
                      ),
                    ),
                    Text(
                      '$strength',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: sliderColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: sliderColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          tierLabel,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Chat Summary sidebar section — shows enable toggle, config,
/// current summary, and allows editing/pause/regeneration.
class _SummarySection extends StatefulWidget {
  final ChatService chatService;
  const _SummarySection({required this.chatService});

  @override
  State<_SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<_SummarySection> {
  late TextEditingController _controller;
  bool _showSettings = false;
  bool _expanded = false;
  double? _dragSummaryInterval;
  double? _dragSummaryMaxWords;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.chatService.summary);
    widget.chatService.addListener(_onChatChanged);
  }

  void _onChatChanged() {
    if (_controller.text != widget.chatService.summary) {
      _controller.text = widget.chatService.summary;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onChatChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.summaryEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable toggle
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.auto_stories,
                  size: 14,
                  color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                ),
                const SizedBox(width: 6),
                Text(
                  'Chat Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (enabled && widget.chatService.isSummaryGenerating)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 28,
                  child: FittedBox(
                    child: Switch(
                      value: enabled,
                      onChanged: (val) {
                        storage.setSummaryEnabled(val);
                        if (val) setState(() => _expanded = true);
                      },
                      activeTrackColor: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_expanded) ...[
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Text(
                'Auto-summarize conversations so the AI remembers earlier events even after they leave the context window.',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
              ),
            ),

          if (enabled) ...[
            const SizedBox(height: 8),
            // Summary text field
            Padding(
              padding: const EdgeInsets.only(left: 20.0),
              child: AppTextField(
                controller: _controller,
                maxLines: 6,
                minLines: 2,
                style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
                decoration: InputDecoration(
                  hintText:
                      'No summary yet. It will generate after enough messages...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700)),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
                onChanged: (val) {
                  widget.chatService.setSummary(val);
                },
              ),
            ),
            const SizedBox(height: 6),
            // Controls row
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  // Pause/Resume toggle
                  InkWell(
                    onTap: () => widget.chatService.setSummaryPaused(
                      !widget.chatService.summaryPaused,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.chatService.summaryPaused
                                ? Icons.play_arrow
                                : Icons.pause,
                            size: 14,
                            color: widget.chatService.summaryPaused
                                ? AppColors.resolve(context, Colors.orangeAccent, Colors.orange.shade700)
                                : AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.chatService.summaryPaused
                                ? 'Paused'
                                : 'Auto',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.chatService.summaryPaused
                                  ? AppColors.resolve(context, Colors.orangeAccent, Colors.orange.shade700)
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Settings gear toggle
                  InkWell(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Icon(
                        Icons.tune,
                        size: 14,
                        color: _showSettings
                            ? Colors.tealAccent
                            : Colors.white38,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Regenerate button
                  InkWell(
                    onTap: widget.chatService.isSummaryGenerating
                        ? null
                        : () => widget.chatService.forceSummaryUpdate(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: widget.chatService.isSummaryGenerating
                                ? Colors.white12
                                : Colors.tealAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Regen',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.chatService.isSummaryGenerating
                                  ? Colors.white12
                                  : Colors.tealAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.chatService.summaryLastIndex > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text(
                  'Last updated at message #${widget.chatService.summaryLastIndex}',
                  style: const TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ),

            // Expandable settings panel
            if (_showSettings) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Update Interval
                      Row(
                        children: [
                          const Text(
                            'Update every',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_dragSummaryInterval ?? storage.summaryInterval.toDouble()).round()} messages',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent,
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
                          value: _dragSummaryInterval ?? storage.summaryInterval.toDouble(),
                          min: 3,
                          max: 50,
                          divisions: 47,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white12,
                          onChanged: (val) => setState(() => _dragSummaryInterval = val),
                          onChangeEnd: (val) {
                            _dragSummaryInterval = null;
                            storage.setSummaryInterval(val.toInt());
                          },
                        ),
                      ),
                      // Max Words
                      Row(
                        children: [
                          const Text(
                            'Max words',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_dragSummaryMaxWords ?? storage.summaryMaxWords.toDouble()).round()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent,
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
                          value: _dragSummaryMaxWords ?? storage.summaryMaxWords.toDouble(),
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white12,
                          onChanged: (val) => setState(() => _dragSummaryMaxWords = val),
                          onChangeEnd: (val) {
                            _dragSummaryMaxWords = null;
                            storage.setSummaryMaxWords(val.toInt());
                          },
                        ),
                      ),
                      // Summary Prompt
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Summary Prompt',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              storage.setSummaryPrompt(
                                StorageService.defaultSummaryPrompt,
                              );
                              setState(() {});
                            },
                            child: const Text(
                              'Reset',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.tealAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AppTextField(
                        controller: TextEditingController(
                          text: storage.summaryPrompt,
                        ),
                        maxLines: 3,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Instructions for summarizing...',
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                        onChanged: (val) => storage.setSummaryPrompt(val),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: Colors.amber,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Uses your active LLM — consumes tokens on paid APIs.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

/// Memory (RAG) sidebar section — shows enable toggle, config,
/// embedding status, and per-character memory source picker.
class _MemorySection extends StatefulWidget {
  final ChatService chatService;
  const _MemorySection({required this.chatService});

  @override
  State<_MemorySection> createState() => _MemorySectionState();
}

class _MemorySectionState extends State<_MemorySection> {
  bool _showSettings = false;
  bool _showSources = false;
  Set<String> _selectedSources = {};
  bool _sourcesLoaded = false;
  double? _dragRagRetrievalCount;
  double? _dragRagWindowSize;
  double? _dragAutoPersonaInterval;
  double? _dragEvolutionInterval;

  /// Derive the embedding ID for a character card (must match ChatService._getCharacterIdFromCard)
  String _embeddingId(CharacterCard card) {
    if (card.imagePath != null) {
      return p.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  /// Load current memorySources from DB
  Future<void> _loadSources() async {
    final activeChar = widget.chatService.activeCharacter;
    if (activeChar == null || activeChar.dbId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final sources = await repo.getMemorySources(activeChar.dbId!);
      setState(() {
        _selectedSources = sources.toSet();
        _sourcesLoaded = true;
      });
    } catch (_) {
      setState(() => _sourcesLoaded = true);
    }
  }

  /// Save selected sources to DB
  Future<void> _saveSources() async {
    final activeChar = widget.chatService.activeCharacter;
    if (activeChar == null || activeChar.dbId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      await repo.setMemorySources(activeChar.dbId!, _selectedSources.toList());
    } catch (e) {
      debugPrint('[RAG:UI] Failed to save memorySources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.ragEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable toggle
        Row(
          children: [
            const Icon(Icons.psychology, size: 16, color: Colors.purpleAccent),
            const SizedBox(width: 6),
            const Text(
              'Memory (RAG)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 28,
              child: FittedBox(
                child: Switch(
                  value: enabled,
                  onChanged: (val) async {
                    if (!val) {
                      // Turning OFF — no consent needed
                      storage.setRagEnabled(false);
                      return;
                    }
                    // Turning ON — check if consent was given before
                    final prefs = await SharedPreferences.getInstance();
                    final consented =
                        prefs.getBool('rag_setup_consented') ?? false;
                    if (consented) {
                      // Already consented — just enable
                      storage.setRagEnabled(true);
                      Provider.of<EmbeddingSidecar>(
                        context,
                        listen: false,
                      ).ensureRunning();
                      return;
                    }
                    // First time — show consent + setup dialog
                    if (!context.mounted) return;
                    final result = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const _RagSetupDialog(),
                    );
                    if (result == true) {
                      await prefs.setBool('rag_setup_consented', true);
                      storage.setRagEnabled(true);
                      if (context.mounted) {
                        Provider.of<EmbeddingSidecar>(
                          context,
                          listen: false,
                        ).ensureRunning();
                      }
                    }
                  },
                  activeTrackColor: Colors.purpleAccent,
                ),
              ),
            ),
          ],
        ),

        if (!enabled)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Retrieve relevant past messages that have fallen out of context, including from other characters\' conversations.',
              style: TextStyle(fontSize: 11, color: Colors.white30),
            ),
          ),

        if (enabled) ...[
          const SizedBox(height: 6),
          // Status indicator
          Builder(
            builder: (context) {
              final sidecar = Provider.of<EmbeddingSidecar>(context);
              final statusColor = sidecar.modelReady
                  ? Colors.greenAccent
                  : Colors.amber;
              final statusText = sidecar.modelReady
                  ? 'Embedding engine ready'
                  : sidecar.isRunning
                  ? 'Starting...'
                  : 'Engine not running';
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          // Controls row
          Row(
            children: [
              // Settings gear toggle
              InkWell(
                onTap: () => setState(() => _showSettings = !_showSettings),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 14,
                        color: _showSettings
                            ? Colors.purpleAccent
                            : Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 10,
                          color: _showSettings
                              ? Colors.purpleAccent
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Sources toggle
              InkWell(
                onTap: () {
                  setState(() => _showSources = !_showSources);
                  if (_showSources && !_sourcesLoaded) _loadSources();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people,
                        size: 14,
                        color: _showSources
                            ? Colors.purpleAccent
                            : Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sources${_selectedSources.isNotEmpty ? ' (${_selectedSources.length})' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: _showSources
                              ? Colors.purpleAccent
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Data Bank button
              InkWell(
                onTap: () {
                  final activeChar = widget.chatService.activeCharacter;
                  if (activeChar == null) return;
                  showDialog(
                    context: context,
                    builder: (_) => DataBankDialog(
                      characterId: _embeddingId(activeChar),
                      characterName: activeChar.name,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.library_books,
                        size: 14,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Data Bank',
                        style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expandable settings
          if (_showSettings) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Memories per turn
                  Row(
                    children: [
                      Text(
                        'Memories per turn',
                        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        (_dragRagRetrievalCount ?? storage.ragRetrievalCount.toDouble()).round() == 0
                            ? 'All'
                            : '${(_dragRagRetrievalCount ?? storage.ragRetrievalCount.toDouble()).round()}',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
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
                      value: _dragRagRetrievalCount ?? storage.ragRetrievalCount.toDouble(),
                      min: 0,
                      max: 50,
                      divisions: 50,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: Colors.white12,
                      onChanged: (val) => setState(() => _dragRagRetrievalCount = val),
                      onChangeEnd: (val) {
                        _dragRagRetrievalCount = null;
                        storage.setRagRetrievalCount(val.round());
                      },
                    ),
                  ),
                  // Window size
                  Row(
                    children: [
                      const Text(
                        'Window size',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        '${(_dragRagWindowSize ?? storage.ragWindowSize.toDouble()).round()}',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
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
                      value: _dragRagWindowSize ?? storage.ragWindowSize.toDouble(),
                      min: 3,
                      max: 10,
                      divisions: 7,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: Colors.white12,
                      onChanged: (val) => setState(() => _dragRagWindowSize = val),
                      onChangeEnd: (val) {
                        _dragRagWindowSize = null;
                        storage.setRagWindowSize(val.round());
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: Colors.purpleAccent,
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Uses local nomic-embed-text model — no data leaves your machine.',
                          style: TextStyle(fontSize: 10, color: Colors.white38),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),
                  // Auto-persona toggle
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: Colors.purpleAccent,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Auto-update persona',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          child: Switch(
                            value: storage.autoPersonaEnabled,
                            onChanged: (val) =>
                                storage.setAutoPersonaEnabled(val),
                            activeTrackColor: Colors.purpleAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (storage.autoPersonaEnabled) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          'Extract every',
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        const Spacer(),
                        Text(
                          '${(_dragAutoPersonaInterval ?? storage.autoPersonaInterval.toDouble()).round()} messages',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _dragAutoPersonaInterval ?? storage.autoPersonaInterval.toDouble(),
                      min: 5,
                      max: 50,
                      divisions: 9,
                      activeColor: Colors.purpleAccent,
                      onChanged: (val) => setState(() => _dragAutoPersonaInterval = val),
                      onChangeEnd: (val) {
                        _dragAutoPersonaInterval = null;
                        storage.setAutoPersonaInterval(val.round());
                      },
                    ),
                    const Text(
                      'Extracts personal facts from your messages using the LLM. View facts in Persona settings.',
                      style: TextStyle(fontSize: 10, color: Colors.white24),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),
                  // Character evolution toggle
                  Row(
                    children: [
                      const Icon(
                        Icons.psychology_alt,
                        size: 14,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Character Evolution',
                        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          child: Switch(
                            value: storage.characterEvolutionEnabled,
                            onChanged: (val) =>
                                storage.setCharacterEvolutionEnabled(val),
                            activeTrackColor: Colors.tealAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (storage.characterEvolutionEnabled) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          'Evolve every',
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                        const Spacer(),
                        Text(
                          '${(_dragEvolutionInterval ?? storage.evolutionInterval.toDouble()).round()} messages',
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _dragEvolutionInterval ?? storage.evolutionInterval.toDouble(),
                      min: 10,
                      max: 50,
                      divisions: 8,
                      activeColor: Colors.tealAccent,
                      onChanged: (val) => setState(() => _dragEvolutionInterval = val),
                      onChangeEnd: (val) {
                        _dragEvolutionInterval = null;
                        storage.setEvolutionInterval(val.round());
                      },
                    ),
                    Consumer<ChatService>(
                      builder: (context, chat, _) {
                        final count = chat.characterEvolutionCount;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  count > 0
                                      ? 'Evolved $count time${count > 1 ? 's' : ''}'
                                      : 'Not yet evolved',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: count > 0
                                        ? Colors.tealAccent
                                        : Colors.white24,
                                    fontWeight: count > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                const Spacer(),
                                if (count > 0) ...[
                                  GestureDetector(
                                    onTap: () =>
                                        _showEvolutionReview(context, chat),
                                    child: const Text(
                                      'View',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.tealAccent,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _showResetEvolutionConfirm(
                                      context,
                                      chat,
                                    ),
                                    child: const Text(
                                      'Reset',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.redAccent,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Personality & scenario evolve based on conversations. Original card is always preserved.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white24,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Expandable memory sources (cross-character picker)
          if (_showSources) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Include memories from other characters:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  _buildCharacterSourceList(),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildCharacterSourceList() {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final activeChar = widget.chatService.activeCharacter;
    final activeEmbedId = activeChar != null ? _embeddingId(activeChar) : '';

    // Get all characters except the current one
    final otherChars = charRepo.characters
        .where((c) => _embeddingId(c) != activeEmbedId)
        .toList();

    if (otherChars.isEmpty) {
      return const Text(
        'No other characters available.',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white30,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      children: otherChars.map((char) {
        final embedId = _embeddingId(char);
        final isSelected = _selectedSources.contains(embedId);
        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedSources.remove(embedId);
              } else {
                _selectedSources.add(embedId);
              }
            });
            _saveSources();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: isSelected ? Colors.purpleAccent : Colors.white30,
                ),
                const SizedBox(width: 8),
                if (char.imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).resolveCharacterImage(char.imagePath!),
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.white30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    char.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white70 : Colors.white38,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showEvolutionReview(BuildContext context, ChatService chat) {
    final character = chat.activeCharacter;
    if (character == null) return;
    final charName = character.name;

    // Get evolved versions from chat service cache
    final evolvedPersonality = chat.getEffectivePersonality ?? '';
    final evolvedScenario = chat.getEffectiveScenario ?? '';

    final personalityController = TextEditingController(
      text: evolvedPersonality,
    );
    final scenarioController = TextEditingController(text: evolvedScenario);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                '$charName — Evolution',
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
                Text(
                  'Evolved ${chat.characterEvolutionCount} time${chat.characterEvolutionCount > 1 ? "s" : ""}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.tealAccent,
                  ),
                ),
                const SizedBox(height: 12),
                // Original personality (read-only)
                const Text(
                  'Original Personality',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      character.personality,
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
                  style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                ),
                const SizedBox(height: 4),
                AppTextField(
                  controller: personalityController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(height: 12),
                // Original scenario (read-only)
                const Text(
                  'Original Scenario',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      character.scenario,
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
                  style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                ),
                const SizedBox(height: 4),
                AppTextField(
                  controller: scenarioController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
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
          ElevatedButton(
            onPressed: () {
              chat.updateEvolvedPersonality(personalityController.text);
              chat.updateEvolvedScenario(scenarioController.text);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade700,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showResetEvolutionConfirm(BuildContext context, ChatService chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Reset Character Evolution?'),
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
              chat.resetCharacterEvolution();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ── RAG Setup Consent + Progress Dialog ─────────────────────────────

class _RagSetupDialog extends StatefulWidget {
  const _RagSetupDialog();

  @override
  State<_RagSetupDialog> createState() => _RagSetupDialogState();
}

class _RagSetupDialogState extends State<_RagSetupDialog> {
  bool _isSettingUp = false;
  bool _isDone = false;

  @override
  Widget build(BuildContext context) {
    final sidecar = Provider.of<EmbeddingSidecar>(context);

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isSettingUp ? _buildSetupView(sidecar) : _buildConsentView(),
        ),
      ),
    );
  }

  Widget _buildConsentView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purpleAccent, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.psychology,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enable Memory (RAG)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Explanation
        const Text(
          'Memory (RAG) gives your AI the ability to recall past conversations — even ones that have left the context window.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                icon: Icons.download,
                color: Colors.blueAccent,
                text: 'Downloads a ~270 MB AI embedding model on first setup',
              ),
              SizedBox(height: 8),
              _InfoRow(
                icon: Icons.memory,
                color: Colors.tealAccent,
                text: 'Runs locally on your CPU — no data leaves your machine',
              ),
              SizedBox(height: 8),
              _InfoRow(
                icon: Icons.search,
                color: Colors.purpleAccent,
                text:
                    'Searches past messages for relevant context to include in prompts',
              ),
              SizedBox(height: 8),
              _InfoRow(
                icon: Icons.swap_horiz,
                color: Colors.amberAccent,
                text:
                    'You can switch to API-based embeddings later in Settings',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isSettingUp = true);
                _startSetup();
              },
              icon: const Icon(Icons.rocket_launch, size: 16),
              label: const Text('Set Up & Enable'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSetupView(EmbeddingSidecar sidecar) {
    final hasError = sidecar.error != null;
    final progress = sidecar.downloadProgress;
    final showProgress = progress >= 0 && progress <= 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            if (_isDone)
              const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 28,
              )
            else if (hasError)
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 28)
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.purpleAccent,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isDone
                    ? 'Setup Complete'
                    : hasError
                    ? 'Setup Failed'
                    : 'Setting Up Memory...',
                style: TextStyle(
                  color: _isDone
                      ? Colors.greenAccent
                      : hasError
                      ? Colors.redAccent
                      : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Status message
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sidecar.statusMessage,
                style: TextStyle(
                  color: hasError ? Colors.redAccent : Colors.white70,
                  fontSize: 13,
                ),
              ),
              if (showProgress) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.purpleAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              if (!showProgress && !hasError && !_isDone) ...[
                const SizedBox(height: 10),
                const ClipRRect(
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.purpleAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasError && sidecar.error != null) ...[
          const SizedBox(height: 8),
          Text(
            sidecar.error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // Troubleshooting hints based on error type
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: Colors.orangeAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Troubleshooting',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (sidecar.error!.contains('retrieve') ||
                    sidecar.error!.contains('download') ||
                    sidecar.error!.contains('network')) ...[
                  const Text(
                    '• Check your internet connection',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• Verify you can access huggingface.co',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• Try again — the server may be temporarily busy',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• If this persists, try clearing the cache:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    Platform.isWindows
                        ? '  %LOCALAPPDATA%/front-porch-ai/embeddings/'
                        : Platform.isMacOS
                        ? '  ~/Library/Caches/front-porch-ai/embeddings/'
                        : '  ~/.cache/front-porch-ai/embeddings/',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ] else if (sidecar.error!.contains('onnxruntime') ||
                    sidecar.error!.contains('.dll')) ...[
                  const Text(
                    '• A conflicting ONNX Runtime library may be installed',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• Check for onnxruntime.dll in C:\\Windows\\System32\\',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• Remove or rename the conflicting file and retry',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ] else if (sidecar.error!.contains('bind') ||
                    sidecar.error!.contains('port')) ...[
                  const Text(
                    '• Port 5055 may be in use by another application',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• Close other applications using that port and retry',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ] else ...[
                  const Text(
                    '• Try clicking Retry — transient errors often resolve',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Text(
                    '• If this persists, restart the application',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isDone)
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Done'),
              )
            else if (hasError) ...[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  sidecar.clearError();
                  _startSetup();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ] else
              TextButton(
                onPressed: () {
                  // Cancel the setup — stop sidecar
                  sidecar.stopServer();
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _startSetup() async {
    final sidecar = Provider.of<EmbeddingSidecar>(context, listen: false);

    // Start server (will also trigger model download if needed)
    await sidecar.startServer();
    if (sidecar.error != null) return; // Error state shown in UI

    // Wait for model to be ready
    final ready = await sidecar.waitForModelReady();
    if (!mounted) return;

    if (ready) {
      setState(() => _isDone = true);
    }
    // If not ready, error state is shown via sidecar.error
  }
}

/// Small helper widget for the consent dialog info rows.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
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
    );
  }
}

// ── Realism Mode Section ──────────────────────────────────────────────

class _RealismSection extends StatefulWidget {
  final ChatService chatService;
  const _RealismSection({required this.chatService});

  @override
  State<_RealismSection> createState() => _RealismSectionState();
}

class _RealismSectionState extends State<_RealismSection> {
  bool _expanded = true; // default expanded

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chat, _) {
        final enabled = chat.realismEnabled;
        final storageService = Provider.of<StorageService>(context);

        // Bond colors per tier — made light-mode safe
        Color getTierColor(int tier) {
          // Strong positive tiers (vibrant, work on both themes)
          if (tier >= 10) return Colors.deepPurpleAccent;
          if (tier >= 9) return Colors.purpleAccent;
          if (tier >= 8) return Colors.pinkAccent;
          if (tier >= 7) return Colors.pink;
          if (tier >= 6) return Colors.pink.shade200;
          if (tier >= 5) return Colors.orangeAccent;
          if (tier >= 4) return Colors.greenAccent;

          // Neutral / low tiers — use context-aware versions for light mode readability
          if (tier >= 3) {
            return AppColors.resolve(context, Colors.lightBlue, Colors.blue.shade700);
          }
          if (tier >= 2) {
            return AppColors.resolve(context, Colors.blueGrey, Colors.blueGrey.shade700);
          }
          if (tier >= 1) {
            return AppColors.resolve(context, Colors.grey.shade400, Colors.grey.shade700);
          }
          if (tier == 0) {
            return AppColors.textTertiary(context);
          }

          // Negative tiers (mostly dark reds/browns in dark mode — they become readable darks on light)
          if (tier >= -1) return AppColors.resolve(context, Colors.orangeAccent.shade100, Colors.orange.shade700);
          if (tier >= -2) return AppColors.resolve(context, Colors.redAccent.shade100, Colors.red.shade600);
          if (tier >= -3) return Colors.redAccent;
          if (tier >= -4) return Colors.red;
          if (tier >= -5) return AppColors.resolve(context, Colors.red.shade900, Colors.red.shade800);
          if (tier >= -6) return AppColors.resolve(context, Colors.brown.shade900, Colors.brown.shade700);
          if (tier >= -7) return AppColors.resolve(context, Colors.deepOrange.shade900, Colors.deepOrange.shade700);
          if (tier >= -8) return AppColors.resolve(context, Colors.amber.shade900, Colors.amber.shade800);
          if (tier >= -9) return AppColors.resolve(context, Colors.orange.shade900, Colors.orange.shade800);
          return AppColors.textPrimary(context);
        }

        final shortTermColor = getTierColor(chat.relationshipTier);
        final longTermColor = getTierColor(chat.longTermTier);

        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Collapsible Header ──
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.theater_comedy,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Realism Mode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: enabled,
                          activeThumbColor: AppColors.resolve(
                            context,
                            Colors.tealAccent,
                            Colors.teal.shade700,
                          ),
                          onChanged: chat.isGenerating
                              ? null
                              : (val) {
                                  chat.setRealismEnabled(val);
                                  if (val) setState(() => _expanded = true);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Expanded Content ──
              if (enabled && _expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: AppColors.borderOf(context).withValues(alpha: 0.2), height: 1),
                      const SizedBox(height: 10),

                      // ── Short-Term Tension ──
                      Tooltip(
                        message:
                            'Short-term Dynamic: The immediate "tension in the room" or how they feel about you right now. Evolves quickly based on recent events.',
                        child: Row(
                          children: [
                            Icon(
                              chat.relationshipTier < 0
                                  ? Icons.heart_broken
                                  : Icons.favorite,
                              size: 13,
                              color: shortTermColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Short-Term Bond: ${chat.shortTermTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: shortTermColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.affectionScore.abs()}/${chat.shortTermProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: chat.shortTermProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            shortTermColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Long-Term Bond ──
                      Tooltip(
                        message:
                            'Long-term Relationship: Your deep, overarching history together. Evolves slowly and sets the foundation for your interactions.',
                        child: Row(
                          children: [
                            Icon(
                              chat.longTermTier < 0
                                  ? Icons.heart_broken_sharp
                                  : Icons.monitor_heart,
                              size: 13,
                              color: longTermColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Long-Term Bond: ${chat.longTermTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: longTermColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.longTermScore.abs()}/${chat.longTermProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: chat.longTermProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            longTermColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Trust / Distrust ──
                      Tooltip(
                        message:
                            'Trust: Paranoia vs absolute faith. Dictates whether the character questions your motives or readily believes you.',
                        child: Row(
                          children: [
                            Icon(
                              chat.trustLevel < 0
                                  ? Icons.vpn_key_off
                                  : Icons.vpn_key,
                              size: 13,
                              color: chat.trustLevel < 0
                                  ? Colors.redAccent
                                  : Colors.amber,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Trust: ${chat.trustTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: chat.trustLevel < 0
                                      ? Colors.redAccent
                                      : Colors.amber,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.trustLevel.abs()}/${chat.trustProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: chat.trustProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            chat.trustLevel < 0
                                ? Colors.redAccent
                                : Colors.amber,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Emotion ──
                      if (chat.characterEmotion.isNotEmpty) ...[
                        Row(
                          children: [
                            Text(
                              _emotionEmoji(chat.characterEmotion),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${chat.characterEmotion.substring(0, 1).toUpperCase()}${chat.characterEmotion.substring(1)} (${chat.emotionIntensity})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Time of Day ──
                      Row(
                        children: [
                          Text(
                            _timeEmoji(chat.timeOfDay),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _timeLabel(chat.timeOfDay),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const Spacer(),
                          // Manual time nudge: back
                          if (chat.realismEnabled)
                            GestureDetector(
                              onTap: () => chat.nudgeTimePeriod(-1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  Icons.chevron_left,
                                  size: 16,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            ),
                          Text(
                            '${chat.narrativeWeekday.substring(0, 3)} · Day ${chat.dayCount}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          // Manual time nudge: forward
                          if (chat.realismEnabled)
                            GestureDetector(
                              onTap: () => chat.nudgeTimePeriod(1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Time period dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final period in [
                            'dawn',
                            'morning',
                            'late_morning',
                            'afternoon',
                            'evening',
                            'night',
                          ])
                            Column(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: chat.timeOfDay == period
                                        ? AppColors.resolve(context, Colors.amber, Colors.amber.shade700)
                                        : AppColors.borderOf(context).withValues(alpha: 0.25),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _timeDotLabel(period),
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: chat.timeOfDay == period
                                        ? AppColors.resolve(context, Colors.amber, Colors.amber.shade800)
                                        : AppColors.textTertiary(context),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // OOC time-skip toast removed — skip info now appears
                      // in the delta row on the next AI message bubble.
                      const SizedBox(height: 12),

                      // ── Automatic Passage of Time Toggle ──
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Automatic Passage of Time',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: chat.passageOfTimeEnabled,
                              activeThumbColor: AppColors.resolve(
                                context,
                                Colors.blueAccent,
                                Colors.blue.shade700,
                              ),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) => chat.setPassageOfTimeEnabled(val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time advances automatically as you chat. Manual controls remain available.',
                        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 10),
                      ),
                      const SizedBox(height: 12),

                      // ── Needs Simulation Toggle + Bars ──
                      Row(
                        children: [
                          Icon(
                            Icons.battery_std,
                            size: 14,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Needs Simulation',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: chat.needsSimEnabled,
                              activeThumbColor: AppColors.resolve(
                                context,
                                Colors.tealAccent,
                                Colors.teal.shade700,
                              ),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) => chat.setNeedsSimEnabled(val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tracks hunger, bladder, energy, social, fun, hygiene, comfort. Affects AI prompts & behavior when low.',
                        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 10),
                      ),
                      if (chat.needsSimEnabled && chat.needsVector.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final entry in chat.needsVector.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 58,
                                  child: Text(
                                    entry.key[0].toUpperCase() + entry.key.substring(1),
                                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context)),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: (entry.value / 100.0).clamp(0.0, 1.0),
                                      minHeight: 4,
                                      backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        entry.value <= ChatService.needCriticalThreshold
                                            ? Colors.redAccent
                                            : AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text('${entry.value}', style: TextStyle(fontSize: 9, color: AppColors.textTertiary(context))),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),

                      // ── NSFW Enhancements Submenu ──
                      _NsfwEnhancementsSection(chat: chat),

                      const SizedBox(height: 12),
                      Divider(color: AppColors.borderOf(context).withValues(alpha: 0.2), height: 1),
                      const SizedBox(height: 10),

                      // ── Realism Performance ──
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            size: 14,
                            color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: RichText(
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'One-Shot Eval ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                                    ),
                                  ),
                                  TextSpan(
                                    text: '(Experimental)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 20,
                            child: Switch(
                              value: storageService.realismOneShotEval,
                              activeThumbColor: AppColors.resolve(context, Colors.tealAccent, Colors.teal.shade700),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) {
                                      storageService.setRealismOneShotEval(val);
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fuses relationship + scene evals into a single LLM call to double the processing speed. May be less accurate on < 8B param models.',
                        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'amused':
      case 'playful':
      case 'happy':
        return '😄';
      case 'angry':
      case 'furious':
        return '😠';
      case 'sad':
      case 'melancholy':
        return '😢';
      case 'anxious':
      case 'nervous':
      case 'worried':
        return '😰';
      case 'excited':
      case 'thrilled':
        return '🤩';
      case 'flirtatious':
      case 'aroused':
        return '😏';
      case 'calm':
      case 'relaxed':
      case 'content':
        return '😌';
      case 'suspicious':
      case 'wary':
        return '🤨';
      case 'fearful':
      case 'scared':
        return '😨';
      case 'embarrassed':
      case 'flustered':
        return '😳';
      case 'annoyed':
      case 'irritated':
        return '😤';
      case 'confused':
      case 'conflicted':
        return '😕';
      case 'protective':
        return '🛡️';
      default:
        return '🎭';
    }
  }

  String _timeEmoji(String time) {
    switch (time) {
      case 'dawn':
        return '🌅';
      case 'morning':
        return '☀️';
      case 'late_morning':
        return '🌤️';
      case 'afternoon':
        return '☀️';
      case 'evening':
        return '🌇';
      case 'night':
        return '🌙';
      default:
        return '🕐';
    }
  }

  String _timeLabel(String time) {
    switch (time) {
      case 'dawn':
        return 'Dawn';
      case 'morning':
        return 'Morning';
      case 'late_morning':
        return 'Late Morning';
      case 'afternoon':
        return 'Afternoon';
      case 'evening':
        return 'Evening';
      case 'night':
        return 'Night';
      default:
        return time;
    }
  }

  String _timeDotLabel(String period) {
    switch (period) {
      case 'dawn':
        return 'D';
      case 'morning':
        return 'M';
      case 'late_morning':
        return 'LM';
      case 'afternoon':
        return 'A';
      case 'evening':
        return 'E';
      case 'night':
        return 'N';
      default:
        return '';
    }
  }
}

// ── NSFW Enhancements Section ──────────────────────────────────────────

class _NsfwEnhancementsSection extends StatefulWidget {
  final ChatService chat;
  const _NsfwEnhancementsSection({required this.chat});

  @override
  State<_NsfwEnhancementsSection> createState() =>
      _NsfwEnhancementsSectionState();
}

class _NsfwEnhancementsSectionState extends State<_NsfwEnhancementsSection> {
  bool _expanded = true; // default expanded

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.deepOrangeAccent,
                ),
                const SizedBox(width: 5),
                const Flexible(
                  child: Text(
                    'NSFW Enhancements',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrangeAccent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.chat.nsfwCooldownEnabled &&
                    widget.chat.cooldownTurnsRemaining > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⏳ ${widget.chat.cooldownTurnsRemaining}t',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.deepOrangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  height: 20,
                  child: Switch(
                    value: widget.chat.nsfwCooldownEnabled,
                    activeThumbColor: Colors.deepOrangeAccent,
                    onChanged: widget.chat.isGenerating
                        ? null
                        : (val) {
                            widget.chat.setNsfwCooldownEnabled(val);
                            if (val) setState(() => _expanded = true);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded content
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepOrange.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                // ── Lust ──
                if (widget.chat.nsfwCooldownEnabled) ...[
                  Row(
                    children: [
                       Icon(
                         widget.chat.arousalTier >= 6
                             ? Icons.local_fire_department
                             : widget.chat.arousalTier <= -1
                             ? Icons.ac_unit
                             : Icons.favorite_border,
                         size: 13,
                         color: widget.chat.arousalTier >= 6
                             ? AppColors.resolve(context, Colors.deepOrangeAccent, Colors.deepOrange.shade700)
                             : widget.chat.arousalTier <= -1
                             ? AppColors.resolve(context, Colors.lightBlueAccent, Colors.blue.shade700)
                             : AppColors.iconSecondary(context),
                       ),
                       const SizedBox(width: 5),
                       Expanded(
                         child: Text(
                           'Lust: ${widget.chat.arousalTierName}',
                           style: TextStyle(
                             fontSize: 12,
                             color: widget.chat.arousalTier >= 6
                                 ? AppColors.resolve(context, Colors.deepOrangeAccent, Colors.deepOrange.shade700)
                                 : widget.chat.arousalTier <= -1
                                 ? AppColors.resolve(context, Colors.lightBlueAccent, Colors.blue.shade700)
                                 : AppColors.textSecondary(context),
                           ),
                           overflow: TextOverflow.ellipsis,
                         ),
                       ),
                       const SizedBox(width: 8),
                       Text(
                         '${widget.chat.arousalLevel.clamp(-100, 100)}/100',
                         style: TextStyle(
                           fontSize: 10,
                           color: AppColors.textTertiary(context),
                         ),
                       ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (widget.chat.arousalLevel.abs() / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.chat.arousalTier >= 6
                            ? AppColors.resolve(context, Colors.deepOrangeAccent, Colors.deepOrange.shade700)
                            : AppColors.resolve(context, Colors.lightBlueAccent, Colors.blue.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (widget.chat.nsfwCooldownEnabled &&
                    widget.chat.cooldownTurnsRemaining > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.hourglass_bottom,
                        size: 12,
                        color: Colors.deepOrangeAccent,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Refractory: ${widget.chat.cooldownTurnsRemaining} turn${widget.chat.cooldownTurnsRemaining == 1 ? '' : 's'} remaining',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.deepOrangeAccent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Chaos Mode Section ─────────────────────────────────────────────────

class _ChaosModeSection extends StatelessWidget {
  final ChatService chat;
  final VoidCallback onSpinRequested;
  const _ChaosModeSection({required this.chat, required this.onSpinRequested});

  Color get _pressureColor => Color.lerp(
    const Color(0xFF2EC4B6),
    const Color(0xFFE63946),
    (chat.chaosPressure / 100).clamp(0.0, 1.0),
  )!;

  @override
  Widget build(BuildContext context) {
    final borderColor = chat.chaosModeEnabled
        ? _pressureColor.withValues(alpha: 0.5)
        : AppColors.borderOf(context).withValues(alpha: 0.3);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: chat.chaosModeEnabled,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: Text(
            '🎰',
            style: TextStyle(
              fontSize: 16,
              shadows: chat.chaosModeEnabled
                  ? [Shadow(color: _pressureColor, blurRadius: 10)]
                  : null,
            ),
          ),
          title: Row(
            children: [
              Text(
                'Chaos Mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              Switch(
                value: chat.chaosModeEnabled,
                onChanged: (v) => chat.setChaosModeEnabled(v),
                activeThumbColor: AppColors.resolve(
                  context,
                  const Color(0xFFFFD166),
                  Colors.amber.shade700,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pressure bar
                  Row(
                    children: [
                      Icon(
                        Icons.casino_rounded,
                        size: 12,
                        color: _pressureColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pressure: ${chat.chaosPressure}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: _pressureColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (chat.chaosPressure / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(_pressureColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // NSFW spicy events toggle
                  Row(
                    children: [
                      const Text('🌶️', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Include spicy events',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: chat.chaosNsfwEnabled,
                          onChanged: (v) => chat.setChaosNsfwEnabled(v),
                          activeThumbColor: AppColors.resolve(
                            context,
                            const Color(0xFFFF6B9D),
                            Colors.pink.shade600,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: chat.hasPendingChaosEvent ? null : onSpinRequested,
                    child: Opacity(
                      opacity: chat.hasPendingChaosEvent ? 0.4 : 1.0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: chat.hasPendingChaosEvent
                                ? [
                                    AppColors.surfaceContainerOf(context),
                                    AppColors.cardOf(context),
                                  ]
                                : [
                                    const Color(0xFFFFD166),
                                    const Color(0xFFFFC233),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: chat.hasPendingChaosEvent
                              ? Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.3))
                              : null,
                          boxShadow: chat.hasPendingChaosEvent
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFFFD166).withValues(alpha: 0.3),
                                    blurRadius: 10,
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              chat.hasPendingChaosEvent ? '⏳' : '🎰',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              chat.hasPendingChaosEvent
                                  ? 'EVENT PENDING'
                                  : 'SPIN NOW',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: chat.hasPendingChaosEvent
                                    ? AppColors.textTertiary(context)
                                    : const Color(0xFF1A1200),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto-triggers grow more likely each turn.\nBase: 5% · +5% per turn · cap: 100%',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary(context),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Objective Section ──────────────────────────────────────────────────

class _ObjectiveSection extends StatefulWidget {
  final ChatService chatService;
  const _ObjectiveSection({required this.chatService});

  @override
  State<_ObjectiveSection> createState() => _ObjectiveSectionState();
}

class _ObjectiveSectionState extends State<_ObjectiveSection> {
  bool _expanded = true; // default expanded
  bool _generatingTasks = false;
  bool _nsfw = false;
  int _taskCount = 5;
  final _goalController = TextEditingController();
  final _manualTaskController = TextEditingController();

  @override
  void dispose() {
    _goalController.dispose();
    _manualTaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final pObj = chatService.primaryObjective;
        final secondaries = chatService.secondaryObjectives;

        final primaryTasks = pObj != null
            ? chatService.tasksForObjective(pObj)
            : [];
        final completedCount = primaryTasks
            .where((t) => t['completed'] == true)
            .length;
        final currentTask = primaryTasks
            .where((t) => t['completed'] != true)
            .firstOrNull;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: AppColors.iconSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.flag,
                      size: 14,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Objectives',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    if (pObj != null)
                      Text(
                        '$completedCount/${primaryTasks.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                  ],
                ),
              ),

              if (!_expanded && pObj != null && currentTask != null) ...[
                const SizedBox(height: 6),
                Text(
                  '▸ ${currentTask['description']}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orangeAccent,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (_expanded) ...[
                const SizedBox(height: 10),

                // Primary Objective Display
                if (pObj != null) ...[
                  Text(
                    'PRIMARY QUEST',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            pObj.objective,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => chatService.clearObjective(pObj),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // NSFW toggle
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'NSFW Tasks',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: _nsfw,
                          activeThumbColor: Colors.redAccent,
                          onChanged: (v) => setState(() => _nsfw = v),
                        ),
                      ),
                    ],
                  ),

                  if (primaryTasks.isEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _generatingTasks
                                ? null
                                : () async {
                                    setState(() => _generatingTasks = true);
                                    await chatService.generateObjectiveTasks(
                                      pObj,
                                      taskCount: _taskCount,
                                      nsfw: _nsfw,
                                    );
                                    if (mounted) {
                                      setState(() => _generatingTasks = false);
                                    }
                                  },
                            icon: _generatingTasks
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 14),
                            label: Text(
                              _generatingTasks
                                  ? 'Generating...'
                                  : 'Generate Tasks',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surfaceContainerOf(context),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButton<int>(
                            value: _taskCount,
                            underline: const SizedBox.shrink(),
                            dropdownColor: AppColors.surfaceContainerOf(context),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 12,
                            ),
                            isDense: true,
                            items: [3, 4, 5, 6, 7, 8, 10]
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text('$n'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _taskCount = v ?? 5),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _manualTaskController,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add a task manually...',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onSubmitted: (text) async {
                            if (text.trim().isEmpty) return;
                            await chatService.addManualTask(pObj, text);
                            _manualTaskController.clear();
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          final text = _manualTaskController.text.trim();
                          if (text.isEmpty) return;
                          await chatService.addManualTask(pObj, text);
                          _manualTaskController.clear();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (primaryTasks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...primaryTasks.asMap().entries.map((entry) {
                      final i = entry.key;
                      final task = entry.value;
                      final completed = task['completed'] == true;
                      final isCurrent =
                          !completed &&
                          primaryTasks
                              .take(i)
                              .every((t) => t['completed'] == true);

                      return _EditableTaskRow(
                        key: ValueKey('task_$i'),
                        description: task['description'] as String,
                        completed: completed,
                        isCurrent: isCurrent,
                        onToggle: () => chatService.toggleTask(pObj, i),
                        onDelete: () => chatService.removeTask(pObj, i),
                        onEdit: (newText) =>
                            chatService.updateTask(pObj, i, newText),
                      );
                    }),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Check every ',
                          style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context)),
                        ),
                        SizedBox(
                          width: 80,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              activeTrackColor: AppColors.resolve(context, Colors.white30, Colors.black26),
                              inactiveTrackColor: AppColors.borderOf(context).withValues(alpha: 0.2),
                              thumbColor: AppColors.textSecondary(context),
                            ),
                            child: Slider(
                              value: pObj.checkFrequency.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              onChanged: (v) => chatService
                                  .updateCheckFrequency(pObj, v.round()),
                            ),
                          ),
                        ),
                        Text(
                          '${pObj.checkFrequency} msgs',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        chatService.isCheckingCompletion
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.greenAccent,
                                ),
                              )
                            : InkWell(
                                onTap: () => chatService.forceCheckCompletion(),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 12,
                                        color: Colors.greenAccent,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'Check now',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ],
                ],

                // Secondary Objectives
                if (secondaries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'SIDE QUESTS',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final sObj in secondaries)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle_outlined,
                            size: 10,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              sObj.objective,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => chatService.setObjective(
                              sObj.objective,
                              isPrimary: true,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.keyboard_double_arrow_up,
                                size: 14,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => chatService.clearObjective(sObj),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 12),

                // Add new objective box
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _goalController,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 11,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add new goal...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerOf(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        onSubmitted: (text) async {
                          if (text.trim().isEmpty) return;
                          await chatService.setObjective(
                            text,
                            isPrimary: chatService.primaryObjective == null,
                          );
                          _goalController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () async {
                        final text = _goalController.text.trim();
                        if (text.isEmpty) return;
                        await chatService.setObjective(text, isPrimary: true);
                        _goalController.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('As Primary'),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () async {
                        final text = _goalController.text.trim();
                        if (text.isEmpty) return;
                        await chatService.setObjective(text, isPrimary: false);
                        _goalController.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerOf(context),
                        foregroundColor: AppColors.textPrimary(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(fontSize: 10),
                      ),
                      child: const Text('As Side'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Editable Task Row ──────────────────────────────────────────────────

class _EditableTaskRow extends StatefulWidget {
  final String description;
  final bool completed;
  final bool isCurrent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<String> onEdit;

  const _EditableTaskRow({
    super.key,
    required this.description,
    required this.completed,
    required this.isCurrent,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_EditableTaskRow> createState() => _EditableTaskRowState();
}

class _EditableTaskRowState extends State<_EditableTaskRow> {
  bool _editing = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.description);
  }

  @override
  void didUpdateWidget(_EditableTaskRow old) {
    super.didUpdateWidget(old);
    if (!_editing && old.description != widget.description) {
      _controller.text = widget.description;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onEdit(_controller.text.trim());
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox
          GestureDetector(
            onTap: widget.onToggle,
            child: Icon(
              widget.completed
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 16,
              color: widget.completed
                  ? Colors.greenAccent
                  : widget.isCurrent
                  ? Colors.orangeAccent
                  : AppColors.iconSecondary(context),
            ),
          ),
          const SizedBox(width: 6),

          // Description or edit field
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(color: AppColors.textPrimary(context), fontSize: 11),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Colors.orangeAccent,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  )
                : GestureDetector(
                    onTap: widget.onToggle,
                    child: Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.completed
                            ? AppColors.textTertiary(context)
                            : widget.isCurrent
                            ? AppColors.textPrimary(context)
                            : AppColors.textSecondary(context),
                        decoration: widget.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
          ),

          // Current task indicator
          if (widget.isCurrent && !_editing)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Text(
                '◂',
                style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
              ),
            ),

          const SizedBox(width: 4),

          // Edit / Save button
          if (_editing)
            GestureDetector(
              onTap: _save,
              child: const Icon(
                Icons.check,
                size: 14,
                color: Colors.greenAccent,
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _editing = true),
              child: Icon(Icons.edit, size: 12, color: AppColors.iconSecondary(context)),
            ),

          const SizedBox(width: 4),

          // Delete button
          GestureDetector(
            onTap: widget.onDelete,
            child: Icon(Icons.close, size: 12, color: AppColors.iconSecondary(context)),
          ),
        ],
      ),
    );
  }
}

// ── Realism Engine Processing Overlay ──────────────────────────────────────────

class _RealismProcessingOverlay extends StatefulWidget {
  final ChatService chatService;
  final bool isGreeting;

  const _RealismProcessingOverlay({
    required this.chatService,
    required this.isGreeting,
  });

  @override
  State<_RealismProcessingOverlay> createState() =>
      _RealismProcessingOverlayState();
}

class _RealismProcessingOverlayState extends State<_RealismProcessingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulse;
  late final Animation<double> _rotate;
  late final Animation<double> _fade;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _rotate = CurvedAnimation(parent: _rotateController, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGreeting = widget.isGreeting;
    final accentColor = isGreeting ? Colors.purpleAccent : Colors.cyanAccent;
    final accentColorDim = isGreeting
        ? const Color(0xFF7C3AED)
        : const Color(0xFF06B6D4);
    final title = isGreeting ? 'Reading the room...' : 'Realism Engine';
    final subtitle = isGreeting
        ? 'Capturing emotional baseline from opening message'
        : 'Evaluating relationship, mood & scene state';

    final pills = isGreeting
        ? <_EvalPill>[
            _EvalPill(
              label: 'Emotion',
              icon: Icons.mood,
              color: Colors.purpleAccent,
            ),
            _EvalPill(
              label: 'Bond',
              icon: Icons.favorite_border,
              color: Colors.pinkAccent,
            ),
            _EvalPill(
              label: 'Trust',
              icon: Icons.handshake_outlined,
              color: Colors.blueAccent,
            ),
          ]
        : <_EvalPill>[
            if (widget.chatService.isCheckingCompletion)
              _EvalPill(
                label: 'Objective',
                icon: Icons.flag,
                color: Colors.greenAccent,
              ),
            _EvalPill(
              label: 'Relationship',
              icon: Icons.favorite_border,
              color: Colors.pinkAccent,
            ),
            _EvalPill(
              label: 'Emotion',
              icon: Icons.mood,
              color: Colors.orangeAccent,
            ),
            _EvalPill(
              label: 'Scene',
              icon: Icons.wb_twilight,
              color: Colors.amber,
            ),
            _EvalPill(
              label: 'Trust',
              icon: Icons.handshake_outlined,
              color: Colors.blueAccent,
            ),
          ];

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          type: MaterialType.transparency,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Colors.black.withOpacity(0.55),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 680,
                    maxHeight: 580,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0F1729).withOpacity(0.97),
                          const Color(0xFF080D1A).withOpacity(0.99),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withOpacity(0.18),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 60,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: accentColorDim.withOpacity(0.12),
                          blurRadius: 80,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ───────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: accentColor.withOpacity(0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Animated orb with spinning ring
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, _) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accentColor.withOpacity(
                                          0.45 + 0.2 * _pulse.value,
                                        ),
                                        accentColorDim.withOpacity(0.06),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withOpacity(
                                          0.2 + 0.18 * _pulse.value,
                                        ),
                                        blurRadius: 20 + 12 * _pulse.value,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      RotationTransition(
                                        turns: _rotate,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accentColor.withOpacity(
                                                0.3,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        isGreeting
                                            ? Icons.auto_awesome
                                            : Icons.psychology,
                                        color: accentColor,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white38,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: accentColor.withOpacity(0.6),
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Eval Pills ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: pills
                                .map(
                                  (p) => _AnimatedEvalPill(
                                    pill: p,
                                    pulseAnimation: _pulse,
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // ── Content area ──────────────────────────────────────
                        if (!isGreeting &&
                            widget
                                .chatService
                                .realismEvalStreamText
                                .isNotEmpty) ...[
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                20,
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF010614),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: accentColor.withOpacity(0.07),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        AnimatedBuilder(
                                          animation: _pulse,
                                          builder: (_, _) => Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: accentColor.withOpacity(
                                                0.5 + 0.5 * _pulse.value,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'LIVE EVAL STREAM',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: accentColor.withOpacity(0.5),
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Expanded(
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: true,
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            reverse: true,
                                            child: Text(
                                              widget
                                                  .chatService
                                                  .realismEvalStreamText,
                                              style: TextStyle(
                                                color: accentColor.withOpacity(0.8),
                                                fontSize: 11.5,
                                                fontFamily: 'monospace',
                                                height: 1.65,
                                                letterSpacing: 0.15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (widget.chatService.isEvaluatingRealism || widget.chatService.isProcessingGreeting) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                children: [
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: widget.chatService.isCancellingRealismEval
                                    ? null
                                    : () => widget.chatService.cancelRealismEval(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                ),
                                      child: const Text(
                                        'Cancel Realism',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (_, _) => Text(
                                isGreeting
                                    ? 'Analyzing opening message to calibrate\nthe character\'s emotional state & relationships...'
                                    : 'Initializing evaluator...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(
                                    0.22 + 0.12 * _pulse.value,
                                  ),
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EvalPill {
  final String label;
  final IconData icon;
  final Color color;
  const _EvalPill({
    required this.label,
    required this.icon,
    required this.color,
  });
}

// ── Objective Completion Check Overlay ──────────────────────────────────────────

class _ObjectiveCheckOverlay extends StatefulWidget {
  final ChatService chatService;

  const _ObjectiveCheckOverlay({required this.chatService});

  @override
  State<_ObjectiveCheckOverlay> createState() => _ObjectiveCheckOverlayState();
}

class _ObjectiveCheckOverlayState extends State<_ObjectiveCheckOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulse;
  late final Animation<double> _rotate;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _rotate = CurvedAnimation(parent: _rotateController, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Colors.greenAccent;
    const accentColorDim = Color(0xFF16A34A);

    const pills = <_EvalPill>[
      _EvalPill(
        label: 'Objective',
        icon: Icons.flag,
        color: Colors.greenAccent,
      ),
      _EvalPill(
        label: 'Progress',
        icon: Icons.trending_up,
        color: Colors.tealAccent,
      ),
      _EvalPill(
        label: 'Completion',
        icon: Icons.check_circle_outline,
        color: Colors.lightGreenAccent,
      ),
    ];

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          type: MaterialType.transparency,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Colors.black.withOpacity(0.55),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 680,
                    maxHeight: 580,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0F1729).withOpacity(0.97),
                          const Color(0xFF080D1A).withOpacity(0.99),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withOpacity(0.18),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 60,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: accentColorDim.withOpacity(0.12),
                          blurRadius: 80,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ───────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: accentColor.withOpacity(0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Animated orb with spinning ring
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, _) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accentColor.withOpacity(
                                          0.45 + 0.2 * _pulse.value,
                                        ),
                                        accentColorDim.withOpacity(0.06),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withOpacity(
                                          0.2 + 0.18 * _pulse.value,
                                        ),
                                        blurRadius: 20 + 12 * _pulse.value,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      RotationTransition(
                                        turns: _rotate,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accentColor.withOpacity(
                                                0.3,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.flag,
                                        color: accentColor,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Objective Engine',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Evaluating objective & task completion',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white38,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: accentColor.withOpacity(0.6),
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Eval Pills ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: pills
                                .map(
                                  (p) => _AnimatedEvalPill(
                                    pill: p,
                                    pulseAnimation: _pulse,
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // ── Body ──────────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, _) => Text(
                              'Reviewing recent conversation to determine\nif objectives or tasks have been fulfilled...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(
                                  0.22 + 0.12 * _pulse.value,
                                ),
                                height: 1.65,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEvalPill extends StatelessWidget {
  final _EvalPill pill;
  final Animation<double> pulseAnimation;

  const _AnimatedEvalPill({required this.pill, required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: pill.color.withOpacity(0.07 + 0.04 * pulseAnimation.value),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pill.color.withOpacity(0.2 + 0.1 * pulseAnimation.value),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(pill.icon, size: 12, color: pill.color.withOpacity(0.85)),
            const SizedBox(width: 5),
            Text(
              pill.label,
              style: TextStyle(
                fontSize: 11,
                color: pill.color.withOpacity(0.9),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rich, phase-aware generation status bar.
/// Shows distinct visuals for each generation phase with real KoboldCPP metrics.
class _GenerationStatusBar extends StatefulWidget {
  final ChatService chatService;
  const _GenerationStatusBar({required this.chatService});

  @override
  State<_GenerationStatusBar> createState() => _GenerationStatusBarState();
}

class _GenerationStatusBarState extends State<_GenerationStatusBar> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    // Tick every second to update elapsed time displays for prefill/thinking
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final phase = cs.generationPhase;

    // Phase-specific configuration
    final (
      String label,
      Color accentColor,
      IconData icon,
      bool showMetrics,
    ) = switch (phase) {
      GenerationPhase.preparing => (
        'Assembling prompt...',
        const Color(0xFFF59E0B),
        Icons.build_rounded,
        false,
      ),
      GenerationPhase.prefilling => _prefillLabel(cs),
      GenerationPhase.thinking => _thinkingLabel(cs),
      GenerationPhase.buffering => (
        'Buffering tokens...',
        const Color(0xFF3B82F6),
        Icons.hourglass_top_rounded,
        true,
      ),
      GenerationPhase.generating => (
        'Generating response...',
        const Color(0xFF10B981),
        Icons.bolt_rounded,
        true,
      ),
      GenerationPhase.idle => (
        'Idle',
        Colors.white38,
        Icons.check_rounded,
        false,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2332),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Phase icon with accent color
              SizedBox(
                width: 16,
                height: 16,
                child:
                    phase == GenerationPhase.prefilling ||
                        phase == GenerationPhase.preparing
                    ? _PulsingIcon(icon: icon, color: accentColor)
                    : Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 10),
              // Phase label
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accentColor.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Metrics (only shown during active generation)
              if (showMetrics) ...[
                Text(
                  '${cs.tokensPerSecond.toStringAsFixed(1)} t/s',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${cs.tokensGenerated} / ${cs.maxTokens}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(cs.generationProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar — determinate when we can estimate, indeterminate otherwise
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _buildProgressBar(cs, phase, accentColor),
          ),
        ],
      ),
    );
  }

  /// Smart progress bar: determinate during generation (real data), indeterminate otherwise.
  Widget _buildProgressBar(
    ChatService cs,
    GenerationPhase phase,
    Color accentColor,
  ) {
    // During generation: use actual token progress
    if (phase == GenerationPhase.generating ||
        phase == GenerationPhase.buffering) {
      return LinearProgressIndicator(
        value: cs.generationProgress,
        minHeight: 4,
        backgroundColor: Colors.white.withOpacity(0.08),
        valueColor: AlwaysStoppedAnimation<Color>(
          Color.lerp(
            accentColor,
            const Color(0xFF10B981),
            cs.generationProgress,
          )!,
        ),
      );
    }

    // Prefill/preparing/thinking: indeterminate (no reliable progress data)
    return LinearProgressIndicator(
      minHeight: 4,
      backgroundColor: Colors.white.withOpacity(0.08),
      valueColor: AlwaysStoppedAnimation<Color>(accentColor.withOpacity(0.7)),
    );
  }

  /// Build prefill label with elapsed time and KoboldCPP perf data.
  (String, Color, IconData, bool) _prefillLabel(ChatService cs) {
    final elapsed = cs.prefillElapsedSeconds;
    final elapsedStr = elapsed >= 1 ? ' (${elapsed.toInt()}s)' : '';
    final promptTokens = cs.prefillPromptTokens;

    // Format token count: "~27K tokens" or "~4,096 tokens"
    String tokenStr = '';
    if (promptTokens > 0) {
      if (promptTokens >= 1000) {
        tokenStr =
            '~${(promptTokens / 1000).toStringAsFixed(promptTokens >= 10000 ? 0 : 1)}K tokens';
      } else {
        tokenStr = '~$promptTokens tokens';
      }
    }

    // Check for KoboldCPP perf data
    final perf = cs.lastPerfData;
    String speedStr = '';
    if (perf != null) {
      final idle = perf['idle'];
      if (idle == 0) {
        final speed = perf['last_process_speed'];
        if (speed != null && speed is num && speed > 0) {
          speedStr = '~${speed.toStringAsFixed(0)} t/s';
        }
      }
    }

    // Build detail string: "~44K tokens, ~78 t/s"
    final parts = <String>[
      if (tokenStr.isNotEmpty) tokenStr,
      if (speedStr.isNotEmpty) speedStr,
    ];
    final detail = parts.isNotEmpty ? ' — ${parts.join(', ')}' : '';

    return (
      'Processing prompt$elapsedStr$detail',
      const Color(0xFFF97316), // Orange
      Icons.memory_rounded,
      false,
    );
  }

  /// Build thinking label with elapsed time.
  (String, Color, IconData, bool) _thinkingLabel(ChatService cs) {
    final tokens = cs.tokensGenerated;
    final tps = cs.tokensPerSecond;
    String detail = '';
    if (tokens > 0 && tps > 0) {
      detail = ' — ${tps.toStringAsFixed(1)} t/s, $tokens tokens';
    } else if (tokens > 0) {
      detail = ' — $tokens tokens';
    }

    return (
      'Model is thinking...$detail',
      const Color(0xFFA855F7), // Purple
      Icons.psychology_rounded,
      false,
    );
  }
}

/// Pulsing icon animation for prefill/preparing phases.
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: Icon(widget.icon, size: 16, color: widget.color),
        );
      },
    );
  }
}

class _SettingsMenuItem extends StatelessWidget {
  const _SettingsMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
