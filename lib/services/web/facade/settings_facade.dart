// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/legacy_model_cleanup.dart';
import 'package:front_porch_ai/services/services.dart';

/// Read/write adapter over the core generation + backend settings for the web
/// Settings page. Reuses the existing StorageService setters (read live at
/// generation time) and LLMProvider for live backend switching — no new state.
/// Deliberately a focused slice of the huge desktop settings page: backend,
/// model/API, and the most-used sampler values.
class SettingsFacade {
  SettingsFacade(this._storage, this._llm, {ChatService? chat}) : _chat = chat;

  final StorageService _storage;
  final LLMProvider _llm;

  /// Optional: present whenever a chat is open, so the three engine-coupled
  /// Porch Life toggles reach the LIVE conversation the same way the desktop
  /// tab's onChanged does. Null-safe — with no chat bound, the write still
  /// lands in storage and applies to the next one.
  final ChatService? _chat;

  static const List<String> backends = ['kobold', 'openRouter', 'omlx'];

  /// Live remote API base — used by the settings route to decide whether a
  /// POST would actually change the generation host (step-up gate).
  String get currentRemoteApiUrl => _storage.backendSettings.remoteApiUrl;

  static String? _seededReasoningCatalogUrl;

  /// The identity the shared reasoning-effort helpers key on: the remote model
  /// name, or — for managed KoboldCpp — the loaded .gguf path the resolver
  /// registers under. Empty (generic chips, nothing claimed) until the file
  /// has actually been read, or in preset mode where there is no path.
  String get _reasoningModelKey {
    if (!_llm.isLocal) return _storage.backendSettings.remoteModelName;
    final path = _storage.lastUsedModelPath ?? '';
    return ReasoningSupportResolver.instance.peek(path) == null ? '' : path;
  }

  bool get _usesTemplateResolve =>
      _llm.activeBackend == BackendType.omlx ||
      isLocalRemoteUrl(_storage.backendSettings.remoteApiUrl);

