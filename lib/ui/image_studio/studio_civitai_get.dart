// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:front_porch_ai/services/image/civitai_search_pages.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'studio_civitai_base.dart';
import 'studio_civitai_card.dart';
import 'studio_civitai_detail.dart';
import 'studio_civitai_install.dart';
import 'studio_civitai_key.dart';

export 'package:front_porch_ai/services/image/civitai_search_pages.dart'
    show CivitaiSearchCall;

part 'studio_civitai_get_base.dart';
part 'studio_civitai_get_search.dart';

/// CivitAI search. A hit is downloaded into the saved models folder.
/// The search title is not stored as the installed file name.
class StudioCivitaiGet extends StatefulWidget {
  const StudioCivitaiGet({
    super.key,
    required this.lora,
    required this.adult,
    required this.adultAllowed,
    required this.backend,
    required this.onInstalled,
    this.onAdultChanged,
    this.onSaveKey,
    this.searchCall = civitaiHttpSearch,
    this.versionFetch = fetchCivitaiVersion,
    this.saveCall = saveCivitaiToDisk,
  });

  final bool lora;
  final bool adult;

  /// The app's adult setting. While it is off the adult box is not shown and
  /// nothing is searched or downloaded from civitai.red.
  final bool adultAllowed;
  final String backend;
  final ValueChanged<String> onInstalled;
  final ValueChanged<bool>? onAdultChanged;
  final Future<String?> Function(String token)? onSaveKey;
  final CivitaiSearchCall searchCall;
  final CivitaiVersionFetch versionFetch;
  final CivitaiSaveCall saveCall;

  @override
  State<StudioCivitaiGet> createState() => _StudioCivitaiGetState();
}

class _StudioCivitaiGetState extends State<StudioCivitaiGet> {
  final TextEditingController _query = TextEditingController();
  late final CivitaiKeyController _keys = CivitaiKeyController(
    onSaveKey: widget.onSaveKey,
  );
  String _base = '';
  final TextEditingController _baseText = TextEditingController();
  final FocusNode _baseFocus = FocusNode();
  String _baseQuery = '';
  bool _baseShowsLabel = false;
  String? _baseNote;
  bool _installedOnly = false;
  List<String> _modelFiles = const [];
  List<String> _localNames = const [];
  bool _scanning = true;
  List<CivitaiModelRow> _rows = const [];

  /// What the rows on screen were searched for, and where Load more starts.
  ({String query, String base, bool adult})? _asked;
  String? _cursor;
  String? _error;
  bool _searching = false;
  bool _needFolder = false;
  String? _offerFolder;
  String? _progressName;
  int _got = 0;
  int? _total;
  int _searchSeq = 0;
  CivitaiCancel? _cancel;
  late bool _adult = widget.adult;

  bool get _downloading => _progressName != null;
  bool get _adultNow => widget.adultAllowed && _adult;

  @override
  void initState() {
    super.initState();
    _watchBaseField();
    unawaited(_loadKeys());
    unawaited(_noteFolder());
  }

  /// A key that cannot be read is shown in the key box, where it stays; it
  /// does not stop an ordinary search.
  Future<void> _loadKeys() => _keys.load();

