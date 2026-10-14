// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart'
    show withoutCity96Ask;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_jobs.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The phone wizard's create fields as the generator's inputs. Quick,
/// Guided and Automated all arrive here with the concept and context the
/// web wizard assembled per mode (as the desktop creator does); the one
/// mode-specific step is Automated's description, kept verbatim.
GenRunInputs chargenInputsFromFields(String name, Map<String, dynamic> f) {
  final mode = f['mode']?.toString() ?? 'quick';
  final concept = f['concept']?.toString() ?? '';
  return GenRunInputs(
    name: name,
    concept: concept,
    personalityKeywords: f['personalityKeywords']?.toString() ?? '',
    artStyle: f['artStyle']?.toString() ?? '',
    greetingLength:
        f['greetingLength']?.toString() ?? 'Medium (2-4 paragraphs)',
    altGreetingCount: (f['altGreetingCount'] as num?)?.toInt() ?? 2,
    greetingTones: _strList(f['greetingTones'], const ['Neutral']),
    generateLorebook: f['generateLorebook'] != false,
    loreCategories: _strList(f['loreCategories'], const []),
    loreDepth: f['loreDepth']?.toString() ?? 'Standard',
    includeDynamicMacros: f['includeDynamicMacros'] == true,
    narrativePerspective: f['narrativePerspective']?.toString() ?? 'first',
    narrativeTense: f['narrativeTense']?.toString() ?? 'present',
    age: f['age']?.toString() ?? '',
    sex: f['sex']?.toString() ?? '',
    relationship: f['relationship']?.toString() ?? '',
    descriptionDetail: f['descriptionDetail']?.toString() ?? '2-3 paragraphs',
    backstory: f['backstory']?.toString() ?? '',
    scenario: f['scenario']?.toString() ?? '',
    characterContext: f['characterContext']?.toString() ?? '',
    generateDescription: mode != 'automated',
    worldLore: (f['worldLore']?.toString().trim().isNotEmpty ?? false)
        ? f['worldLore'].toString()
        : null,
    nsfwEnabled: f['nsfwEnabled'] == true,
    reasoningEnabled: f['reasoningEnabled'] == true,
    descriptionOverride: mode == 'automated' && concept.isNotEmpty
        ? concept
        : null,
  );
}

/// Coerce a JSON value to a `List<String>`, dropping blanks; falls back to
/// [fallback] when absent or empty. Used for greeting tones / lore categories.
List<String> _strList(dynamic v, List<String> fallback) {
  if (v is List) {
    final out = v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return out.isEmpty ? fallback : out;
  }
  return fallback;
}

/// The create fields that are not generation inputs but ride along to the
/// save: a persona's birthday and picture.
Map<String, dynamic> chargenSaveExtras(Map<String, dynamic> f) => {
  for (final k in const ['birthday', 'portraitPersonaId'])
    if (f[k] != null) k: f[k],
};

/// Where a character created here keeps what it was asked for that its
/// greeting recipe does not carry (the concept, the lore categories and
/// depth, the wizard mode), so a lorebook rewrite or the Profile step after
/// a restart asks the same way. Beside the recipe's own key; additive.
const kCreatorInputsExtensionKey = 'creator_inputs';

const _stampConceptChars = 4000;

/// Write [inputs] and [mode] onto [card] (see [kCreatorInputsExtensionKey]).
void stampCreatorInputs(CharacterCard card, GenRunInputs inputs, String mode) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  final concept = inputs.concept;
  raw[kCreatorInputsExtensionKey] = {
    'concept': concept.length > _stampConceptChars
        ? concept.substring(0, _stampConceptChars)
        : concept,
    'loreCategories': inputs.loreCategories,
    'loreDepth': inputs.loreDepth,
    if (mode.isNotEmpty) 'mode': mode,
  };
  card.rawExtensions = raw;
}

