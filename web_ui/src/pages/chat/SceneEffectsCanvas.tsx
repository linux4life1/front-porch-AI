// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage's moving weather (rain, snow, clouds, fog, the storm
// flash) as a canvas behind the chat column, the web twin of the desktop
// stage's effect components. Mounted only at Tint and effects; the tint
// itself stays the chat view's CSS layers (chat.css). The canvas never
// takes a tap: it sits after the veil and before every other child, which
// the chat view keeps positioned while it is up.

import { useEffect, useMemo, useRef } from 'react';
import {
  hasEffects, parseSceneEffects, type EffectPaints, type EffectSpec, type SceneEffectsWire,
} from '../../theme/sceneEffects';
import { SceneEffectsPlayer } from '../../theme/sceneEffectsPlayer';
import { usePaintedThemeMode } from '../../theme/usePaintedThemeMode';

export function SceneEffectsCanvas({ scene, generating }: { scene: unknown; generating: boolean }) {
  // The weather's colours for the mode this page paints, like the tint's.
  const mode = usePaintedThemeMode();
  const parsed = parseSceneEffects(scene, mode);
  const wire = hasEffects(parsed) ? parsed : null;
  // A new chat state is a new object every poll. The weather is scattered
  // afresh only when what it is scattered from (the seed and the spec)
  // changes; new colours (a mode switch) and the pause switch go to the
  // running player, so the rain does not jump.
  const scatterKey = wire ? JSON.stringify([wire.seed, specOf(wire.effects)]) : '';
  const paintsKey = wire ? JSON.stringify(wire.effects.paints) : '';
  const pauseWhileGenerating = wire ? wire.pauseWhileGenerating : true;
  const scatter = useMemo(
    () => (scatterKey ? (JSON.parse(scatterKey) as [number, EffectSpec]) : null),
    [scatterKey],
  );
  const paints = useMemo(() => (paintsKey ? (JSON.parse(paintsKey) as EffectPaints) : null), [paintsKey]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const playerRef = useRef<SceneEffectsPlayer | null>(null);
  // What a new player starts from; the effects below keep a running one current.
  const latest = useRef({ paints, pauseWhileGenerating, generating });
  useEffect(() => {
    latest.current = { paints, pauseWhileGenerating, generating };
  });

  useEffect(() => {
    const canvas = canvasRef.current;
    const look = latest.current;
    if (!scatter || !look.paints || !canvas) return;
    const view = canvas.parentElement;
    view?.classList.add('has-scene-effects');
    const [seed, spec] = scatter;
    const start: SceneEffectsWire = {
      level: 'effects',
      seed,
      pauseWhileGenerating: look.pauseWhileGenerating,
      effects: { ...spec, paints: look.paints },
    };
    const player = new SceneEffectsPlayer(canvas, start);
    player.setGenerating(look.generating);
    playerRef.current = player;
    const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(() => player.resize()) : null;
    observer?.observe(canvas);
    return () => {
      observer?.disconnect();
      player.dispose();
      playerRef.current = null;
      view?.classList.remove('has-scene-effects');
    };
  }, [scatter]);

  useEffect(() => {
    if (paints) playerRef.current?.setPaints(paints);
  }, [paints]);

  useEffect(() => {
    playerRef.current?.setPauseWhileGenerating(pauseWhileGenerating);
  }, [pauseWhileGenerating]);

  useEffect(() => {
    playerRef.current?.setGenerating(generating);
  }, [generating]);

  if (!scatter) return null;
  return <canvas ref={canvasRef} className="scene-effects" aria-hidden="true" data-testid="scene-effects" />;
}

/** What the weather is scattered from, without its colours. */
function specOf(e: SceneEffectsWire['effects']): EffectSpec {
  return { kind: e.kind, density: e.density, clouds: e.clouds, fog: e.fog, lightning: e.lightning, wind: e.wind };
}
