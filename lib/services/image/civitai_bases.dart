// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One still-image base CivitAI's `baseModels` filter accepts.
/// [api] is the enum string from `GET /api/v1/enums` (`BaseModel`), or, for
/// a choice that stands for several bases, the picker's own key for it.
class CivitaiBaseChoice {
  final String label;
  final String api;

  /// The bases a choice for several sends. Empty means just [api].
  final List<String> several;

  const CivitaiBaseChoice(this.label, this.api, [this.several = const []]);

  /// What a search sends as `baseModels`.
  List<String> get sends => several.isEmpty ? [api] : several;
}

/// Every Flux.2 Klein base: CivitAI files Klein LoRAs under all four.
const kCivitaiKleinAll =
    CivitaiBaseChoice('Flux.2 Klein (all)', 'Flux.2 Klein (all)', [
      'Flux.2 Klein 9B',
      'Flux.2 Klein 9B-base',
      'Flux.2 Klein 4B',
      'Flux.2 Klein 4B-base',
    ]);

/// A labeled group in the Get a model / Get a LoRA picker.
class CivitaiBaseGroup {
  final String title;
  final List<CivitaiBaseChoice> choices;

  const CivitaiBaseGroup(this.title, this.choices);
}

/// Still-image bases only. Video, 3D, and audio enums are omitted because
/// this studio has no way to run them. Qwen-Image 2512 and Image Edit are
/// versions of the Qwen base, not their own filter values.
const List<CivitaiBaseGroup> kCivitaiBaseGroups = [
  CivitaiBaseGroup('Flux', [
    CivitaiBaseChoice('Flux.1 Schnell', 'Flux.1 S'),
    CivitaiBaseChoice('Flux.1 Dev', 'Flux.1 D'),
    CivitaiBaseChoice('Flux.1 Krea', 'Flux.1 Krea'),
    CivitaiBaseChoice('Flux.1 Kontext', 'Flux.1 Kontext'),
    CivitaiBaseChoice('Flux.2 Dev', 'Flux.2 D'),
    kCivitaiKleinAll,
    CivitaiBaseChoice('Flux.2 Klein 9B', 'Flux.2 Klein 9B'),
    CivitaiBaseChoice('Flux.2 Klein 9B base', 'Flux.2 Klein 9B-base'),
    CivitaiBaseChoice('Flux.2 Klein 4B', 'Flux.2 Klein 4B'),
    CivitaiBaseChoice('Flux.2 Klein 4B base', 'Flux.2 Klein 4B-base'),
  ]),
  CivitaiBaseGroup('Qwen', [
    CivitaiBaseChoice('Qwen-Image, 2512, and Image Edit', 'Qwen'),
    CivitaiBaseChoice('Qwen 2', 'Qwen 2'),
    CivitaiBaseChoice('Qwen 2.1', 'Qwen 2.1'),
    CivitaiBaseChoice('Qwen 3', 'Qwen 3'),
  ]),
  CivitaiBaseGroup('Z-Image', [
    CivitaiBaseChoice('Z-Image Turbo', 'ZImageTurbo'),
    CivitaiBaseChoice('Z-Image', 'ZImageBase'),
  ]),
  CivitaiBaseGroup('SD 3', [
    CivitaiBaseChoice('SD 3', 'SD 3'),
    CivitaiBaseChoice('SD 3.5', 'SD 3.5'),
    CivitaiBaseChoice('SD 3.5 Medium', 'SD 3.5 Medium'),
    CivitaiBaseChoice('SD 3.5 Large', 'SD 3.5 Large'),
    CivitaiBaseChoice('SD 3.5 Large Turbo', 'SD 3.5 Large Turbo'),
  ]),
  CivitaiBaseGroup('SDXL, Pony, Illustrious', [
    CivitaiBaseChoice('SDXL 0.9', 'SDXL 0.9'),
    CivitaiBaseChoice('SDXL 1.0', 'SDXL 1.0'),
    CivitaiBaseChoice('SDXL 1.0 LCM', 'SDXL 1.0 LCM'),
    CivitaiBaseChoice('SDXL Lightning', 'SDXL Lightning'),
    CivitaiBaseChoice('SDXL Hyper', 'SDXL Hyper'),
    CivitaiBaseChoice('SDXL Turbo', 'SDXL Turbo'),
    CivitaiBaseChoice('SDXL Distilled', 'SDXL Distilled'),
    CivitaiBaseChoice('Pony', 'Pony'),
    CivitaiBaseChoice('Pony V7', 'Pony V7'),
    CivitaiBaseChoice('Illustrious', 'Illustrious'),
    CivitaiBaseChoice('NoobAI', 'NoobAI'),
  ]),
  CivitaiBaseGroup('SD 1 and SD 2', [
    CivitaiBaseChoice('SD 1.4', 'SD 1.4'),
    CivitaiBaseChoice('SD 1.5', 'SD 1.5'),
    CivitaiBaseChoice('SD 1.5 LCM', 'SD 1.5 LCM'),
    CivitaiBaseChoice('SD 1.5 Hyper', 'SD 1.5 Hyper'),
    CivitaiBaseChoice('SD 2.0', 'SD 2.0'),
    CivitaiBaseChoice('SD 2.0 768', 'SD 2.0 768'),
    CivitaiBaseChoice('SD 2.1', 'SD 2.1'),
    CivitaiBaseChoice('SD 2.1 768', 'SD 2.1 768'),
    CivitaiBaseChoice('SD 2.1 Unclip', 'SD 2.1 Unclip'),
  ]),
  CivitaiBaseGroup('Other image', [
    CivitaiBaseChoice('Anima', 'Anima'),
    CivitaiBaseChoice('AuraFlow', 'AuraFlow'),
    CivitaiBaseChoice('Chroma', 'Chroma'),
    CivitaiBaseChoice('ERNIE Image', 'Ernie'),
    CivitaiBaseChoice('HiDream', 'HiDream'),
    CivitaiBaseChoice('HiDream-O1', 'HiDream-O1'),
    CivitaiBaseChoice('Hunyuan Image', 'Hunyuan 1'),
    CivitaiBaseChoice('Ideogram 4.0', 'Ideogram 4.0'),
    CivitaiBaseChoice('Boogu', 'Boogu'),
    CivitaiBaseChoice('Imagen 4', 'Imagen4'),
    CivitaiBaseChoice('Kolors', 'Kolors'),
    CivitaiBaseChoice('Krea 2', 'Krea 2'),
    CivitaiBaseChoice('Lens', 'Lens'),
    CivitaiBaseChoice('Lumina', 'Lumina'),
    CivitaiBaseChoice('MageFlow', 'MageFlow'),
    CivitaiBaseChoice('MAI', 'MAI'),
    CivitaiBaseChoice('Nano Banana', 'Nano Banana'),
    CivitaiBaseChoice('ODOR', 'ODOR'),
    CivitaiBaseChoice('OpenAI', 'OpenAI'),
    CivitaiBaseChoice('PixArt α', 'PixArt a'),
    CivitaiBaseChoice('PixArt Σ', 'PixArt E'),
    CivitaiBaseChoice('Playground v2', 'Playground v2'),
    CivitaiBaseChoice('Stable Cascade', 'Stable Cascade'),
    CivitaiBaseChoice('Reve', 'Reve'),
    CivitaiBaseChoice('Muse Image', 'Muse Image'),
    CivitaiBaseChoice('Seedream', 'Seedream'),
    CivitaiBaseChoice('Wan Image 2.7', 'Wan Image 2.7'),
    CivitaiBaseChoice('Ming Image Design 0.1', 'Ming Image Design 0.1'),
    CivitaiBaseChoice(
      'Ming Image Design Layer 0.1',
      'Ming Image Design Layer 0.1',
    ),
    CivitaiBaseChoice('Grok', 'Grok'),
    CivitaiBaseChoice('HappyHorse', 'HappyHorse'),
  ]),
];