/// What a saved character was asked for, read back from its stamp; null
/// when it carries none.
({String concept, List<String> loreCategories, String loreDepth, String mode})?
readCreatorInputs(CharacterCard? card) {
  final raw = card?.rawExtensions?[kCreatorInputsExtensionKey];
  if (raw is! Map) return null;
  String text(String k) => raw[k] is String ? raw[k] as String : '';
  final depth = text('loreDepth');
  return (
    concept: text('concept'),
    loreCategories: [
      if (raw['loreCategories'] is List)
        for (final c in raw['loreCategories'] as List)
          if (c is String && c.trim().isNotEmpty) c,
    ],
    loreDepth: depth.isEmpty ? 'Standard' : depth,
    mode: text('mode'),
  );
}

/// Creating a whole character and saving it: the one-shot create (both
/// phases back to back, as before the Profile step) and the save every
/// finished card goes through.
class ChargenCreate {
  ChargenCreate(this._llm, this._characters, this._hub, this._imageGen);

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;
  final ImageGenService? _imageGen;

  /// Whether a whole character is being created right now.
  bool creating = false;

  /// How characters saved here were asked for (the last few), so a later
  /// rewrite of their lorebook or profile asks the same way.
  final Map<String, GenRunInputs> _inputs = {};

  GenRunInputs? inputsFor(String characterId) => _inputs[characterId];

  /// How a lorebook rewrite of saved [card] asks: as it was created (the
  /// cache, else the card's stamp), else from its description.
  ({String concept, List<String> loreCategories, String loreDepth}) loreAskFor(
    String characterId,
    CharacterCard card,
  ) {
    final cached = _inputs[characterId];
    if (cached != null) {
      return (
        concept: cached.concept,
        loreCategories: cached.loreCategories,
        loreDepth: cached.loreDepth,
      );
    }
    final stamp = readCreatorInputs(card);
    return (
      concept: (stamp?.concept ?? '').isEmpty
          ? card.description
          : stamp!.concept,
      loreCategories: stamp?.loreCategories ?? const [],
      loreDepth: stamp?.loreDepth ?? 'Standard',
    );
  }

  void _rememberInputs(String id, GenRunInputs inputs) {
    _inputs.remove(id);
    _inputs[id] = inputs;
    while (_inputs.length > 8) {
      _inputs.remove(_inputs.keys.first);
    }
  }

  /// Called with each saved character and how its greetings were written,
  /// before `chargen_done` goes out.
  void Function(String id, GreetingRecipe? recipe)? onSaved;

  /// The one-shot create: both phases, then the save. Answers at once.
  void startOneShot(String name, Map<String, dynamic> fields, LLMService svc) =>
      unawaited(_run(name, fields, svc));

  Future<void> _run(
    String name,
    Map<String, dynamic> fields,
    LLMService svc,
  ) async {
    creating = true;
    String? reported;
    try {
      final i = chargenInputsFromFields(name, fields);
      final gen = CharacterGenService(svc);
      final card = await gen.generateCharacter(
        name: i.name,
        concept: i.concept,
        personalityKeywords: i.personalityKeywords,
        artStyle: i.artStyle,
        greetingLength: i.greetingLength,
        altGreetingCount: i.altGreetingCount,
        greetingTones: i.greetingTones,
        generateLorebook: i.generateLorebook,
        loreCategories: i.loreCategories,
        loreDepth: i.loreDepth,
        includeDynamicMacros: i.includeDynamicMacros,
        narrativePerspective: i.narrativePerspective,
        narrativeTense: i.narrativeTense,
        age: i.age,
        sex: i.sex,
        relationship: i.relationship,
        descriptionDetail: i.descriptionDetail,
        backstory: i.backstory,
        scenario: i.scenario,
        characterContext: i.characterContext,
        generateDescription: i.generateDescription,
        worldLore: i.worldLore,
        nsfwEnabled: i.nsfwEnabled,
        reasoningEnabled: i.reasoningEnabled,
        descriptionOverride: i.descriptionOverride,
        onStatus: (s) =>
            _hub?.broadcast({'event': 'chargen_status', 'data': s}),
        onError: (m) => reported = m,
      );
      await saveGenerated(
        card,
        gen,
        i,
        fields,
        mode: fields['mode']?.toString() ?? '',
        failure: reported,
      );
    } catch (e) {
      _hub?.broadcast(chargenErrorEvent('$e'));
    } finally {
      creating = false;
    }
  }

