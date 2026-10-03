// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

extension on _StudioDeskState {
  /// The LoRAs on the stove with the family facts known so far: a name guess
  /// until Comfy's metadata (or Draw Things' catalog) has been read.
  List<DeskLoraCheck> _loraChecks(ImageGenSettings settings) {
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

  /// Judges Ready again when something it depends on changed. It never
  /// writes what the person picked; the only write is dropping a "use
  /// anyway" that no longer matches the model.
  Future<void> _checkReady({bool force = false}) async {
    final settings = context.read<StorageService>().imageGenSettings;
    final key = _keyFor(settings);
    if (!force && key == _readyKey) return;
    _readyKey = key;
    final seq = ++_readySeq;
    final edit = _editing;
    final primary = studioPrimaryFor(settings, edit: edit);
    final family = ImageModelFamily.detectFromName(primary);
    final override =
        settings.prefs?.getString(
          settings.k('image_studio_lora_override_family'),
        ) ??
        '';
    final report = await checkStudioReady(
      settings: settings,
      edit: edit,
      loras: _loraChecks(settings),
      allowLoraMismatch: override.isNotEmpty && override == family.name,
    );
    if (!mounted || seq != _readySeq) return;
    rebuildState(() => _ready = report);
    _reportReady(report.ready);
    _watchComfy(report);
    // "Use anyway" belongs to the model it was pressed for. It is dropped when
    // this desk's own model changes to another family, not merely because the
    // other tab's desk (a different model) also reads the same setting.
    final changedFamily = _checkedFamily != null && _checkedFamily != family;
    _checkedFamily = family;
    if (!_configurationLocked &&
        override.isNotEmpty &&
        override != family.name &&
        changedFamily) {
      await settings.prefs?.remove(
        settings.k('image_studio_lora_override_family'),
      );
      settings.notify();
    }
    if (_fillWhenReady) {
      _fillWhenReady = false;
      await _fillSupport(settings, report.readiness.slots);
    }
  }

  void _reportReady(bool ready) {
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    widget.onReadyChanged?.call(ready);
  }
}
