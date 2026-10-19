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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'studio_shell/studio_shell.dart';
import 'studio_widgets.dart';

/// The Image Studio: one shared canvas driven by a **Subject** selector
/// (Freeform / Character / Your persona). Backend, model, size, steps, LoRA,
/// seed and the rest of the generation settings live on the studio desk. The
/// prompt box starts empty; "Write it for me" crafts one with the LLM (from
/// the character, or for Freeform the current chat scene). Layout lives in
/// [StudioView]; this owns the session state + handlers.
class ImageStudio extends StatefulWidget {
  final ImageGenMode mode;
  final String? customPrompt;
  final String? lastMessage;
  final String? characterName;
  final String? characterDescription;
  final String? characterPersonality; // signature compat only

  /// Group-chat cast (name + appearance + library id when resolvable). Empty
  /// for 1:1 chats. When non-empty, the Subject picker offers a per-member
  /// portrait picker plus a caveated whole-cast "Group shot".
  final List<({String name, String description, String? dbId})> groupCharacters;
  final String? scenario;
  final String? worldInfo;
  final String? personaName;
  final String? personaText;
  final List<String>? recentMessages;
  final LLMService? llmService;
  final void Function(String path)? onAccept;

  /// When provided (chat launches), the result view offers "Send to chat":
  /// the callback attaches the image bytes + final prompt to the conversation.
  final Future<void> Function(Uint8List bytes, String prompt)? onSendToChat;

  // Richer context wired from the chat launch for better prompts.
  final String? currentExpression;
  final String? timeOfDay;
  final String? lightingHint;
  final bool isGroupNonObserver;
  final String? currentSpeakerId;

  /// Library id of the 1:1 character — the Expression-pack import target.
  final String? characterDbId;

  /// The 1:1 character's current portrait path — pre-loaded as the Edit tab's
  /// source so "change this portrait" starts from the existing avatar.
  final String? characterImagePath;

  /// Fires after a pack import so the launcher refreshes the live card.
  final void Function(String characterDbId)? onExpressionsImported;

  /// Home launch: picks the Character subject from the library. True = chosen.
  final Future<bool> Function()? onChooseCharacter;

  const ImageStudio({
    super.key,
    required this.mode,
    this.customPrompt,
    this.lastMessage,
    this.characterName,
    this.characterDescription,
    this.characterPersonality,
    this.groupCharacters = const [],
    this.scenario,
    this.worldInfo,
    this.personaName,
    this.personaText,
    this.recentMessages,
    this.llmService,
    this.onAccept,
    this.onSendToChat,
    this.currentExpression,
    this.timeOfDay,
    this.lightingHint,
    this.isGroupNonObserver = false,
    this.currentSpeakerId,
    this.characterDbId,
    this.characterImagePath,
    this.onExpressionsImported,
    this.onChooseCharacter,
  });

  @override
  State<ImageStudio> createState() => _ImageStudioState();
}

class _ImageStudioState extends State<ImageStudio> {
  late String _selectedStyle;
  late String _paradigm;

  /// 0 = Create, 1 = Edit, 2 = Expressions, 3 = Batch.
  int _studioTab = 0;
  final _expressionsKey = GlobalKey<StudioExpressionTabState>();
  bool _allowClose = false;
  late final StudioSubject _subject = StudioSubject(widget.mode);
  late String _editablePrompt;
  Uint8List? _currentImageBytes;
  Uint8List? _lastStudioImage;
  String _error = '';
  final _deskStamp = StudioDeskStamp();
  bool _isCrafting = false;
  bool _isGenerating = false;
  bool _saving = false;

  /// Optional img2img reference (transient, never persisted). When set, Generate
  /// runs img2img at the shared imageGenDenoise strength on the local backends;
  /// remote APIs ignore it (the picker hides itself there).
  Uint8List? _referenceImageBytes;

  // History: session-local thumbnails + restoreable prompt/bytes.
  final List<({String prompt, Uint8List bytes, String style})> _history = [];

