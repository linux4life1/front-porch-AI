// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk_copy.dart';

import 'studio_desk_host.dart';

/// The files, samplers and LoRA facts the connected backend lists.
/// Reading never writes a setting.
class StudioDeskCatalog {
  StudioDeskCatalog(
    this._host, {
    required this.onLoraFacts,
    required this.listA1111Models,
    required this.listDrawThingsModels,
  });

  final StudioDeskHost _host;

  /// How a local backend's model files are listed.
  final Future<List<String>> Function(ImageGenService gen, String url)
  listA1111Models;
  final Future<List<String>> Function(ImageGenService gen, String url)
  listDrawThingsModels;

  /// Called after new LoRA facts are remembered, so Ready is judged again.
  final VoidCallback onLoraFacts;

  List<String> _models = const [];
  List<ImageModelInfo> _remoteModels = const [];
  List<String> _checkpoints = const [];
  List<String> _unet = const [];
  List<String> _gguf = const [];
  List<String> _loras = const [];
  List<String> _clips = const [];
  List<String> _vaes = const [];
  List<String> _samplers = const [];
  List<String> _schedulers = const [];
  Map<String, DeskLoraCheck> _loraFacts = {};
  Map<String, String> _dtLoraVersions = const {};
  Map<String, String> _dtModelVersions = const {};
  String? _catalogUrl;
  String? _catalogPending;
  bool _remoteListed = false;

  List<String> get models => _models;

  /// The Remote host's image models with their sizes and prices.
  List<ImageModelInfo> get remoteModels => _remoteModels;
  List<String> get checkpoints => _checkpoints;
  List<String> get unet => _unet;
  List<String> get gguf => _gguf;
  List<String> get loras => _loras;
  List<String> get clips => _clips;
  List<String> get vaes => _vaes;
  List<String> get samplers => _samplers;
  List<String> get schedulers => _schedulers;
  Map<String, DeskLoraCheck> get loraFacts => _loraFacts;
  Map<String, String> get dtLoraVersions => _dtLoraVersions;
  Map<String, String> get dtModelVersions => _dtModelVersions;
  String? get catalogUrl => _catalogUrl;

  bool reachable(String backend, StudioReadyReport? report) {
    if (backend == 'comfyui') return report?.objectInfo != null;
    if (backend == 'drawthings') return _drawThingsListed;
    if (backend == 'remote') return _remoteListed;
    return (_catalogUrl ?? '').startsWith('up:');
  }

  /// Draw Things shows its file counts after a listing, or after Check
  /// says the server is up. A failed Check stays down.
  bool get _drawThingsListed {
    final mark = _catalogUrl ?? '';
    if (mark.isEmpty || mark.startsWith('down:')) return false;
    if (mark.startsWith('up:')) return true;
    return _models.isNotEmpty || _loras.isNotEmpty;
  }

  /// Forgets which address was listed, so the next refresh lists again.
  void forgetListing() => _host.rebuildState(() => _catalogUrl = null);

  /// The LoRAs on the stove with the family facts known so far: a name guess
  /// until Comfy's metadata (or Draw Things' catalog) has been read.
  List<DeskLoraCheck> loraChecks(ImageGenSettings settings) {
    final stored = storedLoraFacts(settings);
    return [
      for (final slot in settings.imageGenLoraSlots)
        if (slot.file.trim().isNotEmpty)
          stored[slot.file] ??
              _loraFacts[slot.file] ??
              DeskLoraCheck(
                slot.file,
                ImageModelFamily.detectFromName(slot.file),
              ),
    ];
  }

