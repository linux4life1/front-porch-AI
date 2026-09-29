// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'studio_civitai_base.dart';
import 'studio_civitai_card.dart';
import 'studio_civitai_detail.dart';

/// CivitAI search. A hit is downloaded into the saved models folder.
/// The search title is not stored as the installed file name.
class StudioCivitaiGet extends StatefulWidget {
  const StudioCivitaiGet({
    super.key,
    required this.lora,
    required this.adult,
    required this.backend,
    required this.onInstalled,
    this.onAdultChanged,
    this.onSaveKey,
  });

  final bool lora;
  final bool adult;
  final String backend;
  final ValueChanged<String> onInstalled;
  final ValueChanged<bool>? onAdultChanged;
  final Future<String?> Function(String token)? onSaveKey;

  @override
  State<StudioCivitaiGet> createState() => _StudioCivitaiGetState();
}

class _StudioCivitaiGetState extends State<StudioCivitaiGet> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _token = TextEditingController();
  String _base = '';
  String _baseQuery = '';
  bool _installedOnly = false;
  List<String> _modelFiles = const [];
  List<String> _localNames = const [];
  bool _scanning = true;
  List<CivitaiModelRow> _rows = const [];
  String? _error;
  bool _busy = false;
  bool _needFolder = false;
  bool _greenEdited = false;
  bool _greenSaved = false;
  String? _progressName;
  int _got = 0;
  int? _total;
  late bool _adult = widget.adult;

  @override
  void initState() {
    super.initState();
    _loadKeys();
    _noteFolder();
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
    final models = root == null || root.trim().isEmpty
        ? const <String>[]
        : await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: false,
          );
    final local = root == null || root.trim().isEmpty
        ? const <String>[]
        : await civitaiSlotNames(
            root: root,
            backend: widget.backend,
            lora: widget.lora,
          );
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

  Future<void> _loadKeys() async {
    final store = await CivitaiCredentialStore.open();
    final green = await store.read('local');
    if (!mounted) return;
    setState(() {
      if (!_greenEdited) _greenSaved = green != null;
    });
  }

  @override
  void dispose() {
    final green = _token.text.trim();
    if (green.isNotEmpty) {
      CivitaiCredentialStore.open().then((store) async {
        await store.save('local', green);
      });
    }
    _query.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<String?> _saveKey() async {
    String? error;
    final green = _token.text.trim();
    try {
      final store = await CivitaiCredentialStore.open();
      if (green.isNotEmpty) {
        await store.save('local', green);
        _greenSaved = true;
        _greenEdited = false;
        _token.clear();
      } else if (_greenEdited) {
        await store.signOut('local');
        _greenSaved = false;
      }
    } catch (e) {
      debugPrint('civitai key save failed: ${e.runtimeType}');
      error = 'Could not save the CivitAI key.';
    }
    if (green.isNotEmpty) error ??= await widget.onSaveKey?.call(green);
    if (!mounted) return error;
    setState(() {
      if (error != null) _error = error;
    });
    return error;
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
      _needFolder = false;
    });
    try {
      final saveError = await _saveKey();
      if (saveError != null) return;
      final hadKey = _greenSaved;
      final relay = CivitaiRelay(await CivitaiCredentialStore.open());
      final plan = await relay.planSearch(
        accountId: 'local',
        query: _query.text.trim(),
        adult: _adult,
        lora: widget.lora,
        baseModel: _selectedBase(),
      );
      if (plan.needsCredential || plan.uri == null) {
        setState(() {
          _rows = const [];
          _error = civitaiSearchNote(
            kind: CivitaiHttpKind.needsCredential,
            hadKey: hadKey,
            rows: 0,
          );
        });
        return;
      }
      final response = await http
          .get(
            plan.uri!,
            headers: {
              if (plan.authorization != null)
                'Authorization': plan.authorization!,
            },
          )
          .timeout(const Duration(seconds: 20));
      final rows = civitaiHttpKind(response.statusCode) == CivitaiHttpKind.ok
          ? parseCivitaiModels(response.body, includeAdult: _adult)
          : const <CivitaiModelRow>[];
      final note = civitaiSearchNote(
        kind: civitaiHttpKind(response.statusCode),
        hadKey: hadKey || plan.authorization != null,
        rows: rows.length,
      );
      setState(() {
        _rows = rows;
        _error = note.isEmpty ? null : note;
      });
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'CivitAI search failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
          adult: _adult,
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
    final filename = row.filename;
    final versionId = row.versionId;
    if (filename == null || versionId == null) {
      setState(() => _error = 'That row has no file to download.');
      return;
    }
    if (civitaiFileInstalled(filename, _localNames)) {
      widget.onInstalled(filename);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progressName = filename;
      _got = 0;
      _total = null;
    });
    try {
      if (widget.backend == 'comfyui' && await comfyStudioIsRemote()) {
        setState(() {
          _error =
              'This ComfyUI is on another computer. Save the download on that computer.';
          _needFolder = false;
        });
        return;
      }
      final root = await savedStudioModelRoot(widget.backend);
      final blocked = civitaiBlockedDownload(
        backend: widget.backend,
        savedRoot: root,
      );
      if (blocked != null) {
        setState(() {
          _error = blocked;
          _needFolder =
              root == null &&
              (widget.backend == 'comfyui' || widget.backend == 'a1111');
        });
        return;
      }
      final relay = CivitaiRelay(await CivitaiCredentialStore.open());
      final plan = await relay.planDownload(
        accountId: 'local',
        versionId: versionId,
        adult: _adult,
        savedRoot: root,
        filename: filename,
        civitaiType: row.type,
        fromLoraSheet: widget.lora,
        backend: widget.backend,
      );
      if (plan.refused || plan.path == null) {
        setState(() {
          _error = plan.reason.isEmpty
              ? 'CivitAI download was refused.'
              : plan.reason;
        });
        return;
      }
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await downloadCivitaiPlan(
        plan,
        onProgress: (got, total) {
          final now = DateTime.now();
          final done = total != null && got >= total;
          if (!done &&
              now.difference(last) < const Duration(milliseconds: 200)) {
            return;
          }
          last = now;
          if (!mounted) return;
          setState(() {
            _got = got;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      widget.onInstalled(filename);
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('civitai download failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'CivitAI download failed.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressName = null;
        });
      }
    }
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
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Text(title),
        bottom: studioCivitaiStatus(
          progressName: _progressName,
          error: _error,
          got: _got,
          total: _total,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _busy ? null : _search,
            child: const Text('Search'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
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
          if (_greenSaved && !_greenEdited && _token.text.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('API key saved'),
              subtitle: const Text(
                'This key is used for search and for adult results on civitai.red.',
              ),
              trailing: TextButton(
                onPressed: () => setState(() => _greenEdited = true),
                child: const Text('Replace'),
              ),
            )
          else
            TextField(
              controller: _token,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'API key'),
              onChanged: (_) => setState(() => _greenEdited = true),
              onSubmitted: (_) => _saveKey(),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saveKey,
              child: const Text('Save key'),
            ),
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
              onPressed: _busy ? null : _pickFolder,
              child: Text(
                widget.backend == 'a1111'
                    ? 'Pick the Automatic1111 folder'
                    : 'Pick the ComfyUI models folder',
              ),
            ),
          for (final row in _rows)
            StudioCivitaiCard(
              row: row,
              busy: _busy,
              installed: civitaiFileInstalled(row.filename, _localNames),
              onOpen: () => _openDetail(row),
              onDownload: () => _install(row),
            ),
        ],
      ),
    );
  }
}
