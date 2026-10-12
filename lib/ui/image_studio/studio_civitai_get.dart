// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:front_porch_ai/services/image/civitai_search_pages.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'studio_civitai_base.dart';
import 'studio_civitai_card.dart';
import 'studio_civitai_detail.dart';
import 'studio_civitai_get/studio_civitai_get.dart';
import 'studio_civitai_install.dart';
import 'studio_civitai_key.dart';

export 'package:front_porch_ai/services/image/civitai_search_pages.dart'
    show CivitaiSearchCall;

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
  late final CivitaiBaseField _base;
  List<String> _localNames = const [];
  final CivitaiSearchResults _results = CivitaiSearchResults();
  String? _error;
  bool _needFolder = false;
  String? _offerFolder;
  String? _progressName;
  int _got = 0;
  int? _total;
  CivitaiCancel? _cancel;
  late bool _adult = widget.adult;

  bool get _downloading => _progressName != null;
  bool get _adultNow => widget.adultAllowed && _adult;

  @override
  void initState() {
    super.initState();
    _base = CivitaiBaseField(update: setState, onCleared: _clearResults);
    _query.addListener(_wordsChanged);
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
        _base.scanning = false;
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
      _base.modelFiles = models;
      _localNames = local;
      _base.scanning = false;
      _base.dropHidden();
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
    _base.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// Stops a running download, then leaves the sheet.
  void _close() {
    _cancel?.cancel();
    Navigator.of(context).pop();
  }

  bool _current(int seq) => mounted && _results.isCurrent(seq);

  /// Call inside a state change.
  void _clearResults() {
    if (_results.clear()) _error = null;
  }

  void _wordsChanged() {
    if (_results.wordsChanged(_query.text.trim())) setState(_clearResults);
  }

  Future<void> _search() => _runSearch(more: false);

  Future<void> _loadMore() => _runSearch(more: true);

  Future<void> _runSearch({required bool more}) async {
    if (_downloading) return;
    final from = more ? _results.cursor : null;
    final asked = more
        ? _results.asked
        : (query: _query.text.trim(), base: _base.base, adult: _adultNow);
    if (more && (from == null || asked == null)) return;
    final seq = _results.begin();
    setState(() {
      _results.searching = true;
      _error = null;
      _needFolder = false;
      _offerFolder = null;
    });
    try {
      final saveError = await _keys.saveTyped();
      if (!_current(seq)) return;
      if (saveError != null) {
        setState(() => _error = saveError);
        return;
      }
      final page = await fetchCivitaiSearchPage(
        asked: asked!,
        lora: widget.lora,
        get: widget.searchCall,
        cursor: from,
        have: _results.rows,
        keys: _keys,
        current: () => _current(seq),
      );
      if (page == null) return;
      setState(() {
        _results.rows = page.rows;
        _results.cursor = page.cursor;
        if (!page.found) {
          _error = page.note;
          return;
        }
        _results.asked = asked;
        _error = page.note.isEmpty ? null : page.note;
        _results.errorFromSearch = page.note.isNotEmpty;
      });
    } on CivitaiKeyStoreException catch (e) {
      if (_current(seq)) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      if (_current(seq)) setState(() => _error = 'CivitAI search failed.');
    } finally {
      if (_current(seq)) setState(() => _results.searching = false);
    }
  }

  Future<void> _pickFolder() async {
    final picked = await GuardedPicker.getDirectoryPath(
      context,
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
      _results.drop();
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
          if (_results.searching) const LinearProgressIndicator(),
          if (widget.adultAllowed)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _adult,
              title: const Text('Include adult models from civitai.red'),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _adult = value;
                  _clearResults();
                });
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
            base: _base.base,
            query: _base.query,
            text: _base.text,
            focus: _base.focus,
            installedOnly: _base.installedOnly,
            modelFiles: _base.modelFiles,
            scanning: _base.scanning,
            note: _base.note,
            onBase: _base.pick,
            onInstalledOnly: _base.setInstalledOnly,
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
          for (final row in _results.rows)
            StudioCivitaiCard(
              row: row,
              busy: _downloading,
              installed: civitaiFileInstalled(row.filename, _localNames),
              onOpen: () => _openDetail(row),
              onDownload: () => _install(row),
            ),
          if (_results.cursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _results.searching || _downloading
                    ? null
                    : _loadMore,
                child: const Text('Load more'),
              ),
            ),
        ],
      ),
    );
  }
}
