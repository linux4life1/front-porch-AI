// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'studio_civitai_base.dart';
import 'studio_civitai_card.dart';
import 'studio_civitai_detail.dart';
import 'studio_civitai_install.dart';
import 'studio_civitai_key.dart';

/// One CivitAI search answer: the HTTP status and body.
typedef CivitaiSearchCall =
    Future<({int status, String body})> Function(
      Uri uri,
      Map<String, String> headers,
    );

Future<({int status, String body})> _httpSearch(
  Uri uri,
  Map<String, String> headers,
) async {
  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 20));
  return (status: response.statusCode, body: response.body);
}

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
    this.searchCall = _httpSearch,
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
  String _baseQuery = '';
  bool _installedOnly = false;
  List<String> _modelFiles = const [];
  List<String> _localNames = const [];
  bool _scanning = true;
  List<CivitaiModelRow> _rows = const [];
  String? _error;
  bool _searching = false;
  bool _needFolder = false;
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
    unawaited(_loadKeys());
    unawaited(_noteFolder());
  }

  Future<void> _loadKeys() async {
    final error = await _keys.load();
    if (error != null && mounted) setState(() => _error = error);
  }

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
    final blocked = civitaiBlockedDownload(
      backend: widget.backend,
      savedRoot: root,
    );
    final haveRoot = root != null && root.trim().isNotEmpty;
    if (haveRoot) await _sweepParts(root);
    final models = haveRoot
        ? await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: false,
          )
        : const <String>[];
    final local = haveRoot
        ? await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: widget.lora,
          )
        : const <String>[];
    if (!mounted) return;
    setState(() {
      _modelFiles = models;
      _localNames = local;
      _scanning = false;
      if (blocked != null) {
        _error = blocked;
        _needFolder = widget.backend == 'comfyui' || widget.backend == 'a1111';
      }
    });
  }

  /// Partial downloads from an earlier run that the app quit in the middle of.
  Future<void> _sweepParts(String root) async {
    try {
      await sweepCivitaiParts(root);
    } catch (e) {
      debugPrint('civitai part sweep failed: ${e.runtimeType}');
    }
  }

  String _selectedBase() {
    final groups = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      query: _baseQuery,
      onlyApis: _installedOnly ? civitaiBasesForFiles(_modelFiles) : null,
    );
    for (final group in groups) {
      for (final choice in group.choices) {
        if (choice.api == _base) return _base;
      }
    }
    return '';
  }

  @override
  void dispose() {
    _cancel?.cancel();
    unawaited(_keys.keepTypedOnClose());
    _query.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// Stops a running download, then leaves the sheet.
  void _close() {
    _cancel?.cancel();
    Navigator.of(context).pop();
  }

  bool _current(int seq) => mounted && seq == _searchSeq;

  /// A newer search replaces an older one, so the list on screen is always
  /// the answer to the last thing asked.
  Future<void> _search() async {
    if (_downloading) return;
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _error = null;
      _needFolder = false;
    });
    try {
      final saveError = await _keys.saveTyped();
      if (!_current(seq)) return;
      if (saveError != null) {
        setState(() => _error = saveError);
        return;
      }
      final relay = CivitaiRelay(await CivitaiCredentialStore.open());
      final plan = await relay.planSearch(
        accountId: 'local',
        query: _query.text.trim(),
        adult: _adultNow,
        lora: widget.lora,
        baseModel: _selectedBase(),
      );
      if (!_current(seq)) return;
      if (plan.needsCredential || plan.uri == null) {
        setState(() {
          _rows = const [];
          _error = civitaiSearchNote(
            kind: CivitaiHttpKind.needsCredential,
            hadKey: _keys.saved,
            rows: 0,
          );
        });
        return;
      }
      final response = await widget.searchCall(plan.uri!, {
        if (plan.authorization != null) 'Authorization': plan.authorization!,
      });
      if (!_current(seq)) return;
      final kind = civitaiHttpKind(response.status);
      final rows = kind == CivitaiHttpKind.ok
          ? parseCivitaiModels(response.body, includeAdult: _adultNow)
          : const <CivitaiModelRow>[];
      final note = civitaiSearchNote(
        kind: kind,
        hadKey: _keys.saved || plan.authorization != null,
        rows: rows.length,
      );
      setState(() {
        _rows = rows;
        _error = note.isEmpty ? null : note;
      });
    } on CivitaiKeyStoreException catch (e) {
      if (_current(seq)) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      if (_current(seq)) setState(() => _error = 'CivitAI search failed.');
    } finally {
      if (_current(seq)) setState(() => _searching = false);
    }
  }

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
      case CivitaiInstallFailed(:final message, :final needFolder):
        setState(() {
          _error = message;
          _needFolder = needFolder;
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
            installedOnly: _installedOnly,
            modelFiles: _modelFiles,
            scanning: _scanning,
            onBase: (value) => setState(() => _base = value),
            onQuery: (value) => setState(() => _baseQuery = value),
            onInstalledOnly: (value) => setState(() => _installedOnly = value),
          ),
          TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: widget.lora ? 'Search LoRAs' : 'Search CivitAI',
              hintText: widget.lora ? 'Clothes' : null,
            ),
            onSubmitted: (_) => _search(),
          ),
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
        ],
      ),
    );
  }
}
