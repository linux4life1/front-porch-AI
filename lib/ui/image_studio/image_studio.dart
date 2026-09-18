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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'edit_view.dart';
import 'expression_pack_dialog.dart';
import 'studio_helpers.dart';
import 'studio_mode_tabs.dart';
import 'studio_view.dart';

part 'studio_prompt_craft.dart';
part 'image_studio.subject.dart';

/// The Image Studio: one shared canvas driven by a **Subject** selector
/// (Freeform / Character / Your persona). Backend/model/size/steps/CFG/sampler/
/// scheduler/seed/LoRA controls live in the collapsible [StudioSettingsPanel].
/// Picking Character/Persona auto-fills the prompt from their appearance (via
/// the [ImagePromptBuilder]); Freeform is yours (blank + Craft distills the
/// current chat scene). Layout lives in [StudioView]; this owns the session
/// state + handlers.
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
  });

  @override
  State<ImageStudio> createState() => _ImageStudioState();
}

class _ImageStudioState extends State<ImageStudio> {
  void rebuildState(VoidCallback fn) => setState(fn);

  // Session state (owned here; no god proliferation).
  late String _selectedStyle;
  late String _paradigm;

  /// 0 = Create, 1 = Edit (the intent tabs).
  int _studioTab = 0;

  // Group-chat subject: the picked cast member, or a whole-cast "group shot".
  // Both null/false → fall back to the 1:1 character passed on the widget.
  String? _pickedGroupName;
  String? _pickedGroupDesc;
  String? _pickedGroupDbId;
  bool _groupShot = false;
  late String _editablePrompt;
  late String _negativeForGen;
  Uint8List? _currentImageBytes;
  String _error = '';
  bool _isCrafting = false;
  bool _isGenerating = false;
  bool _saving = false;

  /// The active subject; `widget.mode` is only the initial selection.
  late ImageGenMode _activeMode;

  /// Optional img2img reference (transient, never persisted). When set, Generate
  /// runs img2img at the shared imageGenDenoise strength on the local backends;
  /// remote APIs ignore it (the picker hides itself there).
  Uint8List? _referenceImageBytes;

  // History: session-local thumbnails + restoreable prompt/bytes.
  final List<({String prompt, Uint8List bytes, String style})> _history = [];

  late final ImagePromptBuilder _builder;
  late ImageGenContext _ctx;

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _selectedStyle = storage.imageGenSettings.imageGenStyle;
    _paradigm = storage.imageGenSettings.imageGenPromptParadigm;
    _negativeForGen = storage.imageGenSettings.imageGenNegativePrompt;
    _activeMode = widget.mode;
    _builder = ImagePromptBuilder(llmService: widget.llmService);
    // No boilerplate prefill for ANY subject: an empty box (with a guiding
    // hint) until the user types or taps "Write it for me". Dumping the raw
    // character description made both a poor prompt and poor UX.
    _editablePrompt = '';
    _ctx = _makeContextForMode(_activeMode);
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

  void _updateStyle(String newStyle) {
    final storage = Provider.of<StorageService>(context, listen: false);
    storage.imageGenSettings.setImageGenStyle(
      newStyle,
    ); // persist global default
    setState(() {
      _selectedStyle = newStyle;
      _reapplyStyle();
    });
  }

  void _updateParadigm(String p) => setState(() {
    _paradigm = p;
    _reapplyStyle();
  });

  void _updatePrompt(String text) => setState(() => _editablePrompt = text);
  void _updateNegative(String text) => setState(() => _negativeForGen = text);

  bool get _isBusy => _isCrafting || _isGenerating || _saving;