  /// Save a finished [card] that [gen] wrote from [inputs]: the persona's
  /// birthday and picture from [extras], else a rendered portrait; then
  /// `chargen_done`. Returns the saved id, or null after a `chargen_error`.
  /// [mode] is the wizard mode, stamped with the inputs. With no card,
  /// `chargen_error` says why: [failure] (what the engine reported), else
  /// what [gen] recorded (a refusal keeps the provider's words).
  Future<String?> saveGenerated(
    CharacterCard? card,
    CharacterGenService gen,
    GenRunInputs inputs,
    Map<String, dynamic> extras, {
    String mode = '',
    String? failure,
  }) async {
    if (card == null) {
      _hub?.broadcast(
        chargenErrorEvent(
          chargenFailure(gen, failure, 'generation produced no card'),
        ),
      );
      return null;
    }
    stampCreatorInputs(card, inputs, mode);
    // A persona's birthday rides along, as the desktop's realismBirthday.
    final birthday = extras['birthday']?.toString().trim() ?? '';
    if (birthday.isNotEmpty) {
      card.frontPorchExtensions =
          (card.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            birthday: birthday,
          );
    }
    // Auto-render a portrait when an image backend is configured (web-only
    // convenience; desktop generation moved to the explicit Portrait &
    // Avatars panel). A character made from a persona keeps the persona's
    // picture.
    final personaPortrait = _characters.portraitFromFields(extras);
    final portrait = personaPortrait == null
        ? await renderPortrait(inputs.name, gen.generatedImagePrompt)
        : null;
    final saved = await _characters.persistNewCard(
      card,
      portraitBytes: portrait,
      portraitPath: personaPortrait,
    );
    if (saved == null) {
      _hub?.broadcast(
        chargenErrorEvent('failed to save the generated character'),
      );
      return null;
    }
    final id = saved['id']?.toString();
    if (id != null) {
      _rememberInputs(id, inputs);
      onSaved?.call(id, gen.greetingRecipe);
    }
    _hub?.broadcast({
      'event': 'chargen_done',
      'id': saved['id'],
      'name': saved['name'],
    });
    return id;
  }

  /// Render a portrait via the configured image backend, or null if there
  /// is no backend / prompt / on failure (generation never blocks on the
  /// image step). Mirrors the desktop buildPortraitPromptSeed: strip the
  /// character name from the LLM-authored prompt so the image model doesn't
  /// render it as text.
  Future<List<int>?> renderPortrait(String name, String? imagePrompt) async {
    final svc = _imageGen;
    final prompt = imagePrompt?.trim() ?? '';
    if (svc == null || !svc.isConfigured || prompt.isEmpty) return null;
    var clean = prompt;
    for (final part in name.split(RegExp(r'\s+'))) {
      if (part.length > 2) {
        clean = clean.replaceAll(
          RegExp('\\b${RegExp.escape(part)}\\b', caseSensitive: false),
          '',
        );
      }
    }
    clean = clean
        .replaceAll(RegExp(r',\s*,'), ',')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (clean.startsWith(',')) clean = clean.substring(1).trim();
    if (clean.isEmpty) clean = prompt;
    _hub?.broadcast({
      'event': 'chargen_status',
      'data': 'Generating portrait...',
    });
    try {
      // Configured size, oriented portrait, configured default negative —
      // mirrors the desktop creator (the old fixed 512x512 failed on remote
      // models that reject small sizes and capped local quality).
      // No desktop dialog can be answered from here; see ImageFacade.generate.
      return await withoutCity96Ask(
        () => svc.generateImage(prompt: clean, isPortrait: true),
      );
    } catch (_) {
      _hub?.broadcast({
        'event': 'chargen_status',
        'data': 'Portrait generation skipped',
      });
      return null;
    }
  }

  /// The LLM backend, when it is ready to generate.
  LLMService? get readyService {
    final svc = _llm.activeService;
    return svc.isReady ? svc : null;
  }
}
