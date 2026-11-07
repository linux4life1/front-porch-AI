// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story-clock sky behind the chat column, the web twin of the desktop
// stage's sky and disc layers: one player drawing two canvases, the sky
// under the moving weather and the sun and moon over it. useSceneSky owns
// the player for the chat page; each SceneSkyCanvas hands it one canvas.
// Mounted whenever the scene carries a sky (Tint only paints it still);
// the canvases never take a tap, like the weather's.

import { useCallback, useEffect, useRef, useState } from 'react';
import { parseSceneSky } from '../../theme/sceneSky';
import { SceneSkyPlayer, type SkyLayer } from '../../theme/sceneSkyPlayer';
import { usePaintedThemeMode } from '../../theme/usePaintedThemeMode';

/** The sky player for the chat page's scene, or null without a sky. */
export function useSceneSky(scene: unknown, generating: boolean): SceneSkyPlayer | null {
  const mode = usePaintedThemeMode();
  const wire = parseSceneSky(scene, mode);
  // A new chat state is a new object every poll; the player hears only a
  // real change of sky.
  const key = wire ? JSON.stringify(wire) : '';
  const playerRef = useRef<SceneSkyPlayer | null>(null);
  const [player, setPlayer] = useState<SceneSkyPlayer | null>(null);

  useEffect(() => {
    if (!key) {
      playerRef.current?.dispose();
      playerRef.current = null;
      setPlayer(null);
      return;
    }
    const next = JSON.parse(key) as NonNullable<typeof wire>;
    if (playerRef.current) {
      playerRef.current.setScene(next);
    } else {
      const p = new SceneSkyPlayer(next);
      playerRef.current = p;
      setPlayer(p);
    }
  }, [key]);

  useEffect(() => {
    player?.setGenerating(generating);
  }, [player, generating]);

  useEffect(() => () => {
    playerRef.current?.dispose();
    playerRef.current = null;
  }, []);

  return player;
}

export function SceneSkyCanvas({ player, layer }: { player: SceneSkyPlayer | null; layer: SkyLayer }) {
  const className = layer === 'under' ? 'scene-sky' : 'scene-sky-discs';
  const viewRef = useRef<HTMLElement | null>(null);
  // A callback ref: React hands over the canvas on mount and null on
  // unmount, so the player always holds a live canvas or none. The chat
  // view keeps its other children positioned while a sky is up.
  const ref = useCallback((canvas: HTMLCanvasElement | null) => {
    if (canvas) {
      viewRef.current = canvas.parentElement;
      viewRef.current?.classList.add('has-scene-sky');
    } else {
      viewRef.current?.classList.remove('has-scene-sky');
      viewRef.current = null;
    }
    player?.attach(layer, canvas);
  }, [player, layer]);
  if (!player) return null;
  return <canvas ref={ref} className={className} aria-hidden="true" data-testid={className} />;
}
