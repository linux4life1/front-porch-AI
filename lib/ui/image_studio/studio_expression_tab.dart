// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'studio_widgets.dart';

part 'studio_expression_tab.view.dart';

/// Independent draft and owned results for the persistent Expressions tab.
class StudioExpressionTab extends StatefulWidget {
  const StudioExpressionTab({
    super.key,
    this.initialCharacterId,
    this.groupCharacterIds = const [],
    this.lastStudioImage,
    this.onImported,
    this.onPackChanged,
  });

  final String? initialCharacterId;
  final List<String> groupCharacterIds;
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
  String _sourceCaption = 'Current card portrait';
  String _error = '';
  bool _loading = false;
  bool _frozen = false;
  bool _seeded = false;
  int _loadSequence = 0;

  void _setWorkspaceState(VoidCallback fn) => setState(fn);

  bool get hasPack => _packKey.currentState?.hasPack ?? false;
  Future<bool> confirmClose() async =>
      await _packKey.currentState?.confirmDiscard() ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = context.read<CharacterRepository?>();
    if (_seeded || repository == null || repository.characters.isEmpty) return;
    _seeded = true;
    final ids = [widget.initialCharacterId, ...widget.groupCharacterIds];
    final card =
        [
          for (final id in ids)
            ...repository.characters.where((c) => c.dbId == id),
        ].firstOrNull ??
        repository.characters.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectCharacter(card);
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _selectCharacter(CharacterCard card) async {
    if (_frozen) return;
    setState(() {
      _character = card;
      _description.text = card.description;
      _sourceCaption = 'Current card portrait';
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
      final bytes = await packCurrentPortraitImage(
        repository,
        context.read<StorageService>(),
        id,
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
      _source = bytes;
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
    final files = await PickerPrefs.pickFiles(
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
    if (_sourceCaption == 'Current card portrait') {
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
  Widget build(BuildContext context) => _buildWorkspace(context);
}
