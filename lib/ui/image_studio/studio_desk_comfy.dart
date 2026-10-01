// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

/// Finding ComfyUI while the desk is open: on open, on Check, and again and
/// again (2 s, doubling to 30 s) while it does not answer, so a ComfyUI
/// started after Front Porch, or on another port, is picked up by itself.
/// While it answers it is asked every [kComfyUpCheckEvery] whether it still
/// does, so one that was closed or restarted elsewhere is noticed too.
extension _DeskComfy on _StudioDeskState {
  ComfyUrlFinder _finder() {
    try {
      return context.read<ComfyUrlFinder?>() ?? ComfyUrlFinder();
    } on ProviderNotFoundException {
      return ComfyUrlFinder();
    }
  }

  /// Looks for ComfyUI ([redialComfy]). True when it answers at the saved
  /// address (or the desk is no longer on ComfyUI), so the looking stops.
  /// Asked again while a look is under way, it waits for that one.
  Future<bool> _lookForComfy() =>
      _looking ??= _lookOnce().whenComplete(() => _looking = null);

  Future<bool> _lookOnce() async {
    if (!mounted) return true;
    final settings = context.read<StorageService>().imageGenSettings;
    if (settings.imageGenBackend != 'comfyui') return true;
    final found = await redialComfy(settings, finder: _finder());
    if (!mounted) return true;
    if (found.offer != _comfyOffer) {
      rebuildState(() => _comfyOffer = found.offer);
    }
    _noteComfy(found.reachable, settings.comfyUiUrl);
    if (found.reachable) {
      _refreshCatalog(settings, force: true);
      _checkReady(force: true);
    }
    return found.reachable;
  }

  /// Logged once each time ComfyUI comes up or goes down, not on every try.
  void _noteComfy(bool up, String url) {
    if (_comfyUp == up) return;
    _comfyUp = up;
    debugPrint(
      up
          ? 'ComfyUI: answering at $url'
          : 'ComfyUI: not answering at $url; looking for it',
    );
  }

  /// After a Ready check: keeps looking while ComfyUI is down, stops once it
  /// answers or the desk is on another backend.
  void _watchComfy(StudioReadyReport report) {
    final settings = context.read<StorageService>().imageGenSettings;
    if (settings.imageGenBackend != 'comfyui') {
      _comfyBackoff?.stop();
      _stopUpWatch();
      return;
    }
    if (report.objectInfo != null) {
      _comfyBackoff?.stop();
      _noteComfy(true, settings.comfyUiUrl);
      _comfyUpWatch ??= Timer.periodic(kComfyUpCheckEvery, (_) => _stillUp());
      return;
    }
    _stopUpWatch();
    _noteComfy(false, settings.comfyUiUrl);
    (_comfyBackoff ??= ComfyBackoff(attempt: _lookForComfy)).start();
  }

  void _stopUpWatch() {
    _comfyUpWatch?.cancel();
    _comfyUpWatch = null;
  }

  /// A ComfyUI that answered is asked whether it still does. When it does
  /// not, the desk says so once, lists the models again (which clears them)
  /// and checks readiness, which starts looking for it.
  Future<void> _stillUp() async {
    if (_askingIfUp || !mounted) return;
    final settings = context.read<StorageService>().imageGenSettings;
    if (settings.imageGenBackend != 'comfyui') {
      _stopUpWatch();
      return;
    }
    _askingIfUp = true;
    try {
      final url = ComfyUiService.ensureHttpScheme(settings.comfyUiUrl);
      if (await _finder().answers(url) || !mounted) return;
      _stopUpWatch();
      _noteComfy(false, settings.comfyUiUrl);
      _refreshCatalog(settings, force: true);
      _checkReady(force: true);
    } finally {
      _askingIfUp = false;
    }
  }
}