  /// Template thinking verdict, kicking resolve once so a later state poll
  /// carries the answer. Mirrors the desktop block's kick-then-peek: this
  /// getter itself never touches disk or the network.
  ThinkingSupport? get _localThinkingSupport {
    if (_llm.isLocal) {
      final path = _storage.lastUsedModelPath ?? '';
      if (path.isEmpty) return null;
      if (!ReasoningSupportResolver.instance.isResolved(path)) {
        unawaited(ReasoningSupportResolver.instance.resolveLocalGguf(path));
        return null;
      }
      return ReasoningSupportResolver.instance.peek(path);
    }
    if (!_usesTemplateResolve) return null;
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty) return null;
    if (!ReasoningSupportResolver.instance.isResolved(name)) {
      unawaited(_resolveTemplate(name));
      return null;
    }
    return ReasoningSupportResolver.instance.peek(name);
  }

  Future<void> _resolveTemplate(String name) {
    final key = _storage.backendSettings.remoteApiKey;
    if (_llm.activeBackend == BackendType.omlx) {
      return ReasoningSupportResolver.instance.resolveOmlx(
        apiUrl: 'http://localhost:8000/v1',
        modelName: name,
        apiKey: key,
      );
    }
    return ReasoningSupportResolver.instance.resolveLmStudio(
      apiUrl: _storage.backendSettings.remoteApiUrl,
      modelName: name,
      apiKey: key,
    );
  }

  /// Await the local-template verdict so a web GET/POST does not return
  /// generic chips for one round and the truth on the next.
  Future<void> ensureReasoningResolved() async {
    if (_llm.isLocal) {
      final path = _storage.lastUsedModelPath ?? '';
      if (path.isEmpty) return;
      await ReasoningSupportResolver.instance.resolveLocalGguf(path);
      return;
    }
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty || !_usesTemplateResolve) return;
    await _resolveTemplate(name);
  }

  void _seedReasoningCatalog() {
    if (_llm.isLocal) return;
    final b = _storage.backendSettings;
    if (b.remoteApiKey.isEmpty && !isLocalRemoteUrl(b.remoteApiUrl)) return;
    final url = b.remoteApiUrl;
    if (_seededReasoningCatalogUrl == url) return;
    _seededReasoningCatalogUrl = url;
    unawaited(_llm.openRouterService.fetchAvailableModels());
  }

  Map<String, dynamic> read() {
    _seedReasoningCatalog();
    final g = _storage.generationSettings;
    final b = _storage.backendSettings;
    return {
      'backend': _name(_llm.activeBackend),
      'backends': backends,
      'isLocal': _llm.isLocal,
      'loadedModel': _loadedModel(),
      'remoteApiUrl': b.remoteApiUrl,
      'remoteModelName': b.remoteModelName,
      'hasApiKey': b.remoteApiKey.isNotEmpty,
      'contextSize': b.contextSize,
      // Reasoning / "thinking" — for reasoning models (GLM-*:thinking, etc.) this
      // must be on or the provider's reasoning tokens are discarded and no
      // <think> block is ever produced for the chat to show.
      'reasoningEnabled': b.reasoningEnabled,
      'reasoningEffort': b.reasoningEffort,
      // Kobold GGUF + oMLX on-disk template answer from
      // ReasoningSupportResolver. Same two fields, so the web control needs
      // no local-only branch — plus one ADDITIVE field for the copy that
      // only a template verdict can produce ("this model cannot think").
      'reasoningMandatory': reasoningEffortIsMandatory(_reasoningModelKey),
      'reasoningEfforts': reasoningEffortChipsFor(_reasoningModelKey),
      'reasoningLocalSupport': _localThinkingSupport?.name,
      'generation': {
        'temperature': g.temperature,
        'minP': g.minP,
        'topP': g.topP,
        'topK': g.topK,
        'dryMultiplier': g.dryMultiplier,
        'repeatPenalty': g.repeatPenalty,
        'repeatPenaltyTokens': g.repeatPenaltyTokens,
        'xtcThreshold': g.xtcThreshold,
        'xtcProbability': g.xtcProbability,
        'maxLength': g.maxLength,
        'minLength': g.minLength,
        'dynamicTempEnabled': g.dynamicTempEnabled,
        'dynamicResponses': g.dynamicResponses,
        'dynamicResponseInterval': g.dynamicResponseInterval,
        'dynamicResponseMaxMessages': g.dynamicResponseMaxMessages,
        // Away pace (Living Time) — additive.
        'dynamicResponsePacePeriods': g.dynamicResponsePacePeriods,
        // Output Sanitizer (audit P2.13) — additive; older PWAs ignore.
        'outputSanitizerEnabled': g.outputSanitizerEnabled,
        'outputSanitizerRules': [
          for (final r in g.outputSanitizerRules) r.toJson(),
        ],
      },
      // Ambitions + the promise ledger. Both work with the Realism Engine off,
      // so they are the two realism-adjacent settings the web needs first.
      // Additive and nullable-safe: an older web client ignores the key.
      'realism': {
        'ambitionsEnabled': _storage.realismSettings.ambitionsEnabled,
        'plannerEnabled': _storage.realismSettings.plannerEnabled,
        'promiseLedgerEnabled': _storage.realismSettings.promiseLedgerEnabled,
        // The rest of the Porch Life tab (2026-08-07). Additive keys only —
        // an older PWA simply ignores what it does not know.
        'realismDefaultWritable': true,
        'nsfwCooldownDefault': _storage.realismSettings.nsfwCooldownDefault,
        'needsSimDefault': _storage.realismSettings.needsSimDefault,
        'passageOfTimeDefault': _storage.realismSettings.passageOfTimeDefault,
        'standaloneClockEnabled':
            _storage.realismSettings.standaloneClockEnabled,
        'objectivesEnabled': _storage.realismSettings.objectivesEnabled,
        'pocketsEnabled': _storage.realismSettings.pocketsEnabled,
        'standingMoodEnabled': _storage.realismSettings.standingMoodEnabled,
        'pocketTransfersEnabled':
            _storage.realismSettings.pocketTransfersEnabled,
        // 2026-08-08: "Acts on desires" (After Dark) and the global Chaos Mode
        // default. Additive, as always — an older PWA ignores both keys.
        'intimateAgencyEnabled': _storage.realismSettings.intimateAgencyEnabled,
        'chaosModeDefault': _storage.realismSettings.chaosModeDefault,
        'sceneGuestDetectionEnabled':
            _storage.realismSettings.sceneGuestDetectionEnabled,
        'adultThemesEnabled': _storage.realismSettings.adultThemesEnabled,
        'weatherEnabled': _storage.realismSettings.weatherEnabled,
        'weatherFahrenheit': _storage.realismSettings.weatherFahrenheit,
        'dreamsEnabled': _storage.realismSettings.dreamsEnabled,
        'absenceBannerEnabled': _storage.realismSettings.absenceBannerEnabled,
        'absenceAckEnabled': _storage.realismSettings.absenceAckEnabled,
        'absenceThresholdHours': _storage.realismSettings.absenceThresholdHours,
        // Read-only context so the web can show the same honest warnings the
        // desktop does: the promise pass needs the Journal, and with realism
        // off there is no passage of time.
        'journalEnabled': _storage.memorySettings.journalEnabled,
        'characterEvolutionEnabled':
            _storage.memorySettings.characterEvolutionEnabled,
        'realismDefault': _storage.realismSettings.realismDefault,
      },
      // Spell check language. The browser does its own spell checking, so the
      // web cannot reuse the desktop's engine — but it must obey the same
      // choice, or a German-desktop user gets English underlined on one
      // surface and not the other. The PWA applies this as the `lang`
      // attribute on its prose inputs, which is what Chrome and Safari read.
      // Additive and nullable-safe: an older web client ignores the key.
      'spellCheckLanguage': _storage.spellCheckLanguage,
    };
  }

  /// Dictionary tags the host can actually check, for the web's picker.
  /// Async because it asks the native side, so it cannot live in [read] —
  /// the routes merge it in.
  Future<List<String>> spellCheckLanguages() =>
      DesktopSpellCheckService.availableLanguages();

  Future<void> update(Map<String, dynamic> body) async {
    final g = _storage.generationSettings;
    final b = _storage.backendSettings;

    final realism = body['realism'];
    if (realism is Map) {
      final amb = realism['ambitionsEnabled'];
      if (amb is bool) await _storage.realismSettings.setAmbitionsEnabled(amb);
      final planner = realism['plannerEnabled'];
      if (planner is bool) {
        await _storage.realismSettings.setPlannerEnabled(planner);
      }
      final prom = realism['promiseLedgerEnabled'];
      if (prom is bool) {
        await _storage.realismSettings.setPromiseLedgerEnabled(prom);
      }
      // Porch Life tab parity (2026-08-07). Each write mirrors the desktop
      // row: the three engine-coupled ones also push into the live chat the
      // way the Flutter tab's onChanged does, so a web toggle takes effect on
      // the open conversation instead of only on the next one.
      final rd = realism['realismDefault'];
      if (rd is bool) {
        await _storage.setRealismDefault(rd);
        _chat?.setRealismEnabled(rd);
      }
      final nsfw = realism['nsfwCooldownDefault'];
      if (nsfw is bool) {
        await _storage.setNsfwCooldownDefault(nsfw);
        _chat?.setNsfwCooldownEnabled(nsfw);
      }
      final needs = realism['needsSimDefault'];
      if (needs is bool) {
        await _storage.realismSettings.setNeedsSimDefault(needs);
        await _chat?.setNeedsSimEnabled(needs);
      }
      final pot = realism['passageOfTimeDefault'];
      if (pot is bool) {
        await _storage.setPassageOfTimeDefault(pot);
        _chat?.setPassageOfTimeEnabled(pot);
      }
      // No live-chat push: unlike the toggles around it, this one is read
      // per turn straight off StorageService (ChatService._standaloneClockActive
      // and ._clockRunning), so writing the setting IS the whole update and an
      // open conversation picks it up on its next turn.
      final sc = realism['standaloneClockEnabled'];
      if (sc is bool) await _storage.setStandaloneClockEnabled(sc);
      final adult = realism['adultThemesEnabled'];
      if (adult is bool) await _storage.setAdultThemesEnabled(adult);
      final growth = realism['characterEvolutionEnabled'];
      if (growth is bool) {
        await _storage.setCharacterEvolutionEnabled(growth);
      }
      final pockets = realism['pocketsEnabled'];
      if (pockets is bool) {
        await _storage.realismSettings.setPocketsEnabled(pockets);
      }
      final transfers = realism['pocketTransfersEnabled'];
      if (transfers is bool) {
        await _storage.realismSettings.setPocketTransfersEnabled(transfers);
      }
      final mood = realism['standingMoodEnabled'];
      if (mood is bool) {
        await _storage.realismSettings.setStandingMoodEnabled(mood);
      }
      // No live-chat push for either of these, and for the same reason the
      // standalone clock has none: both are read straight off StorageService at
      // the moment they matter. "Acts on desires" is resolved per turn when the
      // preferences fragment is built, and Chaos seeds when a chat is entered —
      // so writing the setting IS the whole update.
      final agency = realism['intimateAgencyEnabled'];
      if (agency is bool) {
        await _storage.realismSettings.setIntimateAgencyEnabled(agency);
      }
      final chaos = realism['chaosModeDefault'];
      if (chaos is bool) {
        await _storage.realismSettings.setChaosModeDefault(chaos);
      }
      final guests = realism['sceneGuestDetectionEnabled'];
      if (guests is bool) {
        await _storage.realismSettings.setSceneGuestDetectionEnabled(guests);
      }
      final objs = realism['objectivesEnabled'];
      if (objs is bool) {
        await _storage.setObjectivesEnabled(objs);
        // Engine-coupled in the same sense the rows above are: push into the
        // open conversation so a web toggle takes effect there too, not only
        // on the next chat.
        await _chat?.setObjectivesEnabled(objs);
      }
      final wx = realism['weatherEnabled'];
      if (wx is bool) await _storage.setWeatherEnabled(wx);
      final wf = realism['weatherFahrenheit'];
      if (wf is bool) await _storage.setWeatherFahrenheit(wf);
      final dre = realism['dreamsEnabled'];
      if (dre is bool) await _storage.setDreamsEnabled(dre);
      final ab = realism['absenceBannerEnabled'];
      if (ab is bool) await _storage.setAbsenceBannerEnabled(ab);
      final aa = realism['absenceAckEnabled'];
      if (aa is bool) await _storage.setAbsenceAckEnabled(aa);
      final ath = realism['absenceThresholdHours'];
      if (ath is int) await _storage.setAbsenceThresholdHours(ath);
    }

    final spellLanguage = body['spellCheckLanguage'];
    if (spellLanguage is String && spellLanguage.isNotEmpty) {
      await _storage.setSpellCheckLanguage(spellLanguage);
    }

    final backend = body['backend']?.toString();
    if (backend != null) {
      final type = _parse(backend);
      if (type != null) await _llm.setActiveBackend(type);
    }

    var remoteChanged = false;
    if (body.containsKey('remoteApiUrl')) {
      await b.setRemoteApiUrl(body['remoteApiUrl'].toString());
      remoteChanged = true;
    }
    if (body.containsKey('remoteModelName')) {
      await b.setRemoteModelName(body['remoteModelName'].toString());
      remoteChanged = true;
    }
    // Only overwrite the API key when a non-empty value is provided (the read
    // path never returns it, so an empty field means "leave unchanged").
    final apiKey = body['apiKey']?.toString();
    if (apiKey != null && apiKey.isNotEmpty) {
      await b.setRemoteApiKey(apiKey);
      remoteChanged = true;
    }

    final ctx = body['contextSize'];
    if (ctx is num) await b.setContextSize(ctx.toInt());

    final reasoning = body['reasoningEnabled'];
    if (reasoning is bool) {
      final lockedOff =
          !reasoning && reasoningEffortIsMandatory(b.remoteModelName);
      if (!lockedOff) await b.setReasoningEnabled(reasoning);
    }
    final effort = body['reasoningEffort']?.toString();
    if (effort != null && effort.isNotEmpty) await b.setReasoningEffort(effort);
    if (remoteChanged) {
      _llm.openRouterService.configure(
        apiUrl: b.remoteApiUrl,
        apiKey: b.remoteApiKey,
        modelName: b.remoteModelName,
      );
      if (_usesTemplateResolve) {
        unawaited(_resolveTemplate(b.remoteModelName));
      } else {
        kickReasoningEffortProbe(
          model: b.remoteModelName,
          apiUrl: b.remoteApiUrl,
          apiKey: b.remoteApiKey,
        );
      }
    }

    final gen = body['generation'];
    if (gen is Map) {
      final t = gen['temperature'];
      if (t is num) await g.setTemperature(t.toDouble());
      final mp = gen['minP'];
      if (mp is num) await g.setMinP(mp.toDouble());
      final tp = gen['topP'];
      if (tp is num) await g.setTopP(tp.toDouble());
      final tk = gen['topK'];
      if (tk is num) await g.setTopK(tk.toInt());
      final dm = gen['dryMultiplier'];
      if (dm is num) await g.setDryMultiplier(dm.toDouble());
      final rp = gen['repeatPenalty'];
      if (rp is num) await g.setRepeatPenalty(rp.toDouble());
      final rpt = gen['repeatPenaltyTokens'];
      if (rpt is num) await g.setRepeatPenaltyTokens(rpt.toInt());
      final xt = gen['xtcThreshold'];
      if (xt is num) await g.setXtcThreshold(xt.toDouble());
      final xp = gen['xtcProbability'];
      if (xp is num) await g.setXtcProbability(xp.toDouble());
      final ml = gen['maxLength'];
      if (ml is num) await g.setMaxLength(ml.toInt());
      final mn = gen['minLength'];
      if (mn is num) await g.setMinLength(mn.toInt());
      final dt = gen['dynamicTempEnabled'];
      if (dt is bool) await g.setDynamicTempEnabled(dt);
      final dr = gen['dynamicResponses'];
      if (dr is bool) await g.setDynamicResponses(dr);
      final dri = gen['dynamicResponseInterval'];
      if (dri is num) await g.setDynamicResponseInterval(dri.toInt());
      final drm = gen['dynamicResponseMaxMessages'];
      if (drm is num) await g.setDynamicResponseMaxMessages(drm.toInt());
      final drp = gen['dynamicResponsePacePeriods'];
      if (drp is num) await g.setDynamicResponsePacePeriods(drp.toInt());
      // Output Sanitizer (audit P2.13) — host-side rules apply to every
      // surface that generates through this install.
      final ose = gen['outputSanitizerEnabled'];
      if (ose is bool) await g.setOutputSanitizerEnabled(ose);
      final osr = gen['outputSanitizerRules'];
      if (osr is List) {
        await g.setOutputSanitizerRules(OutputSanitizerRule.listFromJson(osr));
      }
    }
  }

  String _loadedModel() {
    final b = _storage.backendSettings;
    if (_llm.isLocal) {
      final path = b.lastUsedModelPath;
      return (path != null && path.isNotEmpty)
          ? p.basename(path)
          : 'No model loaded';
    }
    return b.remoteModelName.isNotEmpty ? b.remoteModelName : 'Not set';
  }

  static String _name(BackendType t) => switch (t) {
    BackendType.kobold => 'kobold',
    BackendType.openRouter => 'openRouter',
    BackendType.omlx => 'omlx',
  };

  static BackendType? _parse(String s) => switch (s) {
    'kobold' => BackendType.kobold,
    // Legacy 'pseudoRemote' now maps to the local Kobold backend.
    'pseudoRemote' => BackendType.kobold,
    'openRouter' => BackendType.openRouter,
    'omlx' => BackendType.omlx,
    _ => null,
  };

  /// Legacy-engine model files still on the host's disk (sidecar
  /// retirement cleanup — desktop parity: the Reclaim Disk Space card).
  Future<Map<String, dynamic>> legacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return {'groups': const [], 'totalBytes': 0};
    final groups = await LegacyModelCleanup.scan(root);
    return {
      'groups': [
        for (final g in groups) {'label': g.label, 'bytes': g.bytes},
      ],
      'totalBytes': groups.fold(0, (sum, g) => sum + g.bytes),
    };
  }

  /// Deletes the scanned legacy files (the scan reruns server-side — the
  /// client never supplies paths). Returns bytes freed.
  Future<int> reclaimLegacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return 0;
    return LegacyModelCleanup.reclaim(root);
  }
}