/// Every API string the picker can send. Empty means no base filter.
List<String> civitaiBaseApiValues() {
  return [
    for (final group in kCivitaiBaseGroups)
      for (final choice in group.choices)
        if (choice.several.isEmpty) choice.api,
  ];
}

/// The `baseModels` values for a picked base: a choice for several bases
/// sends each of them; anything else is sent as it is.
List<String> civitaiBaseSends(String picked) {
  final key = picked.trim();
  if (key.isEmpty) return const [];
  for (final group in kCivitaiBaseGroups) {
    for (final choice in group.choices) {
      if (choice.api == key) return choice.sends;
    }
  }
  return [key];
}

/// The picker label for [api], or [api] itself when no choice has it.
String civitaiBaseLabel(String api) {
  for (final group in kCivitaiBaseGroups) {
    for (final choice in group.choices) {
      if (choice.api == api) return choice.label;
    }
  }
  return api;
}

/// Whether [api] is in [groups] (a filtered list).
bool civitaiBaseShown(List<CivitaiBaseGroup> groups, String api) {
  for (final group in groups) {
    for (final choice in group.choices) {
      if (choice.api == api) return true;
    }
  }
  return false;
}

/// Bases whose label, API value, or group title contains [query].
/// [onlyApis] limits the list to bases for installed model files; a choice
/// for several bases stays while any of them is installed.
/// Null means every base. An empty set means none of them.
List<CivitaiBaseGroup> filterCivitaiBaseGroups(
  List<CivitaiBaseGroup> groups, {
  String query = '',
  Set<String>? onlyApis,
}) {
  final needle = query.trim().toLowerCase();
  final out = <CivitaiBaseGroup>[];
  for (final group in groups) {
    final title = group.title.toLowerCase();
    final choices = <CivitaiBaseChoice>[];
    for (final choice in group.choices) {
      if (onlyApis != null && !choice.sends.any(onlyApis.contains)) continue;
      if (needle.isEmpty ||
          title.contains(needle) ||
          choice.label.toLowerCase().contains(needle) ||
          choice.api.toLowerCase().contains(needle)) {
        choices.add(choice);
      }
    }
    if (choices.isNotEmpty) out.add(CivitaiBaseGroup(group.title, choices));
  }
  return out;
}