  late final ImagePromptBuilder _builder;
  StorageService? _storage;

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _selectedStyle = storage.imageGenSettings.imageGenStyle;
    _paradigm = storage.imageGenSettings.imageGenPromptParadigm;
    _builder = ImagePromptBuilder(llmService: widget.llmService);
    // No prefill for any subject: a raw character description is a poor prompt.
    _editablePrompt = '';
    _storage = storage..addListener(_followStyleSettings);
  }

  @override
  void dispose() {
    _storage?.removeListener(_followStyleSettings);
    super.dispose();
  }

  /// The style and prompt format are chosen on the desk and stored as the
  /// defaults. A change there re-applies to the prompt already written, as
  /// choosing them here always did.
  void _followStyleSettings() {
    final settings = _storage?.imageGenSettings;
    if (settings == null || !mounted) return;
    if (settings.imageGenStyle == _selectedStyle &&
        settings.imageGenPromptParadigm == _paradigm) {
      return;
    }
    setState(() {
      _selectedStyle = settings.imageGenStyle;
      _paradigm = settings.imageGenPromptParadigm;
      _reapplyStyle();
    });
  }

  /// Re-apply the live style suffix to a non-empty prompt so Generate sends the
  /// currently chosen style. No-op on an empty box (avoids glue+style synthesis).
  void _reapplyStyle() {
    if (_editablePrompt.trim().isEmpty) return;
    _editablePrompt = reapplyCurrentStyleSuffix(
      _editablePrompt,
      _selectedStyle,
      _paradigm,
      _builder,
    );
  }

  void _updatePrompt(String text) => setState(() => _editablePrompt = text);

  bool get _isBusy => _isCrafting || _isGenerating || _saving;

  Future<void> _generate() async {
    if (context.read<ImageGenService>().isGenerating) return;
    final prompt = _editablePrompt.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Write a prompt first.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = '';
      _currentImageBytes = null;
    });

    final result = await generateStudioImage(
      Provider.of<ImageGenService>(context, listen: false),
      prompt: prompt,
      isPortrait: _subject.isPortrait, // portraits orient vertically
      referenceImage: _referenceImageBytes, // img2img on local backends
    );
    if (!mounted) return;
    setState(() {
      _isGenerating = false;
      final bytes = _currentImageBytes = result.bytes;
      if (bytes == null) {
        _error = result.error;
      } else {
        _lastStudioImage = bytes;
        _history.insert(0, (
          prompt: prompt,
          bytes: bytes,
          style: _selectedStyle,
        ));
        if (_history.length > 8) _history.removeLast();
      }
    });
  }

  Future<void> _pickReferenceImage() async {
    final bytes = await pickStudioReference(context);
    if (bytes != null && mounted) setState(() => _referenceImageBytes = bytes);
  }

  Future<void> _variations() async {
    if (_currentImageBytes == null) return;
    final currentPrompt = _editablePrompt.trim();
    if (currentPrompt.isEmpty) return;
    // Nudge the prompt for variety without permanently mutating user text.
    final prevPrompt = _editablePrompt;
    setState(() => _editablePrompt = '$currentPrompt, variation');
    await _generate();
    if (mounted) setState(() => _editablePrompt = prevPrompt);
  }

  /// Return to the workspace with the current prompt for tweaking.
  void _editAndRegen() => setState(() {
    _currentImageBytes = null;
    _error = '';
  });

  void _setSaving(bool saving) => setState(() => _saving = saving);

  Future<void> _save() async {
    final bytes = _currentImageBytes;
    if (bytes == null) return;
    await saveStudioImage(context, bytes, onSaving: _setSaving);
  }

  Future<void> _accept([Uint8List? bytesOverride]) async {
    final bytes = bytesOverride ?? _currentImageBytes;
    if (bytes == null) return;
    final path = await acceptStudioAvatar(
      context,
      bytes,
      characterName: widget.characterName ?? widget.personaName,
      forPersona: _subject.mode == ImageGenMode.userAvatar,
      onSaving: _setSaving,
    );
    if (path == null) return;
    widget.onAccept?.call(path);
    await _closeStudio();
  }

  /// Save the current result to the character's Avatar Gallery as a look
  /// (no crop). Create passes no override (uses the Create result); Edit passes
  /// its own bytes.
  Future<void> _saveToGallery([Uint8List? bytesOverride]) async {
    final bytes = bytesOverride ?? _currentImageBytes;
    final target = _lookTarget;
    if (bytes == null || target == null) return;
    final (dbId, name) = target;
    await saveStudioLook(
      context,
      bytes,
      dbId: dbId,
      name: name,
      onSaving: _setSaving,
      onSaved: (id) => widget.onExpressionsImported?.call(id),
    );
  }

  void _restoreFromHistory(
    ({String prompt, Uint8List bytes, String style}) entry,
  ) {
    setState(() {
      _editablePrompt = entry.prompt;
      _selectedStyle = restorableStyle(entry.style, _selectedStyle);
      _currentImageBytes = entry.bytes;
      _error = '';
    });
  }

  /// The "Send to chat" action, or null when not launched from a conversation.
  VoidCallback? get _sendToChat {
    if (widget.onSendToChat == null) return null;
    return () async {
      final bytes = _currentImageBytes;
      if (bytes == null) return;
      await sendStudioImageToChat(
        context,
        widget.onSendToChat!,
        bytes,
        _editablePrompt.trim(),
      );
    };
  }

  /// A refusal from the last generate no longer applies once the graph or a
  /// model file has been changed on the desk.
  void _dropStaleError() {
    final settings = context.read<StorageService>().imageGenSettings;
    if (!_deskStamp.changed(settings) || _error.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _error.isNotEmpty) setState(() => _error = '');
    });
  }

  /// Switch subject and clear the prompt box — no bleed between subjects,
  /// and no raw-description prefill.
  void _selectSubject(ImageGenMode mode) => setState(() {
    _subject.select(mode);
    _editablePrompt = '';
  });

  void _pickGroupSubject(int? index) {
    final members = widget.groupCharacters;
    if (index != null && (index < 0 || index >= members.length)) return;
    setState(() {
      _subject.pickGroup(index == null ? null : members[index]);
      _editablePrompt = '';
    });
  }

  String? get _packTargetDbId => _subject.packTargetDbId(widget.characterDbId);

  (String, String)? get _lookTarget =>
      _subject.lookTarget(widget.characterDbId, widget.characterName);

  bool get _canSaveToGallery => _lookTarget != null;

  void _openExpressionPack() {
    final target = _packTargetDbId;
    final prompt = _editablePrompt;
    setState(() => _studioTab = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _expressionsKey.currentState?.selectTarget(target, prompt: prompt);
      }
    });
  }

  Future<void> _craftWithLlmIfAvailable() => craftIntoPromptBox(
    context,
    widget,
    mode: _subject.mode,
    style: _selectedStyle,
    box: _editablePrompt,
    onStart: () => setState(() {
      _isCrafting = true;
      _error = '';
    }),
    onCrafted: (crafted) => setState(() {
      _editablePrompt = crafted;
      _isCrafting = false;
    }),
    onFailed: (message) => setState(() {
      _isCrafting = false;
      _error = message;
    }),
  );

  Future<void> _closeStudio() async {
    if (!await (_expressionsKey.currentState?.confirmClose() ??
            Future.value(true)) ||
        !mounted) {
      return;
    }
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    _dropStaleError();
    // Any generation (Create OR Edit) flips the shared service busy; fold it in
    // so Create cannot submit while another workspace is generating.
    final genBusy = context.select<ImageGenService, bool>(
      (s) => s.isGenerating,
    );

    return PopScope(
      canPop: _allowClose || !(_expressionsKey.currentState?.hasPack ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeStudio();
      },
      child: StudioView(
        activeMode: _subject.mode,
        characterName: _subject.charName(
          widget.groupCharacters,
          widget.characterName,
        ),
        groupCharacters: widget.groupCharacters,
        groupShotActive: _subject.groupShot,
        onPickGroupMember: _pickGroupSubject,
        onPickGroupShot: () => _pickGroupSubject(null),
        onChooseCharacter: widget.onChooseCharacter == null
            ? null
            : () async {
                if (await widget.onChooseCharacter!() && mounted) {
                  _selectSubject(ImageGenMode.characterPortrait);
                }
              },
        prompt: _editablePrompt,
        referenceBytes: _referenceImageBytes,
        currentImageBytes: _currentImageBytes,
        error: _error,
        generating: _isGenerating,
        crafting: _isCrafting,
        saving: _saving,
        isBusy: _isBusy || genBusy,
        history: _history,
        onClose: _closeStudio,
        onSelectSubject: _selectSubject,
        onPickReference: _pickReferenceImage,
        onClearReference: () => setState(() => _referenceImageBytes = null),
        onPromptChanged: _updatePrompt,
        onCraftLlm: _craftWithLlmIfAvailable,
        onExpressionPack: _packTargetDbId == null ? null : _openExpressionPack,
        onGenerate: _generate,
        onSave: _save,
        onAccept: _accept,
        onVariations: _variations,
        onEditRegen: _editAndRegen,
        onSendToChat: _sendToChat,
        onSaveToGallery: _canSaveToGallery ? _saveToGallery : null,
        onRestore: _restoreFromHistory,
        showEdit: _studioTab == 1,
        workspaceIndex: _studioTab,
        draftBusy: _isBusy,
        expressionBody: StudioExpressionTab(
          key: _expressionsKey,
          initialCharacterId: _packTargetDbId,
          onCraftPrompt: (card, instruction) => craftPackBasePrompt(
            context,
            widget,
            card,
            instruction,
            style: _selectedStyle,
          ),
          lastStudioImage: _lastStudioImage,
          onImported: widget.onExpressionsImported,
          onPackChanged: () => setState(() {}),
        ),
        batchBody: _studioTab == 3
            ? const ImageBatchesPage(embedded: true)
            : null,
        modeTabs: StudioModeTabs(
          selected: _studioTab,
          onChanged: (i) {
            if (i == 2) {
              _openExpressionPack();
            } else {
              setState(() => _studioTab = i);
            }
          },
        ),
        editBody: EditView(
          key: ValueKey(widget.characterImagePath),
          onResultImage: (bytes) => setState(() => _lastStudioImage = bytes),
          onSendToChat: widget.onSendToChat,
          onAcceptBytes: hasAcceptAction(_subject.mode)
              ? (bytes) => _accept(bytes)
              : null,
          onSaveToGalleryBytes: _canSaveToGallery
              ? (bytes) => _saveToGallery(bytes)
              : null,
          acceptLabel: getAcceptLabel(_subject.mode),
          // Pre-load the current portrait as the edit source (the user can still
          // swap in an unrelated photo via "Add photo").
          initialSourcePath: widget.characterImagePath,
        ),
      ),
    );
  }
}