  Future<void> _generate() async {
    final prompt = _editablePrompt.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = '';
      _currentImageBytes = null;
    });

    final service = Provider.of<ImageGenService>(context, listen: false);
    try {
      final bytes = await service.generateImage(
        prompt: prompt,
        negativePrompt: _negativeForGen,
        isPortrait: _isPortraitSubject, // portraits orient vertically
        referenceImage: _referenceImageBytes, // img2img on local backends
      );

      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _currentImageBytes = bytes;
        if (bytes == null) {
          _error = service.statusMessage.isNotEmpty
              ? service.statusMessage
              : 'Generation returned no image';
        } else {
          _history.insert(0, (
            prompt: prompt,
            bytes: bytes,
            style: _selectedStyle,
          ));
          if (_history.length > 8) _history.removeLast();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
      }
    }
  }

  /// Pick a transient img2img reference (desktop file dialog; not persisted).
  Future<void> _pickReferenceImage() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      dialogTitle: 'Select a reference image',
      type: FileType.image,
    );
    final bytes = await result?.firstBytes();
    if (bytes != null && mounted) {
      setState(() => _referenceImageBytes = bytes);
    }
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

  Future<void> _save() async {
    if (_currentImageBytes == null) return;
    setState(() => _saving = true);
    final service = Provider.of<ImageGenService>(context, listen: false);
    final path = await service.saveImageToDisk(_currentImageBytes);
    if (mounted) {
      setState(() => _saving = false);
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to $path'),
            backgroundColor: AppColors.resolve(
              context,
              AppColors.logReady,
              AppColors.lightBorder,
            ),
          ),
        );
      }
    }
  }

  Future<void> _accept([Uint8List? bytesOverride]) async {
    final bytes = bytesOverride ?? _currentImageBytes;
    if (bytes == null) return;
    setState(() => _saving = true);
    final service = Provider.of<ImageGenService>(context, listen: false);

    // Accept only applies to portrait subjects → crop then save as an avatar.
    final croppedBytes = await ImageCropDialog.show(context, imageBytes: bytes);
    if (croppedBytes == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final path = await service.saveAvatarToDisk(
      croppedBytes,
      characterName: widget.characterName ?? widget.personaName,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (path == null) return;
    if (_activeMode == ImageGenMode.userAvatar) {
      final personaService = Provider.of<UserPersonaService>(
        context,
        listen: false,
      );
      personaService.updatePersona(
        personaService.persona.copyWith(avatarPath: path),
      );
    }
    widget.onAccept?.call(path);
    Navigator.pop(context);
  }

  /// Save the current result to the character's Avatar Gallery as a look
  /// (no crop). Create passes no override (uses the Create result); Edit passes
  /// its own bytes.
  Future<void> _saveToGallery([Uint8List? bytesOverride]) async {
    final bytes = bytesOverride ?? _currentImageBytes;
    final target = _lookTarget;
    if (bytes == null || target == null) return;
    final (dbId, name) = target;
    setState(() => _saving = true);
    try {
      await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).addLook(dbId, name, bytes);
      // A look is an avatar_images row too, so the existing library-avatars
      // refresh pushes it onto the live card → the gallery + sidebar chevrons
      // pick it up without reopening.
      widget.onExpressionsImported?.call(dbId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Avatar Gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save to gallery failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _restoreFromHistory(
    ({String prompt, Uint8List bytes, String style}) entry,
  ) {
    setState(() {
      _editablePrompt = entry.prompt;
      _selectedStyle = entry.style;
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
      await widget.onSendToChat!(bytes, _editablePrompt.trim());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image sent to chat')));
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final configured = Provider.of<ImageGenService>(
      context,
      listen: false,
    ).isConfigured;
    // Any generation (Create OR Edit) flips the shared service busy; fold it in
    // so the tabs lock and Create can't double-submit while Edit is running.
    final genBusy = context.select<ImageGenService, bool>(
      (s) => s.isGenerating,
    );

    return StudioView(
      activeMode: _activeMode,
      characterName: _activeCharName,
      groupCharacters: widget.groupCharacters,
      groupShotActive: _groupShot,
      onPickGroupMember: _pickGroupSubject,
      onPickGroupShot: () => _pickGroupSubject(null),
      selectedStyle: _selectedStyle,
      paradigm: _paradigm,
      prompt: _editablePrompt,
      negative: _negativeForGen,
      referenceBytes: _referenceImageBytes,
      currentImageBytes: _currentImageBytes,
      error: _error,
      isCrafting: _isCrafting,
      isGenerating: _isGenerating,
      saving: _saving,
      isBusy: _isBusy || genBusy,
      llmAvailable: widget.llmService != null && widget.llmService!.isReady,
      configured: configured,
      builder: _builder,
      ctx: _ctx,
      history: _history,
      onClose: () => Navigator.pop(context),
      onSelectSubject: _selectSubject,
      onStyleChanged: _updateStyle,
      onParadigmChanged: _updateParadigm,
      onPickReference: _pickReferenceImage,
      onClearReference: () => setState(() => _referenceImageBytes = null),
      onPromptChanged: _updatePrompt,
      onNegativeChanged: _updateNegative,
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
      modeTabs: StudioModeTabs(
        selected: _studioTab,
        onChanged: (i) => setState(() => _studioTab = i),
        enabled: !_isBusy && !genBusy,
      ),
      editBody: EditView(
        onSendToChat: widget.onSendToChat,
        onAcceptBytes: hasAcceptAction(_activeMode)
            ? (bytes) => _accept(bytes)
            : null,
        onSaveToGalleryBytes: _canSaveToGallery
            ? (bytes) => _saveToGallery(bytes)
            : null,
        acceptLabel: getAcceptLabel(_activeMode),
        // Pre-load the current portrait as the edit source (the user can still
        // swap in an unrelated photo via "Add photo").
        initialSourcePath: widget.characterImagePath,
      ),
    );
  }
}
