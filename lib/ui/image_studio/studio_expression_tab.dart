// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'studio_expression_tab/expression_draft_pane.dart';
import 'studio_widgets.dart';

/// Independent draft and owned results for the persistent Expressions tab.
class StudioExpressionTab extends StatefulWidget {
  const StudioExpressionTab({
    super.key,
    this.initialCharacterId,
    this.onCraftPrompt,
    this.lastStudioImage,
    this.onImported,
    this.onPackChanged,
  });

  final String? initialCharacterId;
  final Future<String> Function(CharacterCard, String?)? onCraftPrompt;
  final Uint8List? lastStudioImage;
  final ValueChanged<String>? onImported;
  final VoidCallback? onPackChanged;

  @override
  StudioExpressionTabState createState() => StudioExpressionTabState();
}

class StudioExpressionTabState extends State<StudioExpressionTab> {
  final _description = TextEditingController();
  GlobalKey<ExpressionPackDialogState> _packKey = GlobalKey();
  CharacterCard? _character;
  Uint8List? _source;
  ({Uint8List bytes, int width, int height, String? note})? _prepared;
  Set<String> _existing = {};
  String _sourceCaption = 'Character portrait';
  String _error = '';
  bool _loading = false;
  bool _frozen = false;
  bool _seeded = false;
  bool _crafting = false;
  bool _draftTouched = false;
  int _loadSequence = 0;

