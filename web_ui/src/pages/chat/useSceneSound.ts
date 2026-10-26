// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's scene sound (docs/design/ambient-stage.md §5): plays what
// the chat state's `scene` says (its condition, part of day and the
// desktop's Scene sound setting, which the state refetches on every
// settings_changed), ducks under a voice clip playing on this device, and
// answers the effects canvas's storm flashes with thunder. Stops on
// unmount and while the tab is hidden.

import { useCallback, useEffect, useRef } from 'react';
import { isVoicePlaying, onVoiceActivity } from '../../components/voiceActivity';
import type { Flash } from '../../theme/sceneEffects';
import { SceneSoundPlayer, parseSceneSound, sceneLoopFor, type SceneSoundOptions } from '../../theme/sceneSound';

export function useSceneSound(scene: unknown, opts?: SceneSoundOptions): { onFlash: (f: Flash) => void } {
  const parsed = parseSceneSound(scene);
  const loop = parsed?.on ? sceneLoopFor(parsed.condition, parsed.daypart) : null;
  const volume = parsed?.volume ?? 0.5;
  const storm = !!parsed?.on && parsed.condition === 'storm';
  const player = useRef<SceneSoundPlayer | null>(null);
  const options = useRef(opts);

  useEffect(() => {
    const p = new SceneSoundPlayer(options.current);
    player.current = p;
    p.setSpeaking(isVoicePlaying());
    const off = onVoiceActivity((speaking) => p.setSpeaking(speaking));
    return () => {
      off();
      p.dispose();
      player.current = null;
    };
  }, []);

  useEffect(() => {
    player.current?.update({ loop, volume, storm });
  }, [loop, volume, storm]);

  const onFlash = useCallback((f: Flash) => player.current?.flash(f), []);
  return { onFlash };
}
