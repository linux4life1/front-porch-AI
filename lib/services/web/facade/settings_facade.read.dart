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

// The read half of the web Settings adapter: one JSON snapshot of the
// generation, backend, reasoning and Porch Life state the PWA renders.
// Every key is part of the wire contract and additive only — a browser
// running an older bundle must keep working against a newer host.

part of 'settings_facade.dart';

extension SettingsFacadeRead on SettingsFacade {
  Map<String, dynamic> read() {
    _seedReasoningCatalog();
    _kickRemoteEffortProbe();
    final g = _storage.generationSettings;
    final b = _storage.backendSettings;
    return {
      'backend': SettingsFacade._name(_llm.activeBackend),
      'backends': SettingsFacade.backends,
      'isLocal': _llm.isLocal,
      'loadedModel': _loadedModel(),
      'remoteApiUrl': b.remoteApiUrl,
      'remoteModelName': b.remoteModelName,
      'hasApiKey': b.remoteApiKey.isNotEmpty,
      'remoteApiUrlsWithKeys': b.remoteApiUrlsWithKeys,
      'omlxAvailable': Platform.isMacOS,
      'remoteConfigured': _llm.openRouterService.isConfigured,
      'remoteReachability': _llm.openRouterService.reachability.name,
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
      'reasoningLocalSupport': _thinkingSupportName,
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
        'dynamicTempRange': g.dynamicTempRange,
        'dynamicResponses': g.dynamicResponses,
        'dynamicResponseInterval': g.dynamicResponseInterval,
        'dynamicResponseMaxMessages': g.dynamicResponseMaxMessages,
        // Away pace (Living Time) — additive.
        'dynamicResponsePacePeriods': g.dynamicResponsePacePeriods,
        // Output Sanitizer (audit P2.13) — additive; older PWAs ignore.
        'outputSanitizerEnabled': g.outputSanitizerEnabled,
        'sanitiseExistingHistory': g.sanitiseExistingHistory,
        'outputSanitizerRules': [
          for (final r in g.outputSanitizerRules) r.toJson(),
        ],
        'stopSequences': g.stopSequences,
      },
      // General-tab extras the Generation card on web also hosts.
      'systemPrompt': g.systemPrompt,
      'bannedPhrases': _storage.realismSettings.bannedPhrases,
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
        'webSearchDefault': _storage.webSearchSettings.webSearchDefault,
        'hasSearchApiKey': _storage.webSearchSettings.hasApiKey,
        'wikiBaseUrl': _storage.webSearchSettings.wikiBaseUrl,
        'wikiSavedUrls': _storage.webSearchSettings.savedWikiUrls,
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
        'preferTextEvals': _storage.realismSettings.preferTextEvals,
      },
      // Spell check language. The browser does its own spell checking, so the
      // web cannot reuse the desktop's engine — but it must obey the same
      // choice, or a German-desktop user gets English underlined on one
      // surface and not the other. The PWA applies this as the `lang`
      // attribute on its prose inputs, which is what Chrome and Safari read.
      // Additive and nullable-safe: an older web client ignores the key.
      'spellCheckLanguage': _storage.spellCheckLanguage,
      ...readWorkerSettings(_storage, _llm),
    };
  }

  /// Dictionary tags the host can actually check, for the web's picker.
  /// Async because it asks the native side, so it cannot live in [read] —
  /// the routes merge it in.
  Future<List<String>> spellCheckLanguages() =>
      DesktopSpellCheckService.availableLanguages();
}
