// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation options (tab content extracted for studio). AppColors only.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/ui/image_studio/backend_catalog.dart';
import 'package:front_porch_ai/ui/image_studio/connection_status_card.dart';
import 'package:front_porch_ai/ui/image_studio/lora_picker.dart';
import 'package:front_porch_ai/ui/image_studio/model_slot_dropdown.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

part 'generation_options_tab.source.dart';
part 'generation_options_tab.local_panel.dart';
part 'generation_options_tab.shared_fields.dart';
part 'generation_options_tab.advanced.dart';

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
    _negativePromptController.text = s.imageGenSettings.imageGenNegativePrompt;
    _localUrlController.text = s.imageGenSettings.localImageGenUrl;
    _seedController.text = s.imageGenSettings.imageGenSeed.toString();
    _dtHostController.text = s.imageGenSettings.drawThingsGrpcHost;
    _dtPortController.text = s.imageGenSettings.drawThingsGrpcPort.toString();
    _comfyUrlController.text = s.imageGenSettings.comfyUiUrl;
    _fetchModels();
    // Auto-test local backends on open — the status card shows the result and
    // a successful test populates models/samplers/LoRAs, so novices never
    // have to find a Test button. (Post-frame: _testConnection uses Provider.)
    if (s.imageGenSettings.imageGenBackend != 'remote') {
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
    final isComfy = st.imageGenSettings.imageGenBackend == 'comfyui';
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
    final backend = st.imageGenSettings.imageGenBackend;
    final isDT = backend == 'drawthings';
    final isComfy = backend == 'comfyui';
    if (!isDT && !isComfy && url.isEmpty) return;
    if (isDT && st.imageGenSettings.drawThingsGrpcHost.isEmpty) return;
    if (isComfy && st.imageGenSettings.comfyUiUrl.isEmpty) return;
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
    Provider.of<StorageService>(
      context,
      listen: false,
    ).imageGenSettings.setImageGenSeed(sd);
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
    final m = st.imageGenSettings.imageGenModel;
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

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`generation_options_tab.*.dart`), which hold the backend/local/shared/
  /// advanced builders but can't call a State's protected members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

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
                value: storage.imageGenSettings.imageGenEnabled,
                activeTrackColor: AppColors.formMasterAccent,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) =>
                    storage.imageGenSettings.setImageGenEnabled(v),
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
            if (storage.imageGenSettings.imageGenBackend == 'remote')
              _buildRemotePanel(storage)
            else
              _buildLocalPanel(storage),
          ],
        );
      },
    );
  }
}
