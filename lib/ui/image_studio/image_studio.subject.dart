// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Subject picker: Freeform / Character / Persona, group member vs group
// shot, and the Expression-pack target those resolve to. The canvas
// (generate / save / accept) stays on image_studio.dart.

part of 'image_studio.dart';

extension _ImageStudioSubject on _ImageStudioState {
  /// Switch subject and clear the prompt box — no bleed between subjects,
  /// and no raw-description prefill.
  void _selectSubject(ImageGenMode mode) {
    rebuildState(() {
      _activeMode = mode;
      // Leaving the Character subject clears any group pick/shot.
      if (mode != ImageGenMode.characterPortrait) {
        _pickedGroupName = null;
        _pickedGroupDbId = null;
        _groupShot = false;
      }
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

  /// Portrait one chosen cast member (reliable — a single subject), or with a
  /// null [index] the caveated whole-cast "group shot".
  void _pickGroupSubject(int? index) {
    final members = widget.groupCharacters;
    if (index != null && (index < 0 || index >= members.length)) return;
    rebuildState(() {
      final m = index == null ? null : members[index];
      _pickedGroupName = m?.name;
      _pickedGroupDbId = m?.dbId;
      _groupShot = m == null;
      _activeMode = ImageGenMode.characterPortrait;
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
  void _openExpressionPack() => rebuildState(() => _studioTab = 2);

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
