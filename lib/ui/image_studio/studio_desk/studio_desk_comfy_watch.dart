// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'studio_desk_host.dart';

/// Finding ComfyUI while the desk is open: on open, on Check, and again and
/// again (2 s, doubling to 30 s) while it does not answer, so a ComfyUI
/// started after Front Porch, or on another port, is picked up by itself.
/// While it answers it is asked every [kComfyUpCheckEvery] whether it still
/// does, so one that was closed or restarted elsewhere is noticed too.
class StudioDeskComfyWatch {
  StudioDeskComfyWatch(this._host, {required this.recheck});

  final StudioDeskHost _host;

  /// Lists the models again and judges Ready again, both forced.
  final void Function(ImageGenSettings settings) recheck;

  ComfyBackoff? _comfyBackoff;
  Future<bool>? _looking;
  Timer? _comfyUpWatch;
  bool _askingIfUp = false;
  bool? _comfyUp;
  String? _comfyOffer;

  /// An address where ComfyUI answered instead of the saved one.
  String? get offer => _comfyOffer;

  void clearOffer() => _host.rebuildState(() => _comfyOffer = null);

  ImageGenSettings _settings() =>
      _host.context.read<StorageService>().imageGenSettings;

  ComfyUrlFinder _finder() {
    try {
      return _host.context.read<ComfyUrlFinder?>() ?? ComfyUrlFinder();
    } on ProviderNotFoundException {
      return ComfyUrlFinder();
    }
  }

  /// Looks for ComfyUI ([redialComfy]). True when it answers at the saved
  /// address (or the desk is no longer on ComfyUI), so the looking stops.
  /// Asked again while a look is under way, it waits for that one.
  Future<bool> look() =>
      _looking ??= _lookOnce().whenComplete(() => _looking = null);

  Future<bool> _lookOnce() async {
    if (!_host.mounted) return true;
    final settings = _settings();
    if (settings.imageGenBackend != 'comfyui') return true;
    final found = await redialComfy(settings, finder: _finder());
    if (!_host.mounted) return true;
    if (found.offer != _comfyOffer) {
      _host.rebuildState(() => _comfyOffer = found.offer);
    }
    _noteComfy(found.reachable, settings.comfyUiUrl);
    if (found.reachable) recheck(settings);
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
  void watch(StudioReadyReport report) {
    final settings = _settings();
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
    (_comfyBackoff ??= ComfyBackoff(attempt: look)).start();
  }

  void _stopUpWatch() {
    _comfyUpWatch?.cancel();
    _comfyUpWatch = null;
  }

  /// A ComfyUI that answered is asked whether it still does. When it does
  /// not, the desk says so once, lists the models again (which clears them)
  /// and checks readiness, which starts looking for it.
  Future<void> _stillUp() async {
    if (_askingIfUp || !_host.mounted) return;
    final settings = _settings();
    if (settings.imageGenBackend != 'comfyui') {
      _stopUpWatch();
      return;
    }
    _askingIfUp = true;
    try {
      final url = ComfyUiService.ensureHttpScheme(settings.comfyUiUrl);
      if (await _finder().answers(url) || !_host.mounted) return;
      _stopUpWatch();
      _noteComfy(false, settings.comfyUiUrl);
      recheck(settings);
    } finally {
      _askingIfUp = false;
    }
  }

  void dispose() {
    _comfyBackoff?.stop();
    _comfyUpWatch?.cancel();
  }
}
