// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage on the web (docs/design/ambient-stage.md). The desktop
// resolves the story's weather into scene tokens (SceneTokens.wireOf in
// lib/services/chat/scene/scene_tokens.dart) and sends them on the chat
// state as `scene`, once per brightness, because this page may run its own
// mode (theme/appTheme.ts); this file only picks the mode's washes and
// arranges those colour strings into the CSS the chat view paints. It never
// works out a colour, so the two sides cannot drift.

import type { ThemeMode } from './appTheme';

/** One brightness's washes. */
export interface SceneModeWire {
  /** Translucent CSS colours in paint order, bottom first. */
  layers: string[];
  haze: number;
  hazeCentre: string;
  hazeEdge: string;
}

export interface SceneWire {
  daypart: string;
  condition: string;
  temp: string;
  dark: SceneModeWire;
  light: SceneModeWire;
}

const CSS_COLOUR = /^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$/;

function parseMode(raw: unknown): SceneModeWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const m = raw as Partial<SceneModeWire>;
  if (!Array.isArray(m.layers) || !m.layers.every((l) => typeof l === 'string' && CSS_COLOUR.test(l))) {
    return null;
  }
  if (typeof m.haze !== 'number' || !Number.isFinite(m.haze)) return null;
  if (typeof m.hazeCentre !== 'string' || !CSS_COLOUR.test(m.hazeCentre)) return null;
  if (typeof m.hazeEdge !== 'string' || !CSS_COLOUR.test(m.hazeEdge)) return null;
  return { layers: [...m.layers], haze: m.haze, hazeCentre: m.hazeCentre, hazeEdge: m.hazeEdge };
}

/** A scene from the desktop, or null when the payload is not one. */
export function parseSceneWire(raw: unknown): SceneWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  if (typeof w.daypart !== 'string' || typeof w.condition !== 'string' || typeof w.temp !== 'string') {
    return null;
  }
  const dark = parseMode(w.dark);
  const light = parseMode(w.light);
  if (!dark || !light) return null;
  return { daypart: w.daypart, condition: w.condition, temp: w.temp, dark, light };
}

/**
 * The CSS custom properties for a scene on the chat view in [mode], the
 * brightness this page paints: one `--scene-layers` background-image list,
 * haze on top (CSS paints the first image on top, so the haze goes first
 * and the shade last), each wash a flat gradient of its colour. Nothing
 * when there is no scene to paint.
 */
export function sceneCssVars(scene: SceneWire | null, mode: ThemeMode): Record<string, string> {
  if (!scene) return {};
  const washes = scene[mode];
  const images: string[] = [];
  if (washes.haze > 0) {
    images.push(`radial-gradient(circle at center, ${washes.hazeCentre} 15%, ${washes.hazeEdge} 100%)`);
  }
  // CSS paints the first image on top, so reverse the desktop's bottom-first order.
  for (const layer of [...washes.layers].reverse()) {
    images.push(`linear-gradient(${layer}, ${layer})`);
  }
  if (images.length === 0) return {};
  return { '--scene-layers': images.join(', ') };
}