  bool get hasPack => _packKey.currentState?.hasPack ?? false;
  Future<bool> confirmClose() async =>
      await _packKey.currentState?.confirmDiscard() ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = context.read<CharacterRepository?>();
    if (_seeded || repository == null || repository.characters.isEmpty) return;
    _seeded = true;
    final card = repository.characters
        .where((c) => c.dbId == widget.initialCharacterId)
        .firstOrNull;
    if (card == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectCharacter(card);
    });
  }

  Future<void> selectTarget(String? id, {String? prompt}) async {
    if (_frozen || _crafting) return;
    final repository = context.read<CharacterRepository?>();
    final card = repository?.characters.where((c) => c.dbId == id).firstOrNull;
    if (card == null) return;
    if (card.dbId == _character?.dbId) {
      if (!_draftTouched && prompt != null) {
        setState(() {
          _description.text = prompt;
          _draftTouched = prompt.isNotEmpty;
        });
      }
      return;
    }
    await _selectCharacter(card);
    if (mounted && !_frozen && _character?.dbId == id) {
      setState(() {
        _description.text = prompt ?? '';
        _draftTouched = _description.text.isNotEmpty;
      });
    }
  }

  Future<String> _craftPrompt({bool automatic = false}) async {
    final card = _character;
    if (card == null) throw StateError('Choose a character first.');
    if (automatic && _description.text.trim().isNotEmpty) {
      return _description.text.trim();
    }
    final instruction = _description.text.trim();
    final callback = widget.onCraftPrompt;
    final crafted = callback != null
        ? await callback(card, instruction.isEmpty ? null : instruction)
        : await context.read<ImageGenService>().generateSmartPrompt(
            mode: ImageGenMode.characterPortrait,
            style: context
                .read<StorageService>()
                .imageGenSettings
                .imageGenStyle,
            characterName: card.name,
            characterDescription: card.description,
            currentExpression: 'neutral',
            userInstruction: instruction.isEmpty ? null : instruction,
          );
    if (mounted && identical(_character, card) && (automatic || !_frozen)) {
      setState(() {
        _description.text = crafted;
        _draftTouched = true;
      });
    }
    return crafted;
  }

  Future<void> _writePrompt() async {
    if (_frozen || _crafting || _character == null) {
      return;
    }
    setState(() {
      _crafting = true;
      _error = '';
    });
    try {
      await _craftPrompt();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not write the prompt: $error');
      }
    } finally {
      if (mounted) setState(() => _crafting = false);
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _selectCharacter(CharacterCard card) async {
    if (_frozen || _crafting) return;
    setState(() {
      _character = card;
      _description.clear();
      _draftTouched = false;
      _sourceCaption = 'Character portrait';
    });
    await _loadPortrait();
  }

  Future<void> _loadPortrait() async {
    final card = _character;
    final repository = context.read<CharacterRepository?>();
    final id = card?.dbId;
    if (id == null || repository == null || _frozen) return;
    final seq = ++_loadSequence;
    setState(() {
      _loading = true;
      _error = '';
      _prepared = null;
      _source = null;
    });
    try {
      final bytes = await packBaseImage(
        repository,
        context.read<StorageService>(),
        id,
        card!.name,
      );
      final avatars = await repository.getAvatarImages(id);
      if (!mounted || seq != _loadSequence) return;
      _existing = avatars
          .map((a) => (a.label ?? '').toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      await _prepareSource(bytes, seq: seq);
    } catch (error) {
      if (mounted && seq == _loadSequence) {
        setState(() {
          _loading = false;
          _error = 'Could not read the portrait: $error';
        });
      }
    }
  }

  Future<void> _prepareSource(Uint8List? bytes, {int? seq}) async {
    final current = seq ?? ++_loadSequence;
    setState(() {
      _loading = true;
      _prepared = null;
      _source = null;
      _error = '';
    });
    String? refusal;
    final normalized = bytes == null
        ? null
        : await preparePackBase(bytes, onRefused: (r) => refusal = r.message);
    if (!mounted || current != _loadSequence) return;
    setState(() {
      _loading = false;
      _error = bytes == null
          ? 'This card has no current portrait. Upload a source or use the last Studio picture.'
          : normalized == null
          ? refusal ?? 'This image could not be decoded.'
          : '';
      _source = normalized?.bytes;
      _prepared = normalized == null
          ? null
          : (
              bytes: normalized.bytes,
              width: normalized.width,
              height: normalized.height,
              note: normalized.converted ? kPackConvertedNote : null,
            );
      _packKey = GlobalKey();
    });
  }

  Future<void> _upload() async {
    if (_frozen) return;
    final files = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImage,
      dialogTitle: 'Choose an expression source portrait',
      type: FileType.image,
    );
    final bytes = await files?.firstBytes();
    if (!mounted || bytes == null || _frozen) return;
    setState(() => _sourceCaption = 'Uploaded portrait');
    await _prepareSource(bytes);
  }

  Future<void> _newPack() async {
    if (!await confirmClose() || !mounted) return;
    setState(() {
      _packKey = GlobalKey();
      _frozen = false;
    });
    widget.onPackChanged?.call();
    if (_sourceCaption == 'Character portrait') {
      await _loadPortrait();
    } else {
      final id = _character?.dbId;
      final repository = context.read<CharacterRepository?>();
      if (id == null || repository == null) return;
      setState(() => _loading = true);
      try {
        final avatars = await repository.getAvatarImages(id);
        if (!mounted) return;
        setState(() {
          _existing = avatars
              .map((a) => (a.label ?? '').toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
          _loading = false;
        });
      } catch (error) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Could not refresh existing expressions: $error';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<CharacterRepository?>();
    final settings = context.watch<StorageService>().imageGenSettings;
    final imageGen = context.watch<ImageGenService>();
    final backend = settings.imageGenBackend;
    final edit =
        backend == 'comfyui' ||
        backend == 'remote' ||
        ImageReferenceResolver.packEditMode(settings);
    final prepared = _prepared;
    final card = _character;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OtherExpressionPack(
          owned: (run) => _packKey.currentState?.owns(run) ?? false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Expressions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              if (hasPack)
                Tooltip(
                  message:
                      'Clear pack results and unlock the target, prompt, and source. Imported expressions stay in the library.',
                  child: TextButton(
                    onPressed: _loading || _crafting ? null : _newPack,
                    child: const Text('Reset pack'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final draft = ExpressionDraftPane(
                repository: repository,
                card: card,
                edit: edit,
                frozen: _frozen,
                loading: _loading,
                crafting: _crafting,
                description: _description,
                sourceCaption: _sourceCaption,
                source: _source,
                lastStudioImage: widget.lastStudioImage,
                error: _error,
                onSelectCharacter: _selectCharacter,
                onDraftEdited: () => setState(() => _draftTouched = true),
                onWritePrompt: _writePrompt,
                onUsePortrait: () {
                  setState(() => _sourceCaption = 'Character portrait');
                  _loadPortrait();
                },
                onUpload: _upload,
                onUseLast: () {
                  setState(() => _sourceCaption = 'Last Studio picture');
                  _prepareSource(widget.lastStudioImage);
                },
              );
              final pack =
                  prepared == null || card?.dbId == null || repository == null
                  ? const Center(
                      child: Text(
                        'Choose a character and source portrait to set up expressions.',
                      ),
                    )
                  : ExpressionPackDialog.workspace(
                      key: _packKey,
                      characterDbId: card!.dbId!,
                      characterName: card.name,
                      repository: repository,
                      storage: context.read<StorageService>(),
                      imageGen: imageGen,
                      baseImage: prepared.bytes,
                      baseWidth: prepared.width,
                      baseHeight: prepared.height,
                      basePrompt: _description.text.trim(),
                      preparePrompt: () => _craftPrompt(automatic: true),
                      preparingPrompt: _crafting,
                      negativePrompt: settings.imageGenNegativePrompt,
                      existingEmotions: _existing,
                      note: prepared.note,
                      onSessionChanged: (hasSession) {
                        setState(() => _frozen = hasSession);
                        widget.onPackChanged?.call();
                      },
                      onImported: () => widget.onImported?.call(card.dbId!),
                      onDiscard: _newPack,
                    );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: draft),
                    Expanded(flex: 2, child: pack),
                  ],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 440, child: draft),
                    SizedBox(height: 580, child: pack),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
