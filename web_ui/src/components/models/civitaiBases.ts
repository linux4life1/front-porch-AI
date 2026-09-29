// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/** Still-image bases. `api` is CivitAI's BaseModel enum string. No video. */
export const civitaiBaseGroups: { title: string; choices: { label: string; api: string }[] }[] = [
  {
    title: 'Flux',
    choices: [
      { label: 'Flux.1 Schnell', api: 'Flux.1 S' },
      { label: 'Flux.1 Dev', api: 'Flux.1 D' },
      { label: 'Flux.1 Krea', api: 'Flux.1 Krea' },
      { label: 'Flux.1 Kontext', api: 'Flux.1 Kontext' },
      { label: 'Flux.2 Dev', api: 'Flux.2 D' },
      { label: 'Flux.2 Klein 9B', api: 'Flux.2 Klein 9B' },
      { label: 'Flux.2 Klein 9B base', api: 'Flux.2 Klein 9B-base' },
      { label: 'Flux.2 Klein 4B', api: 'Flux.2 Klein 4B' },
      { label: 'Flux.2 Klein 4B base', api: 'Flux.2 Klein 4B-base' },
    ],
  },
  {
    title: 'Qwen',
    choices: [
      { label: 'Qwen-Image, 2512, and Image Edit', api: 'Qwen' },
      { label: 'Qwen 2', api: 'Qwen 2' },
      { label: 'Qwen 2.1', api: 'Qwen 2.1' },
      { label: 'Qwen 3', api: 'Qwen 3' },
    ],
  },
  {
    title: 'Z-Image',
    choices: [
      { label: 'Z-Image Turbo', api: 'ZImageTurbo' },
      { label: 'Z-Image', api: 'ZImageBase' },
    ],
  },
  {
    title: 'SD 3',
    choices: [
      { label: 'SD 3', api: 'SD 3' },
      { label: 'SD 3.5', api: 'SD 3.5' },
      { label: 'SD 3.5 Medium', api: 'SD 3.5 Medium' },
      { label: 'SD 3.5 Large', api: 'SD 3.5 Large' },
      { label: 'SD 3.5 Large Turbo', api: 'SD 3.5 Large Turbo' },
    ],
  },
  {
    title: 'SDXL, Pony, Illustrious',
    choices: [
      { label: 'SDXL 0.9', api: 'SDXL 0.9' },
      { label: 'SDXL 1.0', api: 'SDXL 1.0' },
      { label: 'SDXL 1.0 LCM', api: 'SDXL 1.0 LCM' },
      { label: 'SDXL Lightning', api: 'SDXL Lightning' },
      { label: 'SDXL Hyper', api: 'SDXL Hyper' },
      { label: 'SDXL Turbo', api: 'SDXL Turbo' },
      { label: 'SDXL Distilled', api: 'SDXL Distilled' },
      { label: 'Pony', api: 'Pony' },
      { label: 'Pony V7', api: 'Pony V7' },
      { label: 'Illustrious', api: 'Illustrious' },
      { label: 'NoobAI', api: 'NoobAI' },
    ],
  },
  {
    title: 'SD 1 and SD 2',
    choices: [
      { label: 'SD 1.4', api: 'SD 1.4' },
      { label: 'SD 1.5', api: 'SD 1.5' },
      { label: 'SD 1.5 LCM', api: 'SD 1.5 LCM' },
      { label: 'SD 1.5 Hyper', api: 'SD 1.5 Hyper' },
      { label: 'SD 2.0', api: 'SD 2.0' },
      { label: 'SD 2.0 768', api: 'SD 2.0 768' },
      { label: 'SD 2.1', api: 'SD 2.1' },
      { label: 'SD 2.1 768', api: 'SD 2.1 768' },
      { label: 'SD 2.1 Unclip', api: 'SD 2.1 Unclip' },
    ],
  },
  {
    title: 'Other image',
    choices: [
      { label: 'Anima', api: 'Anima' },
      { label: 'AuraFlow', api: 'AuraFlow' },
      { label: 'Chroma', api: 'Chroma' },
      { label: 'ERNIE Image', api: 'Ernie' },
      { label: 'HiDream', api: 'HiDream' },
      { label: 'HiDream-O1', api: 'HiDream-O1' },
      { label: 'Hunyuan Image', api: 'Hunyuan 1' },
      { label: 'Ideogram 4.0', api: 'Ideogram 4.0' },
      { label: 'Boogu', api: 'Boogu' },
      { label: 'Imagen 4', api: 'Imagen4' },
      { label: 'Kolors', api: 'Kolors' },
      { label: 'Krea 2', api: 'Krea 2' },
      { label: 'Lens', api: 'Lens' },
      { label: 'Lumina', api: 'Lumina' },
      { label: 'MageFlow', api: 'MageFlow' },
      { label: 'MAI', api: 'MAI' },
      { label: 'Nano Banana', api: 'Nano Banana' },
      { label: 'ODOR', api: 'ODOR' },
      { label: 'OpenAI', api: 'OpenAI' },
      { label: 'PixArt α', api: 'PixArt a' },
      { label: 'PixArt Σ', api: 'PixArt E' },
      { label: 'Playground v2', api: 'Playground v2' },
      { label: 'Stable Cascade', api: 'Stable Cascade' },
      { label: 'Reve', api: 'Reve' },
      { label: 'Muse Image', api: 'Muse Image' },
      { label: 'Seedream', api: 'Seedream' },
      { label: 'Wan Image 2.7', api: 'Wan Image 2.7' },
      { label: 'Ming Image Design 0.1', api: 'Ming Image Design 0.1' },
      { label: 'Ming Image Design Layer 0.1', api: 'Ming Image Design Layer 0.1' },
      { label: 'Grok', api: 'Grok' },
      { label: 'HappyHorse', api: 'HappyHorse' },
    ],
  },
];

/** Same rule as Dart `filterCivitaiBaseGroups`. Null [onlyApis] keeps every base. */
export function filterCivitaiBases(
  groups: { title: string; choices: { label: string; api: string }[] }[],
  query: string,
  onlyApis: string[] | null,
): { title: string; choices: { label: string; api: string }[] }[] {
  const needle = query.trim().toLowerCase();
  const only = onlyApis == null ? null : new Set(onlyApis);
  const out: { title: string; choices: { label: string; api: string }[] }[] = [];
  for (const group of groups) {
    const title = group.title.toLowerCase();
    const choices = group.choices.filter((choice) => {
      if (only && !only.has(choice.api)) return false;
      if (!needle) return true;
      return (
        title.includes(needle) ||
        choice.label.toLowerCase().includes(needle) ||
        choice.api.toLowerCase().includes(needle)
      );
    });
    if (choices.length > 0) out.push({ title: group.title, choices });
  }
  return out;
}

/** The selected base, or empty when the filter hid it. */
export function visibleCivitaiBase(
  current: string,
  groups: { choices: { api: string }[] }[],
): string {
  const apis = new Set(groups.flatMap((group) => group.choices.map((choice) => choice.api)));
  return current !== '' && apis.has(current) ? current : '';
}
