// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
    this.localFiles = const [],
    this.onPickLocal,
    this.onAdultChanged,
    this.onSaveKey,
  });

  final bool lora;
  final bool adult;
  final String backend;
  final ValueChanged<String> onInstalled;
  final List<String> localFiles;
  final ValueChanged<String>? onPickLocal;
  final ValueChanged<bool>? onAdultChanged;
  final Future<String?> Function(String token)? onSaveKey;

  @override
  State<StudioCivitaiGet> createState() => _StudioCivitaiGetState();
}

class _StudioCivitaiGetState extends State<StudioCivitaiGet> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _token = TextEditingController();
  List<CivitaiModelRow> _rows = const [];
  String? _error;
  bool _busy = false;
  bool _needFolder = false;
  bool _onComputer = false;
  late bool _adult = widget.adult;

  @override
  void dispose() {
    _query.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final save = widget.onSaveKey;
    if (save == null) return;
    final error = await save(_token.text);
    if (!mounted) return;
    if (error != null) setState(() => _error = error);
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
      _needFolder = false;
    });
    try {
      final relay = CivitaiRelay(await CivitaiCredentialStore.open());
      final plan = await relay.planSearch(
        accountId: 'local',
        query: _query.text.trim(),
        adult: _adult,
        lora: widget.lora,
      );
      if (plan.needsCredential || plan.uri == null) {
        setState(() {
          _rows = const [];
          _error = 'Paste an API key to search adult models.';
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
      final kind = civitaiHttpKind(response.statusCode);
      if (kind == CivitaiHttpKind.needsCredential) {
        setState(() => _error = 'CivitAI needs your API key.');
        return;
      }
      if (kind == CivitaiHttpKind.locked) {
        setState(() => _error = 'CivitAI refused this search.');
        return;
      }
      if (kind != CivitaiHttpKind.ok) {
        setState(() => _error = 'CivitAI search failed.');
        return;
      }
      setState(() {
        _rows = parseCivitaiModels(response.body, includeAdult: widget.adult);
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StudioCivitaiDetail(
        row: row,
        adult: _adult,
        onDownload: () {
          Navigator.of(dialogContext).pop();
          _install(row);
        },
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
    setState(() => _busy = true);
    try {
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
        setState(() => _error = 'CivitAI download was refused.');
        return;
      }
      await downloadCivitaiPlan(plan);
      if (!mounted) return;
      widget.onInstalled(filename);
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('civitai download failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = 'CivitAI download failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        widget.lora ? 'Get a LoRA from CivitAI' : 'Get a model from CivitAI',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.lora)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _onComputer = true),
                    child: const Text('On this computer'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _onComputer = false),
                    child: const Text('CivitAI'),
                  ),
                ],
              ),
            if (_onComputer)
              SizedBox(
                height: 240,
                child: ListView(
                  children: [
                    for (final file in widget.localFiles)
                      ListTile(
                        title: Text(file),
                        onTap: () {
                          widget.onPickLocal?.call(file);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              )
            else ...[
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
              TextField(
                controller: _token,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  isDense: true,
                ),
                onSubmitted: (_) => _saveKey(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saveKey,
                  child: const Text('Save key'),
                ),
              ),
              TextField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Search CivitAI'),
                onSubmitted: (_) => _search(),
              ),
            ],
            if (!_onComputer && _error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ),
            if (!_onComputer && _needFolder)
              TextButton(
                onPressed: _busy ? null : _pickFolder,
                child: const Text('Pick models folder'),
              ),
            if (!_onComputer)
              SizedBox(
                height: 420,
                child: ListView(
                  children: [
                    for (final row in _rows)
                      StudioCivitaiCard(
                        row: row,
                        busy: _busy,
                        onOpen: () => _openDetail(row),
                        onDownload: () => _install(row),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _search,
          child: const Text('Search'),
        ),
      ],
    );
  }
}