  Future<void> _noteFolder() async {
    if (widget.backend == 'comfyui' && await comfyStudioIsRemote()) {
      if (!mounted) return;
      setState(() {
        _error =
            'This ComfyUI is on another computer. Save the download on that computer.';
        _needFolder = false;
        _scanning = false;
      });
      return;
    }
    final root = await savedStudioModelRoot(widget.backend);
    if (!mounted) return;
    final gone = root == null && await studioSavedRootMissing(widget.backend);
    final blocked = civitaiBlockedDownload(
      backend: widget.backend,
      savedRoot: root,
      savedGone: gone,
    );
    final haveRoot = root != null && root.trim().isNotEmpty;
    final kinds = haveRoot
        ? await studioModelTypeFolders(widget.backend, root)
        : const <String, String>{};
    if (haveRoot) await _sweepParts(root, kinds);
    final models = haveRoot
        ? await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: false,
            typeFolders: kinds,
          )
        : const <String>[];
    final local = haveRoot
        ? await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: widget.lora,
            typeFolders: kinds,
          )
        : const <String>[];
    if (!mounted) return;
    setState(() {
      _modelFiles = models;
      _localNames = local;
      _scanning = false;
      _dropHiddenBase();
      if (blocked != null) {
        _error = blocked;
        _needFolder = widget.backend == 'comfyui' || widget.backend == 'a1111';
      }
    });
  }

  /// Partial downloads from an earlier run that the app quit in the middle of.
  Future<void> _sweepParts(String root, Map<String, String> kinds) async {
    try {
      await sweepCivitaiParts(root, typeFolders: kinds);
    } catch (e) {
      debugPrint('civitai part sweep failed: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    unawaited(_keys.keepTypedOnClose());
    _query.dispose();
    _baseText.dispose();
    _baseFocus.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// Stops a running download, then leaves the sheet.
  void _close() {
    _cancel?.cancel();
    Navigator.of(context).pop();
  }

  bool _current(int seq) => mounted && seq == _searchSeq;

  void _set(VoidCallback change) => setState(change);

  Future<void> _pickFolder() async {
    final picked = await PickerPrefs.getDirectoryPath(
      category: 'studio-models',
      dialogTitle: 'Models folder',
    );
    if (picked == null) return;
    await rememberStudioModelRoot(widget.backend, picked);
    if (mounted) {
      setState(() {
        _error = null;
        _needFolder = false;
      });
    }
  }

  /// "Use this folder": the person says the folder ComfyUI's config named is
  /// theirs, so downloads may go there.
  Future<void> _useOfferedFolder() async {
    final folder = _offerFolder;
    if (folder == null) return;
    final ok = await addTrustedModelFolder(folder);
    if (!mounted) return;
    setState(() {
      _offerFolder = null;
      _error = ok
          ? 'That folder is saved as a models folder. Press Download again.'
          : 'That folder cannot be used as a models folder.';
    });
  }

  void _openDetail(CivitaiModelRow row) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (pageContext) => StudioCivitaiDetail(
          row: row,
          adult: _adultNow,
          installed: civitaiFileInstalled(row.filename, _localNames),
          onDownload: () {
            Navigator.of(pageContext).pop();
            _install(row);
          },
        ),
      ),
    );
  }

  Future<void> _install(CivitaiModelRow row) async {
    if (_downloading) return;
    final cancel = CivitaiCancel();
    _cancel = cancel;
    setState(() {
      _searchSeq++;
      _searching = false;
      _error = null;
      _offerFolder = null;
      _progressName = row.filename ?? row.name;
      _got = 0;
      _total = null;
    });
    final result = await installCivitaiRow(
      row: row,
      backend: widget.backend,
      lora: widget.lora,
      adult: _adultNow,
      adultAllowed: widget.adultAllowed,
      versionFetch: widget.versionFetch,
      saveCall: widget.saveCall,
      cancel: cancel,
      onProgress: _paintProgress,
    );
    if (identical(_cancel, cancel)) _cancel = null;
    if (!mounted) return;
    switch (result) {
      case CivitaiInstalled(:final name):
        widget.onInstalled(name);
        Navigator.of(context).pop();
        return;
      case CivitaiInstallFailed(
        :final message,
        :final needFolder,
        :final offerFolder,
      ):
        setState(() {
          _error = message;
          _needFolder = needFolder;
          _offerFolder = offerFolder;
          _progressName = null;
        });
      case CivitaiInstallStopped():
        setState(() => _progressName = null);
    }
  }

  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _paintEvery = Duration(milliseconds: 200);

  void _paintProgress(int got, int? total) {
    if (!mounted) return;
    final done = total != null && got >= total;
    final now = DateTime.now();
    if (!done && now.difference(_lastPaint) < _paintEvery) return;
    _lastPaint = now;
    setState(() {
      _got = got;
      _total = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.lora
        ? 'Get a LoRA from CivitAI'
        : 'Get a model from CivitAI';
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimary(context),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        title: Text(title),
        bottom: studioCivitaiStatus(
          progressName: _progressName,
          error: _error,
          got: _got,
          total: _total,
          onCancel: () => _cancel?.cancel(),
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('Close')),
          TextButton(
            onPressed: _downloading ? null : _search,
            child: const Text('Search'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (_searching) const LinearProgressIndicator(),
          if (widget.adultAllowed)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _adult,
              title: const Text('Include adult models from civitai.red'),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _adult = value);
                widget.onAdultChanged?.call(value);
              },
            ),
          CivitaiKeyPanel(
            controller: _keys,
            onMessage: (message) {
              if (mounted) setState(() => _error = message);
            },
          ),
          StudioCivitaiBasePicker(
            base: _base,
            query: _baseQuery,
            text: _baseText,
            focus: _baseFocus,
            installedOnly: _installedOnly,
            modelFiles: _modelFiles,
            scanning: _scanning,
            note: _baseNote,
            onBase: _pickBase,
            onInstalledOnly: _setInstalledOnly,
          ),
          TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: widget.lora ? 'Search LoRAs' : 'Search CivitAI',
              hintText: widget.lora ? 'Clothes' : null,
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_offerFolder != null) ...[
            Text(
              _offerFolder!,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            TextButton(
              onPressed: _downloading ? null : _useOfferedFolder,
              child: const Text('Use this folder'),
            ),
          ],
          if (_needFolder)
            TextButton(
              onPressed: _downloading ? null : _pickFolder,
              child: Text(
                widget.backend == 'a1111'
                    ? 'Pick the Automatic1111 folder'
                    : 'Pick the ComfyUI models folder',
              ),
            ),
          for (final row in _rows)
            StudioCivitaiCard(
              row: row,
              busy: _downloading,
              installed: civitaiFileInstalled(row.filename, _localNames),
              onOpen: () => _openDetail(row),
              onDownload: () => _install(row),
            ),
          if (_cursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _searching || _downloading ? null : _loadMore,
                child: const Text('Load more'),
              ),
            ),
        ],
      ),
    );
  }
}
