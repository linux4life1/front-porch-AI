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
import { hasEffects, parseSceneEffects, type SceneEffectsWire } from '../../theme/sceneEffects';
import { SceneEffectsPlayer } from '../../theme/sceneEffectsPlayer';

export function SceneEffectsCanvas({ scene, generating }: { scene: unknown; generating: boolean }) {
  const parsed = parseSceneEffects(scene);
  const wire = hasEffects(parsed) ? parsed : null;
  // A new chat state is a new object every poll; the weather is rebuilt
  // only when what it is scattered from changes.
  const key = wire ? JSON.stringify(wire) : '';
  const stable = useMemo(() => (key ? (JSON.parse(key) as SceneEffectsWire) : null), [key]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const playerRef = useRef<SceneEffectsPlayer | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!stable || !canvas) return;
    const view = canvas.parentElement;
    view?.classList.add('has-scene-effects');
    const player = new SceneEffectsPlayer(canvas, stable);
    playerRef.current = player;
    const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(() => player.resize()) : null;
    observer?.observe(canvas);
    return () => {
      observer?.disconnect();
      player.dispose();
      playerRef.current = null;
      view?.classList.remove('has-scene-effects');
    };
  }, [stable]);

  // Declared after the effect above, so a new scene's player hears the
  // current generating state as soon as it exists.
  useEffect(() => {
    playerRef.current?.setGenerating(generating);
  }, [generating, stable]);

  if (!stable) return null;
  return <canvas ref={canvasRef} className="scene-effects" aria-hidden="true" data-testid="scene-effects" />;
}
