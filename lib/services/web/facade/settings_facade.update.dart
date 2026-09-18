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

// The write half of the web Settings adapter. Each branch mirrors the
// desktop control it belongs to, and the row comments record which ones
// push into the LIVE conversation versus which are read per turn straight
// off StorageService — that distinction is the parity contract, not trivia.

part of 'settings_facade.dart';

extension SettingsFacadeUpdate on SettingsFacade {
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
        await _storage.realismSettings.setRealismDefault(rd);
        _chat?.setRealismEnabled(rd);
      }
      final nsfw = realism['nsfwCooldownDefault'];
      if (nsfw is bool) {
        await _storage.realismSettings.setNsfwCooldownDefault(nsfw);
        _chat?.setNsfwCooldownEnabled(nsfw);
      }
      final needs = realism['needsSimDefault'];
      if (needs is bool) {
        await _storage.realismSettings.setNeedsSimDefault(needs);
        await _chat?.setNeedsSimEnabled(needs);
      }
      final pot = realism['passageOfTimeDefault'];
      if (pot is bool) {
        await _storage.realismSettings.setPassageOfTimeDefault(pot);
        _chat?.setPassageOfTimeEnabled(pot);
      }
      // No live-chat push: unlike the toggles around it, this one is read
      // per turn straight off StorageService (ChatService._standaloneClockActive
      // and ._clockRunning), so writing the setting IS the whole update and an
      // open conversation picks it up on its next turn.
      final sc = realism['standaloneClockEnabled'];
      if (sc is bool) {
        await _storage.realismSettings.setStandaloneClockEnabled(sc);
      }
      final adult = realism['adultThemesEnabled'];
      if (adult is bool) {
        await _storage.realismSettings.setAdultThemesEnabled(adult);
      }
      final growth = realism['characterEvolutionEnabled'];
      if (growth is bool) {
        await _storage.memorySettings.setCharacterEvolutionEnabled(growth);
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
      final webSearch = realism['webSearchDefault'];
      if (webSearch is bool) {
        await _storage.webSearchSettings.setWebSearchDefault(webSearch);
      }
      final searchKey = realism['searchApiKey']?.toString();
      if (searchKey != null) {
        await _storage.webSearchSettings.setSearchApiKey(searchKey);
      }
      final wikiUrl = realism['wikiBaseUrl']?.toString();
      if (wikiUrl != null) {
        await _storage.webSearchSettings.setWikiBaseUrl(wikiUrl);
        if (wikiUrl.trim().isNotEmpty) {
          await _storage.webSearchSettings.addSavedWikiUrl(wikiUrl);
        }
      }
      final wikiAdd = realism['wikiSavedUrlAdd']?.toString();
      if (wikiAdd != null) {
        await _storage.webSearchSettings.addSavedWikiUrl(wikiAdd);
      }
      final wikiRemove = realism['wikiSavedUrlRemove']?.toString();
      if (wikiRemove != null) {
        await _storage.webSearchSettings.removeSavedWikiUrl(wikiRemove);
      }
      final guests = realism['sceneGuestDetectionEnabled'];
      if (guests is bool) {
        await _storage.realismSettings.setSceneGuestDetectionEnabled(guests);
      }
      final objs = realism['objectivesEnabled'];
      if (objs is bool) {
        await _storage.realismSettings.setObjectivesEnabled(objs);
        // Engine-coupled in the same sense the rows above are: push into the
        // open conversation so a web toggle takes effect there too, not only
        // on the next chat.
        await _chat?.setObjectivesEnabled(objs);
      }
      final wx = realism['weatherEnabled'];
      if (wx is bool) await _storage.realismSettings.setWeatherEnabled(wx);
      final wf = realism['weatherFahrenheit'];
      if (wf is bool) await _storage.realismSettings.setWeatherFahrenheit(wf);
      final dre = realism['dreamsEnabled'];
      if (dre is bool) await _storage.realismSettings.setDreamsEnabled(dre);
      final ab = realism['absenceBannerEnabled'];
      if (ab is bool) {
        await _storage.realismSettings.setAbsenceBannerEnabled(ab);
      }
      final aa = realism['absenceAckEnabled'];
      if (aa is bool) await _storage.realismSettings.setAbsenceAckEnabled(aa);
      final ath = realism['absenceThresholdHours'];
      if (ath is int) {
        await _storage.realismSettings.setAbsenceThresholdHours(ath);
      }
      final pt = realism['preferTextEvals'];
      if (pt is bool) {
        await _storage.realismSettings.setPreferTextEvals(pt);
      }
    }

    final spellLanguage = body['spellCheckLanguage'];
    if (spellLanguage is String && spellLanguage.isNotEmpty) {
      await _storage.setSpellCheckLanguage(spellLanguage);
    }

    await updateWorkerSettings(storage: _storage, body: body);

    final backend = body['backend']?.toString();
    if (backend != null) {
      final type = SettingsFacade._parse(backend);
      if (type != null) await _llm.setActiveBackend(type);
    }

    var remoteChanged = false;
    var urlChanged = false;
    if (body.containsKey('remoteApiUrl')) {
      final nextUrl = body['remoteApiUrl'].toString();
      urlChanged = nextUrl != b.remoteApiUrl;
      await b.setRemoteApiUrl(nextUrl);
      remoteChanged = true;
    }
    // A provider-bar swap sends the previous model's id in the same POST.
    // setRemoteApiUrl already restored this host's last model — do not
    // stamp the leftover onto the new host.
    if (body.containsKey('remoteModelName') && !urlChanged) {
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
      final dtr = gen['dynamicTempRange'];
      if (dtr is num) await g.setDynamicTempRange(dtr.toDouble());
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
      final seh = gen['sanitiseExistingHistory'];
      // Apply AFTER the enable flag: turning sanitizer off clears this in
      // setOutputSanitizerEnabled, and a stale true from the PWA must not
      // re-arm a history rewrite without the confirm dialog.
      if (seh is bool && g.outputSanitizerEnabled) {
        await g.setSanitiseExistingHistory(seh);
      }
      final stops = gen['stopSequences'];
      if (stops is List) {
        await g.setStopSequences([
          for (final s in stops)
            if (s is String && s.isNotEmpty) s,
        ]);
      }
    }

    final prompt = body['systemPrompt']?.toString();
    if (prompt != null) await g.setSystemPrompt(prompt);
    final bans = body['bannedPhrases'];
    if (bans is List) {
      await _storage.realismSettings.setBannedPhrases([
        for (final s in bans)
          if (s is String && s.isNotEmpty) s,
      ]);
    }
  }
}
