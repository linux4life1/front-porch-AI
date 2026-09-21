// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Subject picker: Freeform / Character / Persona, group member vs group
// shot, and the Expression-pack target those resolve to. The canvas
// (generate / save / accept) stays on image_studio.dart.

part of 'image_studio.dart';

extension _ImageStudioSubject on _ImageStudioState {
  /// Build a fresh snapshot ctx for the given subject.
  ImageGenContext _makeContextForMode(ImageGenMode mode) => _buildStudioContext(
    widget,
    mode: mode,
    style: _selectedStyle,
    paradigm: _paradigm,
    characterName: _activeCharName,
    characterDescription: _activeCharDesc,
  );

  /// Switch subject: rebuild the ctx snapshot and clear the prompt box — no
  /// bleed between subjects, and no raw-description prefill.
  void _selectSubject(ImageGenMode mode) {
    rebuildState(() {
      _activeMode = mode;
      // Leaving the Character subject clears any group pick/shot.
      if (mode != ImageGenMode.characterPortrait) {
        _pickedGroupName = null;
        _pickedGroupDesc = null;
        _pickedGroupDbId = null;
        _groupShot = false;
      }
      _ctx = _makeContextForMode(mode);
      _editablePrompt = '';
    });
  }

  /// Name for the portrait context: a whole-cast label, a picked group member,
  /// else the 1:1 chat character.
  String? get _activeCharName {
    if (_groupShot) {
      return 'the group (${widget.groupCharacters.map((c) => c.name).join(', ')})';
    }
    return _pickedGroupName ?? widget.characterName;
  }

  /// Appearance for the portrait context: all members' appearances for a group
  /// shot, a picked member's, else the 1:1 character's.
  String? get _activeCharDesc {
    if (_groupShot) {
      return widget.groupCharacters
          .map((c) => '${c.name}: ${c.description}')
          .join('\n\n');
    }
    return _pickedGroupDesc ?? widget.characterDescription;
  }

  /// Portrait one chosen cast member (reliable — a single subject), or with a
  /// null [index] the caveated whole-cast "group shot".
  void _pickGroupSubject(int? index) {
    final members = widget.groupCharacters;
    if (index != null && (index < 0 || index >= members.length)) return;
    rebuildState(() {
      final m = index == null ? null : members[index];
      _pickedGroupName = m?.name;
      _pickedGroupDesc = m?.description;
      _pickedGroupDbId = m?.dbId;
      _groupShot = m == null;
      _activeMode = ImageGenMode.characterPortrait;
      _ctx = _makeContextForMode(_activeMode);
      _editablePrompt = '';
    });
  }

  /// The library id an Expression pack imports into: the picked member's, else
  /// the 1:1 character's. Null (group shot/persona/freeform) hides the button.
  String? get _packTargetDbId {
    if (_groupShot) return null;
    if (_activeMode != ImageGenMode.characterPortrait) return null;
    return _pickedGroupName != null ? _pickedGroupDbId : widget.characterDbId;
  }

  /// Launch the Expression-pack flow. An empty prompt box gets the same
  /// crafting as the Craft button (for the active subject); the dialog owns
  /// the rest: backend guard, base image, crop, generation, import.
  Future<void> _openExpressionPack() async {
    final dbId = _packTargetDbId;
    if (dbId == null) return;
    final imageGen = Provider.of<ImageGenService>(context, listen: false);
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    var basePrompt = _editablePrompt.trim();
    if (basePrompt.isEmpty) {
      // Never throws: generateSmartPrompt has its own static fallback.
      rebuildState(() => _isCrafting = true);
      basePrompt = await _craftStudioPrompt(
        widget,
        service: imageGen,
        llm: _liveStudioLlm(context, widget.llmService),
        mode: ImageGenMode.characterPortrait,
        style: _selectedStyle,
        characterName: _activeCharName,
        characterDescription: _activeCharDesc,
        // Neutral base: the per-slot emotion modifiers supply ALL the feeling;
        // a base crafted around the character's live emotion would fight them.
        currentExpression: 'neutral',
      );
      if (!mounted) return;
      rebuildState(() => _isCrafting = false);
    }
    final ok = await ExpressionPackDialog.launch(
      context,
      characterDbId: dbId,
      characterName: _activeCharName ?? '',
      repository: repo,
      candidateBase: _currentImageBytes ?? _referenceImageBytes,
      basePrompt: basePrompt,
      negativePrompt: _negativeForGen,
    );
    if (ok) widget.onExpressionsImported?.call(dbId);
  }

  bool get _isPortraitSubject =>
      _activeMode == ImageGenMode.characterPortrait ||
      _activeMode == ImageGenMode.userAvatar;

  /// The library (dbId, name) a saved LOOK targets: the picked group member's
  /// origin, else the 1:1 character. Unlike [_packTargetDbId] it does NOT gate on
  /// portrait mode — any generated image (a scene, an outfit) can be a look.
  /// Null for a group shot / persona / no character → the button hides.
  (String, String)? get _lookTarget {
    if (_groupShot) return null;
    final dbId = _pickedGroupName != null
        ? _pickedGroupDbId
        : widget.characterDbId;
    final name = _pickedGroupName ?? widget.characterName;
    if (dbId == null || name == null) return null;
    return (dbId, name);
  }

  bool get _canSaveToGallery => _lookTarget != null;

  Future<void> _craftWithLlmIfAvailable() async {
    // Re-query the live LLM at craft time (the launch snapshot may be stale).
    final liveLlm = _liveStudioLlm(context, widget.llmService, toast: true);
    if (liveLlm == null) return;
    rebuildState(() {
      _isCrafting = true;
      _error = '';
    });
    try {
      final crafted = await _craftStudioPrompt(
        widget,
        service: Provider.of<ImageGenService>(context, listen: false),
        llm: liveLlm,
        mode: _activeMode,
        style: _selectedStyle,
        characterName: widget.characterName,
        characterDescription: widget.characterDescription,
        // Box content → guidance the LLM parses in (blank Freeform → scene).
        userInstruction: _editablePrompt.trim().isNotEmpty
            ? _editablePrompt.trim()
            : null,
      );
      if (mounted) {
        rebuildState(() {
          _editablePrompt = crafted;
          _isCrafting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        rebuildState(() {
          _isCrafting = false;
          _error =
              'Craft failed: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}';
        });
      }
    }
  }
}
