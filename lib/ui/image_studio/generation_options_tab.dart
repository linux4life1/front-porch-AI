// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation options (tab content extracted for studio). AppColors only.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/ui/image_studio/backend_catalog.dart';
import 'package:front_porch_ai/ui/image_studio/connection_status_card.dart';
import 'package:front_porch_ai/ui/image_studio/lora_picker.dart';
import 'package:front_porch_ai/ui/image_studio/model_slot_dropdown.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

const List<({String label, int value})> _drawThingsSamplers = [
  (label: 'DDIM Trailing', value: 16),
  (label: 'UniPC Trailing', value: 17),
  (label: 'Euler a Trailing', value: 10),
  (label: 'DPM++ 2M Trailing', value: 15),
  (label: 'DPM++ SDE Trailing', value: 11),
  (label: 'UniPC AYS', value: 18),
  (label: 'Euler a AYS', value: 13),
  (label: 'DPM++ 2M AYS', value: 12),
  (label: 'DPM++ SDE AYS', value: 14),
  (label: 'DPM++ 2M Karras', value: 0),
  (label: 'DPM++ SDE Karras', value: 4),
  (label: 'Euler a', value: 1),
  (label: 'UniPC', value: 5),
  (label: 'DDIM', value: 2),
  (label: 'PLMS', value: 3),
  (label: 'LCM', value: 6),
  (label: 'TCD', value: 9),
  (label: 'Euler a Substep', value: 7),
  (label: 'DPM++ SDE Substep', value: 8),
];

class GenerationOptionsTab extends StatefulWidget {
  final bool showEnableToggle;

  /// When false, the Default Style + Prompt Format controls are hidden here —
  /// the Studio owns them via its canvas StylePreview, so showing them in the
  /// settings panel too would duplicate the control. The standalone image
  /// settings dialog (which has no StylePreview) keeps them.
  final bool showStyleControls;

  /// When true, the per-generation knobs (Steps / CFG / DT Sampler / Shift /
  /// SeedMode) read and write the EDIT-scoped store instead of the Create
  /// (txt2img) store, so the Image Studio Edit tab can tune an edit without
  /// clobbering Create. The MODEL picker is edit-scoped too on Draw Things and
  /// remote (the phase-#12 create/edit slot split — an edit model left selected
  /// after an Edit session used to poison base generation); ComfyUI's edit
  /// models live in comfyEdit* and A1111 can't edit, so their checkpoint
  /// pickers stay on the create slot. Everything else (backend, size, seed,
  /// LoRA) stays shared. Default false = the normal Create/settings behavior.
  final bool editScoped;
  const GenerationOptionsTab({
    super.key,
    this.showEnableToggle = true,
    this.showStyleControls = true,
    this.editScoped = false,
  });
  @override
  State<GenerationOptionsTab> createState() => _GenerationOptionsTabState();
}

class _GenerationOptionsTabState extends State<GenerationOptionsTab> {
  List<ImageModelInfo> _models = [];
  bool _loadingModels = false;
  final _negativePromptController = TextEditingController();
  final _localUrlController = TextEditingController();
  List<String> _localModels = [];
  bool _loadingLocalModels = false;
  bool? _connectionOk;
  bool _testingConnection = false;
  bool _unloadingModel = false;
  bool _switchingModel = false;
  List<String> _localSamplers = [];
  List<String> _localSchedulers = [];
  List<LoraOption> _localLoras = [];
  bool _loadingLoras = false;
  final _seedController = TextEditingController();
  final _dtHostController = TextEditingController();
  final _dtPortController = TextEditingController();
  final _comfyUrlController = TextEditingController();
  double? _dragSteps;
  double? _dragCfgScale;

