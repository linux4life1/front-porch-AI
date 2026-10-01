// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/** One base. `several` are the bases a choice for several sends. */
export interface CivitaiBaseChoice {
  label: string;
  api: string;
  several?: string[];
}

export interface CivitaiBaseGroup {
  title: string;
  choices: CivitaiBaseChoice[];
}

/** Still-image bases. `api` is CivitAI's BaseModel enum string, or the
 *  picker's own key for a choice that stands for several. No video. Same list
 *  as Dart `kCivitaiBaseGroups`. */
export const civitaiBaseGroups: CivitaiBaseGroup[] = [
  {
    title: 'Flux',
    choices: [
      { label: 'Flux.1 Schnell', api: 'Flux.1 S' },
      { label: 'Flux.1 Dev', api: 'Flux.1 D' },
      { label: 'Flux.1 Krea', api: 'Flux.1 Krea' },
      { label: 'Flux.1 Kontext', api: 'Flux.1 Kontext' },
      { label: 'Flux.2 Dev', api: 'Flux.2 D' },
      {
        label: 'Flux.2 Klein (all)',
        api: 'Flux.2 Klein (all)',
        several: ['Flux.2 Klein 9B', 'Flux.2 Klein 9B-base', 'Flux.2 Klein 4B', 'Flux.2 Klein 4B-base'],
      },
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

/** What a choice sends as `baseModels`. */
export const civitaiBaseSends = (choice: CivitaiBaseChoice): string[] =>
  choice.several && choice.several.length > 0 ? choice.several : [choice.api];

/** Same rule as Dart `filterCivitaiBaseGroups`. Null [onlyApis] keeps every
 *  base; a choice for several stays while any of them is installed. */
export function filterCivitaiBases(
  groups: CivitaiBaseGroup[],
  query: string,
  onlyApis: string[] | null,
): CivitaiBaseGroup[] {
  const needle = query.trim().toLowerCase();
  const only = onlyApis == null ? null : new Set(onlyApis);
  const out: CivitaiBaseGroup[] = [];
  for (const group of groups) {
    const title = group.title.toLowerCase();
    const choices = group.choices.filter((choice) => {
      if (only && !civitaiBaseSends(choice).some((api) => only.has(api))) return false;
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

/** Whether [api] is in [groups] (a filtered list). */
export const civitaiBaseShown = (groups: CivitaiBaseGroup[], api: string): boolean =>
  groups.some((group) => group.choices.some((choice) => choice.api === api));

/** The picker label for [api], or [api] itself. */
export function civitaiBaseLabel(api: string): string {
  for (const group of civitaiBaseGroups) {
    for (const choice of group.choices) if (choice.api === api) return choice.label;
  }
  return api;
}