/// CivitAI base API values a weight file can run. Empty for encoders.
List<String> civitaiBasesForFilename(String name) {
  final leaf = name.replaceAll(r'\', '/');
  final cut = leaf.lastIndexOf('/');
  final s = (cut < 0 ? leaf : leaf.substring(cut + 1)).toLowerCase();
  if (s.isEmpty || _civitaiSupportName(s)) return const [];
  if (s.contains('kontext')) return const ['Flux.1 Kontext'];
  final flux = _civitaiFluxBase(s);
  if (flux != null) return flux;
  if (RegExp(r'krea[ ._-]?2').hasMatch(s)) return const ['Krea 2'];
  final qwen = _civitaiQwenBase(s);
  if (qwen != null) return qwen;
  if (RegExp(r'z[ _-]?image').hasMatch(s)) {
    if (s.contains('turbo')) return const ['ZImageTurbo'];
    if (s.contains('base')) return const ['ZImageBase'];
    return const ['ZImageTurbo', 'ZImageBase'];
  }
  final sd3 = _civitaiSd3Base(s);
  if (sd3 != null) return sd3;
  if (s.contains('pony')) {
    if (RegExp(r'pony[ _-]?v?7').hasMatch(s)) return const ['Pony V7'];
    return const ['Pony'];
  }
  if (s.contains('illustrious')) return const ['Illustrious'];
  if (s.contains('noobai') || s.contains('noob-ai') || s.contains('noob_ai')) {
    return const ['NoobAI'];
  }
  final sdxl = _civitaiSdxlBase(s);
  if (sdxl != null) return sdxl;
  final sd = _civitaiSdBase(s);
  if (sd != null) return sd;
  for (final row in _kLooseBases) {
    if (s.contains(row.$1)) return [row.$2];
  }
  return const [];
}

/// Union of [civitaiBasesForFilename] for every installed weight.
Set<String> civitaiBasesForFiles(Iterable<String> names) {
  return {for (final name in names) ...civitaiBasesForFilename(name)};
}

bool _civitaiSupportName(String s) {
  if (s.contains('mmproj') || s.contains('vae')) return true;
  if (s.contains('t5xxl') || s.contains('clip_l') || s.contains('clip-l')) {
    return true;
  }
  if (RegExp(r'qwen[ _.-]?3[ _.-]?4b').hasMatch(s)) return true;
  if (s.contains('qwen') &&
      s.contains('vl') &&
      !s.contains('qwen-image') &&
      !s.contains('qwen_image') &&
      !s.contains('qwenimage')) {
    return true;
  }
  return RegExp(r'(^|[^a-z])ae\.(safetensors|sft|pt)').hasMatch(s);
}

List<String>? _civitaiFluxBase(String s) {
  if (!s.contains('flux')) return null;
  final klein9 = s.contains('klein') && s.contains('9');
  final klein4 = s.contains('klein') && s.contains('4') && !klein9;
  if (klein9) {
    return [s.contains('base') ? 'Flux.2 Klein 9B-base' : 'Flux.2 Klein 9B'];
  }
  if (klein4) {
    return [s.contains('base') ? 'Flux.2 Klein 4B-base' : 'Flux.2 Klein 4B'];
  }
  if (RegExp(r'flux[ ._-]?2').hasMatch(s)) return const ['Flux.2 D'];
  if (s.contains('krea')) return const ['Flux.1 Krea'];
  if (s.contains('schnell')) return const ['Flux.1 S'];
  return const ['Flux.1 D'];
}

List<String>? _civitaiQwenBase(String s) {
  if (!s.contains('qwen')) return null;
  if (s.contains('2.1') || s.contains('2_1')) return const ['Qwen 2.1'];
  if (RegExp(r'qwen[ ._-]?3').hasMatch(s)) return const ['Qwen 3'];
  if (RegExp(r'qwen[ ._-]?2(?![.\d])').hasMatch(s)) return const ['Qwen 2'];
  return const ['Qwen'];
}

List<String>? _civitaiSd3Base(String s) {
  if (!RegExp(
    r'(^|[^a-z0-9])sd[ _-]?3($|[^0-9])|stable[ _-]?diffusion[ _-]?3',
  ).hasMatch(s)) {
    return null;
  }
  if (s.contains('3.5') || s.contains('3_5')) {
    final large = s.contains('large');
    if (large && s.contains('turbo')) return const ['SD 3.5 Large Turbo'];
    if (s.contains('medium')) return const ['SD 3.5 Medium'];
    if (large) return const ['SD 3.5 Large'];
    return const ['SD 3.5'];
  }
  return const ['SD 3'];
}

List<String>? _civitaiSdxlBase(String s) {
  final xl =
      s.contains('sdxl') ||
      s.contains('sd_xl') ||
      s.contains('sd-xl') ||
      RegExp(r'xl(?![a-z])').hasMatch(s);
  if (!xl) return null;
  if (s.contains('0.9')) return const ['SDXL 0.9'];
  if (s.contains('lcm')) return const ['SDXL 1.0 LCM'];
  if (s.contains('lightning')) return const ['SDXL Lightning'];
  if (s.contains('hyper')) return const ['SDXL Hyper'];
  if (s.contains('turbo')) return const ['SDXL Turbo'];
  if (s.contains('distill')) return const ['SDXL Distilled'];
  return const ['SDXL 1.0'];
}

List<String>? _civitaiSdBase(String s) {
  if (RegExp(r'sd[ _-]?1\.?4|(^|[^0-9])1\.4($|[^0-9])').hasMatch(s)) {
    return const ['SD 1.4'];
  }
  if (RegExp(r'sd[ _-]?1\.?5|v1-5|v1_5').hasMatch(s)) {
    if (s.contains('lcm')) return const ['SD 1.5 LCM'];
    if (s.contains('hyper')) return const ['SD 1.5 Hyper'];
    return const ['SD 1.5'];
  }
  if (RegExp(r'sd[ _-]?2\.?1').hasMatch(s)) {
    if (s.contains('unclip')) return const ['SD 2.1 Unclip'];
    if (s.contains('768')) return const ['SD 2.1 768'];
    return const ['SD 2.1'];
  }
  if (RegExp(r'sd[ _-]?2\.?0').hasMatch(s)) {
    if (s.contains('768')) return const ['SD 2.0 768'];
    return const ['SD 2.0'];
  }
  return null;
}

const List<(String, String)> _kLooseBases = [
  ('hidream-o1', 'HiDream-O1'),
  ('hidream_o1', 'HiDream-O1'),
  ('hidream', 'HiDream'),
  ('auraflow', 'AuraFlow'),
  ('chroma', 'Chroma'),
  ('ernie', 'Ernie'),
  ('hunyuan', 'Hunyuan 1'),
  ('ideogram', 'Ideogram 4.0'),
  ('boogu', 'Boogu'),
  ('imagen', 'Imagen4'),
  ('kolors', 'Kolors'),
  ('lumina', 'Lumina'),
  ('playground', 'Playground v2'),
  ('cascade', 'Stable Cascade'),
  ('seedream', 'Seedream'),
  ('happyhorse', 'HappyHorse'),
  ('anima', 'Anima'),
];