  @override
  void initState() {
    super.initState();
    final s = Provider.of<StorageService>(context, listen: false);
    _negativePromptController.text = s.imageGenNegativePrompt;
    _localUrlController.text = s.localImageGenUrl;
    _seedController.text = s.imageGenSeed.toString();
    _dtHostController.text = s.drawThingsGrpcHost;
    _dtPortController.text = s.drawThingsGrpcPort.toString();
    _comfyUrlController.text = s.comfyUiUrl;
    _fetchModels();
    // Auto-test local backends on open — the status card shows the result and
    // a successful test populates models/samplers/LoRAs, so novices never
    // have to find a Test button. (Post-frame: _testConnection uses Provider.)
    if (s.imageGenBackend != 'remote') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _testConnection();
      });
    }
  }

  @override
  void dispose() {
    _negativePromptController.dispose();
    _localUrlController.dispose();
    _seedController.dispose();
    _dtHostController.dispose();
    _dtPortController.dispose();
    _comfyUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    final svc = Provider.of<ImageGenService>(context, listen: false);
    final m = await svc.fetchImageModels();
    if (mounted) {
      setState(() {
        _models = m;
        _loadingModels = false;
      });
    }
  }

  Future<void> _fetchLocalModels() async {
    final st = Provider.of<StorageService>(context, listen: false);
    if (backendProbeUrl(st).isEmpty) return;
    setState(() => _loadingLocalModels = true);
    final svc = Provider.of<ImageGenService>(context, listen: false);
    // Shared per-backend dispatch (also the creators' engine strip).
    final options = await fetchBackendModelOptions(svc, st);
    if (mounted) {
      setState(() {
        _localModels = [for (final o in options) o.value];
        _loadingLocalModels = false;
      });
    }
  }

  Future<void> _fetchLocalSamplers(String url) async {
    final st = Provider.of<StorageService>(context, listen: false);
    final isComfy = st.imageGenBackend == 'comfyui';
    if (!isComfy && url.isEmpty) return;
    final svc = Provider.of<ImageGenService>(context, listen: false);
    // Samplers and schedulers come from the same server (and, for ComfyUI, the
    // same /object_info payload), so fetch them together on connect.
    final ss = isComfy
        ? await svc.fetchComfySamplers(url)
        : await svc.fetchA1111Samplers(url);
    final sched = isComfy
        ? await svc.fetchComfySchedulers(url)
        : await svc.fetchA1111Schedulers(url);
    if (mounted) {
      setState(() {
        _localSamplers = ss;
        _localSchedulers = sched;
      });
    }
  }

  Future<void> _fetchLocalLoras(String url) async {
    // Mirrors the _fetchLocalModels guard: Draw Things lists LoRAs over gRPC
    // and ComfyUI via its own URL setting; A1111 needs the local server URL.
    final st = Provider.of<StorageService>(context, listen: false);
    final backend = st.imageGenBackend;
    final isDT = backend == 'drawthings';
    final isComfy = backend == 'comfyui';
    if (!isDT && !isComfy && url.isEmpty) return;
    if (isDT && st.drawThingsGrpcHost.isEmpty) return;
    if (isComfy && st.comfyUiUrl.isEmpty) return;
    setState(() => _loadingLoras = true);
    final svc = Provider.of<ImageGenService>(context, listen: false);
    final loras = isDT
        ? await svc.fetchDrawThingsLoras(url)
        : isComfy
        ? await svc.fetchComfyLoras(url)
        : await svc.fetchA1111Loras(url);
    if (mounted) {
      setState(() {
        _localLoras = loras;
        _loadingLoras = false;
      });
    }
  }

  void _randomizeSeed() {
    final sd = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    _seedController.text = sd.toString();
    Provider.of<StorageService>(context, listen: false).setImageGenSeed(sd);
  }

  Future<void> _testConnection() async {
    // The URL controllers write straight through to storage onChanged, so the
    // shared settings-derived probe URL always matches what the user typed.
    final st = Provider.of<StorageService>(context, listen: false);
    final u = backendProbeUrl(st);
    if (u.isEmpty) return;
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
    });
    final svc = Provider.of<ImageGenService>(context, listen: false);
    final ok = await svc.testLocalConnection(u);
    if (mounted) {
      setState(() {
        _connectionOk = ok;
        _testingConnection = false;
      });
      if (ok) {
        _fetchLocalModels();
        _fetchLocalSamplers(u);
        _fetchLocalLoras(u);
      }
    }
  }

  Future<void> _unloadModel() async {
    final u = _localUrlController.text.trim();
    if (u.isEmpty) return;
    setState(() => _unloadingModel = true);
    await Provider.of<ImageGenService>(
      context,
      listen: false,
    ).unloadLocalModel(u);
    if (mounted) {
      setState(() => _unloadingModel = false);
    }
  }

  Future<void> _switchModel() async {
    final u = _localUrlController.text.trim();
    final st = Provider.of<StorageService>(context, listen: false);
    final m = st.imageGenModel;
    if (u.isEmpty || m.isEmpty) return;
    setState(() => _switchingModel = true);
    await Provider.of<ImageGenService>(
      context,
      listen: false,
    ).switchLocalModel(u, m);
    if (mounted) {
      setState(() => _switchingModel = false);
    }
  }

  InputDecoration _deco({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textTertiary(context)),
    filled: true,
    fillColor: AppColors.surfaceContainerOf(context),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showEnableToggle) ...[
              SwitchListTile(
                title: Text(
                  'Enable Image Generation',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  'Add image button to toolbar',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                value: storage.imageGenEnabled,
                activeTrackColor: AppColors.presetColors[6],
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => storage.setImageGenEnabled(v),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Image Source',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _buildBackendSelector(storage),
            const SizedBox(height: 12),
            if (storage.imageGenBackend == 'remote')
              _buildRemotePanel(storage)
            else
              _buildLocalPanel(storage),
          ],
        );
      },
    );
  }

  Widget _buildBackendSelector(StorageService st) {
    final bs = ImageGenBackend.values;
    final ac = AppColors.formMasterAccent;
    return Row(
      children: bs.map((b) {
        final sel = st.imageGenBackend == b.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: b == bs.last ? 0 : 8),
            child: GestureDetector(
              onTap: () {
                st.setImageGenBackend(b.key);
                setState(() {
                  _connectionOk = null;
                  _localModels = [];
                  _localLoras = [];
                  _localSamplers = [];
                  _localSchedulers = [];
                });
                // Auto-test the newly selected local backend (the status card
                // reflects progress; success populates models/LoRAs/samplers).
                if (b != ImageGenBackend.remote) _testConnection();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.cardOf(context)
                      : AppColors.surfaceContainerOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? ac : AppColors.borderOf(context),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      b == ImageGenBackend.remote
                          ? Icons.cloud_outlined
                          : b == ImageGenBackend.drawThings
                          ? Icons.apple
                          : b == ImageGenBackend.comfyUi
                          ? Icons.account_tree_outlined
                          : Icons.computer_outlined,
                      size: 16,
                      color: sel ? ac : AppColors.iconSecondary(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: sel ? ac : AppColors.textTertiary(context),
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRemotePanel(StorageService st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Image Model',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ModelSlotDropdown(
                settings: st.imageGenSettings,
                editSlot: widget.editScoped,
                keyPrefix: 'remote-model',
                fontSize: 12,
                decoration: _deco(
                  hint: _loadingModels
                      ? 'Loading...'
                      : (_models.isEmpty ? 'No models' : 'Select'),
                ),
                options: [
                  for (final m in _models) (value: m.id, label: m.displayName),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: _loadingModels
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.formMasterAccent,
                      ),
                    )
                  : Icon(
                      Icons.refresh,
                      color: AppColors.iconSecondary(context),
                      size: 18,
                    ),
              onPressed: _loadingModels ? null : _fetchModels,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSharedFields(st),
      ],
    );
  }

  Widget _buildLocalPanel(StorageService st) {
    final isDT = st.imageGenBackend == 'drawthings';
    final isComfy = st.imageGenBackend == 'comfyui';
    final backend = ImageGenBackend.fromKey(st.imageGenBackend);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One glanceable status line + Retry, fed by the automatic connection
        // test (on open and on backend switch). Replaces the old per-backend
        // Test buttons and status icons.
        ConnectionStatusCard(
          backendLabel: backend.label,
          connected: _connectionOk,
          testing: _testingConnection,
          modelCount: _localModels.length,
          loraCount: _localLoras.length,
          notReachableHint: isDT
              ? 'Is Draw Things running with its gRPC server enabled? '
                    'Default port 7859.'
              : isComfy
              ? 'Is ComfyUI running? It listens on http://127.0.0.1:8188 '
                    'by default.'
              : 'Is Stable Diffusion WebUI running with the --api flag?',
          onRetry: _testConnection,
        ),
        const SizedBox(height: 8),
        if (isDT) ...[
          Text(
            'gRPC Host / Port',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dtHostController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  decoration: _deco(hint: '127.0.0.1'),
                  onChanged: (v) {
                    st.setDrawThingsGrpcHost(v.trim());
                    setState(() {
                      _connectionOk = null;
                      _localModels = [];
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _dtPortController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  keyboardType: TextInputType.number,
                  decoration: _deco(),
                  onChanged: (v) {
                    st.setDrawThingsGrpcPort(int.tryParse(v) ?? 7859);
                    setState(() {
                      _connectionOk = null;
                      _localModels = [];
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                widget.editScoped ? 'Edit Model' : 'Checkpoint Model',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!_loadingLocalModels)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: _fetchLocalModels,
                  tooltip: 'Refresh model list',
                ),
            ],
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else
            Builder(
              builder: (_) {
                // Offline fallback: show the persisted slot value so the
                // selection is visible before the server is connected.
                final slotValue = widget.editScoped
                    ? st.imageGenSettings.imageGenEditModel
                    : st.imageGenModel;
                final dtModels = _localModels.isNotEmpty
                    ? _localModels
                    : (slotValue.isNotEmpty ? [slotValue] : <String>[]);
                if (dtModels.isEmpty) {
                  return Text(
                    'Models appear here once the server is connected.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 10,
                    ),
                  );
                }
                return ModelSlotDropdown(
                  settings: st.imageGenSettings,
                  editSlot: widget.editScoped,
                  keyPrefix: 'dt-checkpoint',
                  decoration: _deco(hint: 'Select'),
                  options: [for (final m in dtModels) (value: m, label: m)],
                );
              },
            ),
          const SizedBox(height: 4),
          Text(
            'Selection is used automatically on the next generation.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
        ] else if (isComfy) ...[
          Text(
            'ComfyUI URL',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: _comfyUrlController,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: _deco(hint: 'http://127.0.0.1:8188'),
            onChanged: (v) {
              st.setComfyUiUrl(v.trim());
              setState(() {
                _connectionOk = null;
                _localModels = [];
              });
            },
            onSubmitted: (_) => _testConnection(),
          ),
          const SizedBox(height: 8),
          Text(
            'Checkpoint Model',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else if (_localModels.isEmpty)
            Text(
              'No models found yet — Retry above once ComfyUI is running.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 10,
              ),
            )
          else
            // Always the CREATE slot — ComfyUI's edit models live in the
            // comfyEdit* workflow slots, never here.
            ModelSlotDropdown(
              settings: st.imageGenSettings,
              editSlot: false,
              keyPrefix: 'comfy-checkpoint',
              decoration: _deco(hint: 'Select'),
              options: [for (final m in _localModels) (value: m, label: m)],
            ),
          const SizedBox(height: 4),
          Text(
            'The model is applied per generation — no separate load step.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
        ] else ...[
          Text(
            'Server URL',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: _localUrlController,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: _deco(hint: 'http://127.0.0.1:7860'),
            onChanged: (v) {
              st.setLocalImageGenUrl(v.trim());
              setState(() => _connectionOk = null);
            },
            onSubmitted: (_) => _testConnection(),
          ),
          const SizedBox(height: 8),
          Text(
            'Checkpoint Model',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_loadingLocalModels)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            )
          else if (_localModels.isEmpty)
            Text(
              'Models appear here once the server is connected.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 10,
              ),
            )
          else
            // Always the CREATE slot — stock A1111 can't instruction-edit,
            // so an edit slot has no meaning here (img2img fallback only).
            ModelSlotDropdown(
              settings: st.imageGenSettings,
              editSlot: false,
              keyPrefix: 'a1111-checkpoint',
              decoration: _deco(hint: 'Select'),
              options: [for (final m in _localModels) (value: m, label: m)],
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_unloadingModel || _switchingModel)
                      ? null
                      : _unloadModel,
                  child: const Text('Unload', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (_unloadingModel ||
                          _switchingModel ||
                          st.imageGenModel.isEmpty)
                      ? null
                      : _switchModel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardOf(context),
                    foregroundColor: AppColors.textPrimary(context),
                  ),
                  child: const Text('Switch', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
        // LoRA (name + weight slider). A1111 injects <lora:name:weight> into
        // the prompt; Draw Things applies it natively via the gRPC config.
        ...[
          Divider(color: AppColors.borderOf(context)),
          const SizedBox(height: 4),
          Text(
            'LoRA',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isDT
                ? 'Applied natively by Draw Things.'
                : 'Via <lora:name:weight> in prompt.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          if (_loadingLoras)
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.formMasterAccent,
              ),
            )
          else
            LoraPicker(
              loras: _localLoras,
              // Family-filter against the slot this surface generates with
              // (the Edit tab pairs LoRAs with the EDIT model on DT).
              checkpointFamily: ImageModelFamily.detectFromName(
                widget.editScoped && isDT
                    ? st.imageGenSettings.imageGenEditModel
                    : st.imageGenModel,
              ),
              selected: st.imageGenLora,
              weight: st.imageGenLoraWeight,
              onSelected: (val) => st.setImageGenLora(val),
              onWeightChanged: (v) => st.setImageGenLoraWeight(v),
            ),
        ],
        const SizedBox(height: 8),
        _buildSharedFields(st),
      ],
    );
  }

  Widget _buildSharedFields(StorageService st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(
            'Review AI prompts before generating',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
          ),
          subtitle: Text(
            '/image pauses so you can edit the crafted prompt first',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10,
            ),
          ),
          value: st.imageGenPromptReview,
          activeTrackColor: AppColors.formMasterAccent,
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (v) => st.setImageGenPromptReview(v),
        ),
        const SizedBox(height: 4),
        Text(
          'Image Size',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _buildSizeSelector(st),
        const SizedBox(height: 8),
        if (widget.showStyleControls) ...[
        Text(
          'Default Style',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue:
              ImageGenService.styleLabels.containsKey(st.imageGenStyle)
              ? st.imageGenStyle
              : 'photorealistic',
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(color: AppColors.textPrimary(context)),
          isExpanded: true,
          decoration: _deco(),
          items: ImageGenService.styleLabels.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) st.setImageGenStyle(v);
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Prompt Format',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: st.imageGenPromptParadigm,
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(color: AppColors.textPrimary(context)),
          isExpanded: true,
          decoration: _deco(),
          items: const [
            DropdownMenuItem(
              value: 'natural',
              child: Text('Natural Language (FLUX / SD3)'),
            ),
            DropdownMenuItem(
              value: 'tags',
              child: Text('Danbooru Tags (SD 1.5 / Anime)'),
            ),
          ],
          onChanged: (v) {
            if (v != null) st.setImageGenPromptParadigm(v);
          },
        ),
        ],
        const SizedBox(height: 6),
        Text(
          'Default Negative Prompt',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextField(
          controller: _negativePromptController,
          maxLines: 2,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          decoration: _deco(hint: 'e.g. blurry...'),
          onChanged: (v) => st.setImageGenNegativePrompt(v),
        ),
        const SizedBox(height: 8),
        Consumer<StorageService>(
          builder: (ctx, st2, c) {
            final local = st2.imageGenBackend != 'remote';
            return ExpansionTile(
              title: Text(
                'Advanced',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              children: local
                  ? _buildAdvancedFields(
                      st2,
                      isDrawThings: st2.imageGenBackend == 'drawthings',
                    )
                  : [
                      Text(
                        'Local backend required.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 10,
                        ),
                      ),
                    ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSizeSelector(StorageService st) {
    const sizes = ['512x512', '768x768', '1024x1024', '1536x1024', '1024x1536'];
    const labels = ['512²', '768²', '1024²', '1536×1024', '1024×1536'];
    final ac = AppColors.formMasterAccent;
    final kids = <Widget>[];
    for (var i = 0; i < sizes.length; i++) {
      final sel = st.imageGenSize == sizes[i];
      kids.add(
        GestureDetector(
          onTap: () => st.setImageGenSize(sizes[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.cardOf(context)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sel ? ac : AppColors.borderOf(context)),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: sel ? ac : AppColors.textSecondary(context),
                fontSize: 10,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }
    return Wrap(spacing: 6, children: kids);
  }

  List<Widget> _buildAdvancedFields(
    StorageService st, {
    required bool isDrawThings,
  }) {
    // On the Edit tab these knobs are edit-scoped so an edit never clobbers
    // Create's txt2img settings; everywhere else they are the shared knobs.
    final editScoped = widget.editScoped;
    final steps = editScoped ? st.editSteps : st.imageGenSteps;
    final cfg = editScoped ? st.editCfgScale : st.imageGenCfgScale;
    final dtSampler = editScoped ? st.editSampler : st.drawThingsSampler;
    final dtShift = editScoped ? st.editShift : st.drawThingsShift;
    final dtSeedMode = editScoped ? st.editSeedMode : st.drawThingsSeedMode;
    return [
      Row(
        children: [
          Text(
            'Steps',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 10,
            ),
          ),
          Expanded(
            child: Slider(
              value: _dragSteps ?? steps.toDouble(),
              min: 5,
              max: 50,
              divisions: 45,
              activeColor: AppColors.formMasterAccent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (v) => setState(() => _dragSteps = v),
              onChangeEnd: (v) {
                _dragSteps = null;
                editScoped
                    ? st.setEditSteps(v.round())
                    : st.setImageGenSteps(v.round());
              },
            ),
          ),
          SizedBox(
            width: 26,
            child: Text(
              (_dragSteps ?? steps.toDouble()).round().toString(),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Text(
            'CFG',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 10,
            ),
          ),
          Expanded(
            child: Slider(
              value: _dragCfgScale ?? cfg,
              min: 1,
              max: 20,
              divisions: 190,
              activeColor: AppColors.formMasterAccent,
              inactiveColor: AppColors.borderOf(context),
              onChanged: (v) => setState(() => _dragCfgScale = v),
              onChangeEnd: (v) {
                _dragCfgScale = null;
                editScoped ? st.setEditCfgScale(v) : st.setImageGenCfgScale(v);
              },
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              (_dragCfgScale ?? cfg).toStringAsFixed(1),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      // In EDIT mode the string sampler (ComfyUI/A1111) is hidden: the ComfyUI
      // edit preset bakes its own sampler, and picking one here only clobbered
      // the Create-tab sampler while doing nothing to the edit. The DrawThings
      // int sampler stays — it IS edit-scoped (setEditSampler below).
      if (isDrawThings || !editScoped)
        Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Sampler',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: isDrawThings
                ? DropdownButtonFormField<int>(
                    initialValue: dtSampler,
                    dropdownColor: AppColors.surfaceContainerOf(context),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 10,
                    ),
                    isExpanded: true,
                    decoration: _deco(hint: 'DT'),
                    items: _drawThingsSamplers
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.value,
                            child: Text(
                              s.label,
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      editScoped
                          ? st.setEditSampler(v)
                          : st.setDrawThingsSampler(v);
                    },
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _localSamplers.contains(st.imageGenSampler)
                        ? st.imageGenSampler
                        : (st.imageGenSampler.isNotEmpty ? null : 'Euler a'),
                    dropdownColor: AppColors.surfaceContainerOf(context),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 10,
                    ),
                    isExpanded: true,
                    decoration: _deco(hint: 'sampler'),
                    items: _localSamplers
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) st.setImageGenSampler(v);
                    },
                  ),
          ),
        ],
      ),
      // Scheduler (noise schedule) — a real quality lever on A1111 and ComfyUI.
      // Draw Things has no separate scheduler concept, so it's hidden there.
      // Hidden in EDIT mode too: the ComfyUI edit preset controls it, so a
      // choice here only clobbered the Create-tab scheduler (same as sampler).
      // 'Automatic' means the backend decides (A1111 default / sampler-derived
      // for ComfyUI); the fetched list is server-specific.
      if (!isDrawThings && !editScoped)
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'Scheduler',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue:
                    (st.imageGenScheduler == 'Automatic' ||
                        _localSchedulers.contains(st.imageGenScheduler))
                    ? st.imageGenScheduler
                    : 'Automatic',
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 10,
                ),
                isExpanded: true,
                decoration: _deco(hint: 'scheduler'),
                items: <String>['Automatic', ..._localSchedulers]
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) st.setImageGenScheduler(v);
                },
              ),
            ),
          ],
        ),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Seed',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seedController,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 10,
                    ),
                    keyboardType: TextInputType.number,
                    decoration: _deco(hint: '-1=random'),
                    onChanged: (v) {
                      st.setImageGenSeed(int.tryParse(v) ?? -1);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.casino_outlined,
                    size: 14,
                    color: AppColors.formMasterAccent,
                  ),
                  onPressed: _randomizeSeed,
                ),
              ],
            ),
          ),
        ],
      ),
      if (isDrawThings) ...[
        const SizedBox(height: 6),
        Text(
          'DT Advanced',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          children: [
            Text(
              'Shift',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
            ),
            Expanded(
              child: Slider(
                value: dtShift,
                min: 0,
                max: 10,
                divisions: 100,
                activeColor: AppColors.formMasterAccent,
                onChanged: (v) =>
                    editScoped ? st.setEditShift(v) : st.setDrawThingsShift(v),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                dtShift.toStringAsFixed(1),
                style: TextStyle(fontSize: 8),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              'SeedMode',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 9,
              ),
            ),
            DropdownButton<int>(
              value: dtSeedMode,
              style: TextStyle(fontSize: 9),
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Rand', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text('Const', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text('PerImg', style: TextStyle(fontSize: 8)),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text('Prompt', style: TextStyle(fontSize: 8)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                editScoped
                    ? st.setEditSeedMode(v)
                    : st.setDrawThingsSeedMode(v);
              },
            ),
            Checkbox(
              value: st.drawThingsTeaCache,
              onChanged: (v) => st.setDrawThingsTeaCache(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text('Tea', style: TextStyle(fontSize: 8)),
            Checkbox(
              value: st.drawThingsCfgZeroStar,
              onChanged: (v) => st.setDrawThingsCfgZeroStar(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text('Zero', style: TextStyle(fontSize: 8)),
          ],
        ),
      ],
    ];
  }
}
