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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/desktop_spell_check_service.dart';
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
import 'package:front_porch_ai/ui/dialogs/image_gen_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/kobold_log_dialog.dart';
import 'package:front_porch_ai/ui/pages/fork_to_group_page.dart';

class StyledTextController extends TextEditingController
    implements SpellCheckResultsProvider {
  static final _pattern = RegExp(r'("[^"]*")|(\*[^*]*\*)');

  // Custom spell check cache (populated by the debounced spell runner).
  String? _lastCheckedText;
  final List<TextRange> _misspelledRanges = [];
  final Map<int, List<String>> _suggestions = {};

  void applySpellResults(String checkedText, List<SuggestionSpan> spans) {
    _lastCheckedText = checkedText;
    _misspelledRanges
      ..clear()
      ..addAll(spans.map((s) => s.range));
    _misspelledRanges.sort((a, b) => a.start.compareTo(b.start));
    _suggestions
      ..clear()
      ..addEntries(spans.map((s) => MapEntry(s.range.start, s.suggestions)));
  }

  void clearSpellResults() {
    _lastCheckedText = null;
    _misspelledRanges.clear();
    _suggestions.clear();
  }

  @override
  SpellCheckResults? get spellCheckResults {
    if (_misspelledRanges.isEmpty || _lastCheckedText != text) return null;
    return SpellCheckResults(
      _lastCheckedText!,
      _misspelledRanges.map((r) {
        return SuggestionSpan(r, _suggestions[r.start] ?? <String>[]);
      }).toList(),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final matches = _pattern.allMatches(text);
    final useSpellCheck =
        _lastCheckedText == text && _misspelledRanges.isNotEmpty;

    // Build a list of (text, style, offset) for each colored segment.
    final segments = <({String text, TextStyle? style, int offset})>[];
    int lastEnd = 0;

    void addSegment(String segText, TextStyle? segStyle, int segOffset) {
      segments.add((text: segText, style: segStyle, offset: segOffset));
    }

    if (matches.isEmpty) {
      addSegment(text, style, 0);
    } else {
      for (final match in matches) {
        if (match.start > lastEnd) {
          addSegment(text.substring(lastEnd, match.start), style, lastEnd);
        }
        final matchText = match.group(0)!;
        if (matchText.startsWith('"')) {
          addSegment(
            matchText,
            style?.copyWith(
              color: AppColors.resolve(
                context,
                Colors.amberAccent,
                const Color(0xFFB45309),
              ),
              fontWeight: FontWeight.w500,
            ),
            match.start,
          );
        } else {
          addSegment(
            matchText,
            style?.copyWith(
              color: AppColors.resolve(
                context,
                const Color(0xFF90CAF9),
                const Color(0xFF1565C0),
              ),
            ),
            match.start,
          );
        }
        lastEnd = match.end;
      }
      if (lastEnd < text.length) {
        addSegment(text.substring(lastEnd), style, lastEnd);
      }
    }

    if (!useSpellCheck) {
      return TextSpan(
        children: segments
            .map((s) => TextSpan(text: s.text, style: s.style))
            .toList(),
        style: style,
      );
    }

    // Apply spell check: split colored segments at misspelled boundaries
    // and add wavy red decoration to the intersecting portions while
    // preserving each segment's base color.
    const misspelledTextStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Colors.redAccent,
      decorationStyle: TextDecorationStyle.wavy,
    );

    final children = <TextSpan>[];
    for (final seg in segments) {
      final spanStart = seg.offset;
      final spanEnd = seg.offset + seg.text.length;

      // Collect intersecting misspelled ranges in this segment.
      final intersecting = <({int start, int end})>[];
      for (final range in _misspelledRanges) {
        final isectStart = range.start > spanStart ? range.start : spanStart;
        final isectEnd = range.end < spanEnd ? range.end : spanEnd;
        if (isectStart < isectEnd) {
          intersecting.add((start: isectStart, end: isectEnd));
        }
      }

      if (intersecting.isEmpty) {
        children.add(TextSpan(text: seg.text, style: seg.style));
        continue;
      }

      int splitAt = 0;
      for (final isect in intersecting) {
        final localStart = (isect.start - seg.offset).clamp(0, seg.text.length);
        if (localStart > splitAt) {
          children.add(
            TextSpan(
              text: seg.text.substring(splitAt, localStart),
              style: seg.style,
            ),
          );
        }
        final localEnd = (isect.end - seg.offset).clamp(0, seg.text.length);
        children.add(
          TextSpan(
            text: seg.text.substring(localStart, localEnd),
            style: seg.style?.merge(misspelledTextStyle) ?? misspelledTextStyle,
          ),
        );
        splitAt = localEnd;
      }
      if (splitAt < seg.text.length) {
        children.add(
          TextSpan(text: seg.text.substring(splitAt), style: seg.style),
        );
      }
    }

    return TextSpan(children: children, style: style);
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final StyledTextController _controller = StyledTextController();
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
  final DesktopSpellCheckService _spellService = DesktopSpellCheckService();
  Timer? _spellDebounce;

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

    // Listen for custom spell check triggered by text changes.
    _controller.addListener(_onComposerTextChanged);

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
    _spellDebounce?.cancel();
    _controller.removeListener(_onComposerTextChanged);
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

  void _onComposerTextChanged() {
    _spellDebounce?.cancel();
    _spellDebounce = Timer(const Duration(milliseconds: 300), _trySpellCheck);
  }

  bool _spellCheckInFlight = false;

  void _trySpellCheck() {
    if (!_spellCheckInFlight) {
      _runCustomSpellCheck();
    }
    // If in-flight, the completion handler will auto-retry below.
  }

  Future<void> _runCustomSpellCheck() async {
    if (_spellCheckInFlight) return;
    _spellCheckInFlight = true;
    final text = _controller.text;
    try {
      if (text.trim().isEmpty) {
        _controller.clearSpellResults();
        if (mounted) setState(() {});
        return;
      }
      final locale = PlatformDispatcher.instance.locale;
      final results = await _spellService.fetchSpellCheckSuggestions(
        locale,
        text,
      );
      if (!mounted) return;
      if (text != _controller.text) return;
      if (results != null && results.isNotEmpty) {
        _controller.applySpellResults(text, results);
      } else {
        _controller.clearSpellResults();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Spell check error: $e');
      _controller.clearSpellResults();
      if (mounted) setState(() {});
    } finally {
      _spellCheckInFlight = false;
      // If text changed during the request, schedule a retry.
      if (_controller.text != text) {
        _spellDebounce?.cancel();
        _spellDebounce = Timer(
          const Duration(milliseconds: 300),
          _trySpellCheck,
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
            onBackgroundImageError: character.imagePath != null
                ? (_, _) {}
                : null,
            child: character.imagePath == null
                ? const Icon(Icons.person)
                : null,
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
          // Stacked avatars (with emotion rings when group realism is active)
          SizedBox(
            width: 24.0 + (chars.length.clamp(0, 4) - 1) * 16,
            height: 32,
            child: Stack(
              children: [
                for (int i = 0; i < chars.length.clamp(0, 4); i++)
                  Positioned(
                    left: i * 16.0,
                    child: Tooltip(
                      message: () {
                        if (!chatService.isGroupRealismActive) {
                          return chars[i].name;
                        }
                        final emo = chatService.getEmotionForGroupCharacter(
                          chars[i],
                        );
                        final fix = chatService.getFixationForGroupCharacter(
                          chars[i],
                        );
                        final base =
                            '${chars[i].name}${emo != null ? ' • $emo' : ''}';
                        return fix != null && fix.isNotEmpty
                            ? '$base\nFixated: $fix'
                            : base;
                      }(),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: chatService.isGroupRealismActive
                              ? Border.all(
                                  color: EmotionLabels.ringColor(
                                    chatService.getEmotionForGroupCharacter(
                                      chars[i],
                                    ),
                                  ),
                                  width: 2.0,
                                )
                              : null,
                        ),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: _groupCharacterColor(i),
                          backgroundImage: chars[i].imagePath != null
                              ? FileImage(
                                  _resolveCharImage(chars[i].imagePath!),
                                )
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
                        _showEvolutionDialog(context, chatService);
                      } else if (value == 'context') {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              ContextViewerDialog(chatService: chatService),
                        );
                      } else if (value == 'fork_group') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForkToGroupPage(),
                          ),
                        );
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
                      if (!storage.imageGenEnabled) {
                        return const SizedBox.shrink();
                      }
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
                                Icon(
                                  Icons.wallpaper,
                                  size: 20,
                                  color: Colors.teal,
                                ),
                                SizedBox(width: 12),
                                Text('Chat Background'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ImageGenMode.userAvatar,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.orange,
                                ),
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
                AuthorNoteSection(chatService: chatService),
                const SizedBox(height: 16),

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
        border: Border(
          left: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Settings buttons ──
          Container(
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
                          side: BorderSide(
                            color: AppColors.borderOf(
                              context,
                            ).withValues(alpha: 0.4),
                          ),
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
                          side: BorderSide(
                            color: AppColors.borderOf(
                              context,
                            ).withValues(alpha: 0.4),
                          ),
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
                          side: BorderSide(
                            color: AppColors.borderOf(
                              context,
                            ).withValues(alpha: 0.4),
                          ),
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
                      side: BorderSide(
                        color: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.4),
                      ),
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
                              value:
                                  _dragDirectorDelay ?? storage.directorDelay,
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
          ),

          // ── Author's Note ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: AuthorNoteSection(chatService: chatService),
          ),

          // ── Chaos Mode (global for the group chat) ──
          Consumer<ChatService>(
            builder: (context, chat, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChaosModeSection(
                  chat: chat,
                  onSpinRequested: () => _showChanceTimeOverlay(context),
                ),
                // Scene time tracker (day of week + time of day + nudges + dots)
                // Placed here with Chaos as they are both global/scene-level state.
                SceneTimeSection(chat: chat),
              ],
            ),
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
              'Tap a character to focus their full state (emotion, bond, needs, fixation)',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context).withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: chars.length,
              itemBuilder: (context, index) {
                final ch = chars[index];
                final color = _groupCharacterColor(index);
                final isNext = chatService.nextCharacter?.name == ch.name;
                final evolutionCount = chatService.getEvolutionCountFor(ch);
                final canRemove = chars.length > 2 && !chatService.isGenerating;

                File? avatarFile;
                if (ch.imagePath != null) {
                  try {
                    avatarFile = _resolveCharImage(ch.imagePath!);
                  } catch (_) {}
                }

                return GroupMemberCard(
                  character: ch,
                  chatService: chatService,
                  avatarColor: color,
                  isNextSpeaker: isNext,
                  isExpanded:
                      isNext, // current/next speaker gets the full 1:1-parity rich view
                  onTap: chatService.isGenerating
                      ? () {}
                      : () => chatService.setNextCharacter(ch),
                  avatarFile: avatarFile,
                  evolutionCount: evolutionCount,
                  canRemove: canRemove,
                  onRemove: canRemove
                      ? () async {
                          final groupRepo = Provider.of<GroupChatRepository>(
                            context,
                            listen: false,
                          );
                          await chatService.removeCharacterFromGroup(
                            ch,
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
                        initialCharacter: ch,
                      ),
                    );
                  },
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

          // ── Lorebook Triggers & Chat Summary moved below the character list
          // (global sections that apply to the whole group scene).
          const SizedBox(height: 8),
          GroupLorebookSection(chatService: chatService),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SummarySection(chatService: chatService),
          ),
        ],
      ),
    );
  }

  /// Show dialog to add a character to the active group chat.
  void _showAddCharacterToGroupDialog(
    BuildContext context,
    ChatService chatService,
  ) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    // characterIds removed from GroupChat (decoupled). Use chatService or group members for active set.
    final currentIds =
        <String>[]; // TODO: derive from active group members when needed

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
