// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_prompts.dart';
import 'kcpps_editor_style.dart';
import 'kcpps_fit_panel.dart';
import 'kcpps_model_field.dart';
import 'kcpps_preset_list.dart';
import 'kcpps_sections.dart';
import 'kcpps_sections_more.dart';

/// The preset editor. True when a preset was saved.
class KcppsEditorDialog extends StatefulWidget {
  const KcppsEditorDialog({super.key, this.controller});

  /// For tests; built from the app's services otherwise.
  final KcppsEditorController? controller;

  @override
  State<KcppsEditorDialog> createState() => _KcppsEditorDialogState();
}

class _KcppsEditorDialogState extends State<KcppsEditorDialog> {
  late final KcppsEditorController c;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    c =
        widget.controller ??
        KcppsEditorController(
          storage: context.read<StorageService>(),
          hardware: context.read<HardwareService>(),
          kobold: context.read<KoboldService>(),
          stories: Provider.of<StoryRepository?>(context, listen: false),
          reloadChat: context.read<LLMProvider>().reloadChatKobold,
          loadTrial: context.read<LLMProvider>().loadKoboldTrial,
          models: [
            for (final m in context.read<ModelManager>().models)
              if (m.path.toLowerCase().endsWith('.gguf')) m.path,
          ],
          enginePath: Provider.of<BackendManager?>(
            context,
            listen: false,
          )?.backendPath,
        );
    c.addListener(_follow);
    if (!c.ready) c.init();
    _follow();
  }

  void _follow() {
    if (!_nameFocus.hasFocus && _name.text != c.draft.name) {
      _name.text = c.draft.name;
    }
  }

  @override
  void dispose() {
    c.removeListener(_follow);
    if (widget.controller == null) c.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Leaves unsaved changes only when the user says so.
  Future<bool> _mayLeave() async =>
      !c.dirty || await askDiscardKcpps(context, c.draft.name);

  Future<void> _select(String path) async {
    if (await _mayLeave()) await c.select(path);
  }

  Future<void> _new() async {
    if (await _mayLeave()) await c.newFromSettings();
  }

  Future<void> _open() async {
    if (!await _mayLeave()) return;
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['kcpps'],
    );
    final file = result?.files.single.path;
    if (file != null) await c.openFile(file);
  }

  Future<void> _save({required bool use}) async {
    Future<KcppsSaveResult> run(bool overwrite) =>
        use ? c.saveAndUse(overwrite: overwrite) : c.save(overwrite: overwrite);
    var result = await run(false);
    if (result == KcppsSaveResult.nameTaken && mounted) {
      if (!await askReplaceKcpps(context, c.draft.name.trim())) return;
      result = await run(true);
    }
    if (result != KcppsSaveResult.saved || !mounted) return;
    _saved = true;
    if (use) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final path = c.path;
    if (path == null) return;
    final ok = await askDeleteKcpps(
      context,
      c.draft.name,
      inUse: c.isChatPreset(path),
    );
    if (!ok) return;
    await c.delete();
    _saved = true;
  }

  Future<void> _close() async {
    if (await _mayLeave() && mounted) Navigator.of(context).pop(_saved);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.hairlineOf(context, 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 1380),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KcppsPresetList(
                      c: c,
                      onSelect: _select,
                      onNew: _new,
                      onOpen: _open,
                    ),
                    Expanded(child: _form(context)),
                  ],
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: AppColors.hairlineOf(context, 0.08)),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'KoboldCpp presets',
                  style: keText(context, size: 22, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A preset is how KoboldCpp loads a model. The app uses it '
                'whenever that model starts.',
                style: keText(
                  context,
                  size: 14,
                  color: AppColors.slateMutedOf(context),
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Close',
          child: SizedBox(
            width: 44,
            child: KeButton(
              'Close',
              icon: Icons.close,
              fontSize: 20,
              padding: 0,
              expand: true,
              onPressed: _close,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _form(BuildContext context) {
    if (!c.ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameRow(context),
          const SizedBox(height: 18),
          KcppsModelField(c: c),
          const SizedBox(height: 18),
          KcppsFitPanel(c: c),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) {
              final sections = <Widget>[
                KcppsChatLengthSection(c: c),
                KcppsSpeedSection(c: c),
                KcppsSmartCacheSection(c: c),
                KcppsExtrasSection(c: c),
              ];
              if (box.maxWidth < 720) {
                return Column(
                  children: [
                    for (final s in sections) ...[
                      s,
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              }
              Widget pair(Widget a, Widget b) => IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 16),
                    Expanded(child: b),
                  ],
                ),
              );
              return Column(
                children: [
                  pair(sections[0], sections[1]),
                  const SizedBox(height: 16),
                  pair(sections[2], sections[3]),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          KcppsPlainWords(text: c.plainWords),
          if (c.problem case final problem?) ...[
            const SizedBox(height: 12),
            Text(
              problem,
              key: const ValueKey('kcpps-problem'),
              style: keText(
                context,
                size: 14,
                color: AppColors.alertRedOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nameRow(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KeLabel('Name'),
            const SizedBox(height: 6),
            Focus(
              focusNode: _nameFocus,
              child: KeBox(
                controller: _name,
                keyName: 'kcpps-name',
                height: 44,
                fontSize: 15,
                semanticLabel: 'Name',
                onChanged: (v) => c.edit((d) => d.copyWith(name: v)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      KeButton(
        'Duplicate',
        padding: 14,
        onPressed: c.path == null ? null : c.duplicate,
      ),
      const SizedBox(width: 8),
      KeButton(
        'Delete',
        padding: 14,
        onPressed: c.path == null ? null : _delete,
      ),
    ],
  );

  Widget _footer(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: AppColors.hairlineOf(context, 0.08)),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        KeButton('Cancel', padding: 18, onPressed: _close),
        const SizedBox(width: 10),
        KeButton(
          'Save',
          kind: KeButtonKind.amberOutline,
          padding: 18,
          onPressed: () => _save(use: false),
        ),
        const SizedBox(width: 10),
        KeButton(
          'Save and use now',
          kind: KeButtonKind.amber,
          padding: 20,
          onPressed: () => _save(use: true),
        ),
      ],
    ),
  );
}