  ImageGenService? _service() {
    try {
      return _host.context.read<ImageGenService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _applyCatalog({
    List<String> models = const [],
    List<ImageModelInfo> remoteModels = const [],
    List<String> checkpoints = const [],
    List<String> unet = const [],
    List<String> gguf = const [],
    List<String> loras = const [],
    List<String> clips = const [],
    List<String> vaes = const [],
    List<String> samplers = const [],
    List<String> schedulers = const [],
    bool remoteListed = false,
    String? url,
  }) {
    _host.rebuildState(() {
      _models = models;
      _remoteModels = remoteModels;
      _checkpoints = checkpoints;
      _unet = unet;
      _gguf = gguf;
      _loras = loras;
      _clips = clips;
      _vaes = vaes;
      _samplers = samplers;
      _schedulers = schedulers;
      _remoteListed = remoteListed;
      _catalogUrl = url;
    });
  }

  void _rememberLoraFacts(
    Map<String, DeskLoraCheck> facts, {
    Map<String, String> dtLoraVersions = const {},
    Map<String, String> dtModelVersions = const {},
  }) {
    _host.rebuildState(() {
      _loraFacts = facts;
      _dtLoraVersions = dtLoraVersions;
      _dtModelVersions = dtModelVersions;
    });
    onLoraFacts();
  }

  void showInstalledFiles({
    required List<String> checkpoints,
    required List<String> unet,
    required List<String> gguf,
    required List<String> loras,
  }) {
    _host.rebuildState(() {
      _checkpoints = checkpoints;
      _unet = unet;
      _gguf = gguf;
      _loras = loras;
    });
  }

  /// Lists what the connected backend has. Reading never writes a setting.
  /// A [soft] read (a Change sheet opening or refreshing) lists again but
  /// never takes files away: one that fails, or comes back empty, leaves what
  /// was listed, where Check says the backend is not answering.
  Future<void> refresh(
    ImageGenSettings settings, {
    bool force = false,
    bool soft = false,
  }) async {
    final backend = settings.imageGenBackend;
    if (backend == 'a1111' || backend == 'drawthings') {
      await _refreshLocal(settings, force: force || soft, soft: soft);
    } else if (backend == 'comfyui') {
      await _refreshComfy(settings, force: force || soft);
    } else if (backend == 'remote') {
      await _refreshRemote(settings, force: force || soft, soft: soft);
    }
  }

  Future<void> _refreshLocal(
    ImageGenSettings settings, {
    required bool force,
    bool soft = false,
  }) async {
    final drawThings = settings.imageGenBackend == 'drawthings';
    final url = drawThings
        ? '${settings.drawThingsGrpcHost}:${settings.drawThingsGrpcPort}'
        : settings.localImageGenUrl;
    if (!force && _catalogUrl == url) return;
    final gen = _service();
    if (gen == null) return;
    final up = force ? await gen.testLocalConnection(url) : true;
    if (soft && !up) return;
    final models = !up
        ? const <String>[]
        : drawThings
        ? await listDrawThingsModels(gen, url)
        : await listA1111Models(gen, url);
    var listing = const DrawThingsLoraListing();
    var modelVersions = const <String, String>{};
    if (up && drawThings) {
      listing = drawThingsLoraListing(await gen.fetchDrawThingsLoras(url));
      modelVersions = await gen.fetchDrawThingsModelVersions(url);
    }
    final samplers = up && !drawThings
        ? await gen.fetchA1111Samplers(url)
        : const <String>[];
    final schedulers = up && !drawThings
        ? await gen.fetchA1111Schedulers(url)
        : const <String>[];
    // Automatic1111's own LoRA list, so the slots can be filled from it.
    // A server lists the LoRAs it found at start, so a re-check (and a finished
    // download) asks it to look at the folder again before listing.
    if (force && up && !drawThings) await refreshA1111LorasAt(url);
    final a1111Loras = up && !drawThings
        ? [for (final l in await gen.fetchA1111Loras(url)) l.name]
        : const <String>[];
    if (!_host.mounted) return;
    final loras = drawThings ? listing.names : a1111Loras;
    _applyCatalog(
      models: soft && models.isEmpty ? _models : models,
      loras: soft && loras.isEmpty ? _loras : loras,
      samplers: soft && samplers.isEmpty ? _samplers : samplers,
      schedulers: soft && schedulers.isEmpty ? _schedulers : schedulers,
      url: force ? (up ? 'up:$url' : 'down:$url') : url,
    );
    if (drawThings && !(soft && loras.isEmpty)) {
      _rememberLoraFacts(
        listing.facts,
        dtLoraVersions: listing.versions,
        dtModelVersions: modelVersions,
      );
    }
  }

  Future<void> _refreshComfy(
    ImageGenSettings settings, {
    required bool force,
  }) async {
    final url = settings.comfyUiUrl;
    if (!force && (_catalogUrl == url || _catalogPending == url)) return;
    // Marked as listed only once it has been: a ComfyUI that was down is
    // asked again on the next look, not only after Check.
    _catalogPending = url;
    final service = ComfyUiService(baseUrl: url);
    final catalog = await service.fetchCatalogIfUp();
    if (_catalogPending == url) _catalogPending = null;
    if (catalog == null) {
      if (_host.mounted && _catalogUrl == url) {
        _host.rebuildState(() => _catalogUrl = null);
      }
      return;
    }
    final samplers = await service.fetchSamplers();
    final schedulers = await service.fetchSchedulers();
    if (!_host.mounted) return;
    _applyCatalog(
      models: catalog.deskDiscovery,
      checkpoints: catalog.checkpoints,
      unet: catalog.diffusionModels,
      gguf: catalog.ggufUnets,
      loras: catalog.loras,
      clips: catalog.textEncoders,
      vaes: catalog.vaes,
      samplers: samplers,
      schedulers: schedulers,
      url: url,
    );
    await _readLoraFacts(settings, service);
  }

  /// The Remote API's image models, for the host chosen on the stove.
  Future<void> _refreshRemote(
    ImageGenSettings settings, {
    required bool force,
    bool soft = false,
  }) async {
    final url = settings.imageRemoteApiUrl;
    if (!force && _catalogUrl == url) return;
    _catalogUrl = url;
    final gen = _service();
    if (gen == null) return;
    final listed = await gen.fetchImageModels();
    if (!_host.mounted) return;
    if (soft && _remoteListed && isBundledImageCatalog(listed)) return;
    _applyCatalog(
      models: [for (final model in listed) model.id],
      remoteModels: listed,
      remoteListed: listed.isNotEmpty && !isBundledImageCatalog(listed),
      url: url,
    );
  }

  Future<void> _readLoraFacts(
    ImageGenSettings settings,
    ComfyUiService service,
  ) async {
    final checks = await deskLoraChecks(settings: settings, comfy: service);
    if (!_host.mounted) return;
    final stored = storedLoraFacts(settings);
    final changed = checks.any((row) {
      final was = stored[row.file];
      return was == null ||
          was.family != row.family ||
          was.metadataBacked != row.metadataBacked;
    });
    if (changed) await saveLoraFacts(settings, checks);
    if (!_host.mounted) return;
    _rememberLoraFacts({for (final row in checks) row.file: row});
  }
}
