// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage on the web (docs/design/ambient-stage.md). The desktop
// resolves the story's weather into scene tokens (SceneTokens.toWire in
// lib/services/chat/scene/scene_tokens.dart) and sends them on the chat
// state as `scene`; this file only arranges those colour strings into the
// CSS the chat view paints. It never works out a colour, so the two sides
// cannot drift.

export interface SceneWire {
  daypart: string;
  condition: string;
  temp: string;
  /** Translucent CSS colours in paint order, bottom first. */
  layers: string[];
  haze: number;
  hazeCentre: string;
  hazeEdge: string;
}

const CSS_COLOUR = /^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$/;

/** A scene from the desktop, or null when the payload is not one. */
export function parseSceneWire(raw: unknown): SceneWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Partial<SceneWire>;
  if (typeof w.daypart !== 'string' || typeof w.condition !== 'string' || typeof w.temp !== 'string') {
    return null;
  }
  if (!Array.isArray(w.layers) || !w.layers.every((l) => typeof l === 'string' && CSS_COLOUR.test(l))) {
    return null;
  }
  if (typeof w.haze !== 'number' || !Number.isFinite(w.haze)) return null;
  if (typeof w.hazeCentre !== 'string' || !CSS_COLOUR.test(w.hazeCentre)) return null;
  if (typeof w.hazeEdge !== 'string' || !CSS_COLOUR.test(w.hazeEdge)) return null;
  return {
    daypart: w.daypart,
    condition: w.condition,
    temp: w.temp,
    layers: [...w.layers],
    haze: w.haze,
    hazeCentre: w.hazeCentre,
    hazeEdge: w.hazeEdge,
  };
}

/**
 * The CSS custom properties for a scene on the chat view: one
 * `--scene-layers` background-image list, haze on top (last in the list
 * paints first, so the haze goes first and the shade last), each wash a
 * flat gradient of its colour. Nothing when there is no scene to paint.
 */
export function sceneCssVars(scene: SceneWire | null): Record<string, string> {
  if (!scene) return {};
  const images: string[] = [];
  if (scene.haze > 0) {
    images.push(`radial-gradient(circle at center, ${scene.hazeCentre} 15%, ${scene.hazeEdge} 100%)`);
  }
  // CSS paints the first image on top, so reverse the desktop's bottom-first order.
  for (const layer of [...scene.layers].reverse()) {
    images.push(`linear-gradient(${layer}, ${layer})`);
  }
  if (images.length === 0) return {};
  return { '--scene-layers': images.join(', ') };
}
