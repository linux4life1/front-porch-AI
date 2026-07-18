// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Read to me" for the web book reader. The host synthesizes each scene's prose
// (per-character voices, stitched WAV) via /api/stories/<id>/narrate; this plays
// them in order, prefetches the next scene while one plays, and jumps the book to
// each scene as it begins. Scene-granular sync — the desktop's page-granular
// read-along isn't feasible in the browser, so we follow along by scene.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';

export interface NarrationScene {
  ai: number;
  si: number;
}

export function useSceneNarration(
  id: string,
  scenes: NarrationScene[],
  onJump: (ai: number, si: number) => void,
) {
  const [reading, setReading] = useState(false);
  const [current, setCurrent] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const readingRef = useRef(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const cache = useRef<Map<number, string>>(new Map());

  const fetchScene = useCallback(async (idx: number): Promise<string | null> => {
    if (idx < 0 || idx >= scenes.length) return null;
    const hit = cache.current.get(idx);
    if (hit) return hit;
    const sc = scenes[idx];
    const blob = await api.postForBlob(`/api/stories/${id}/narrate`, {
      actIndex: sc.ai,
      sceneIndex: sc.si,
    });
    const url = URL.createObjectURL(blob);
    cache.current.set(idx, url);
    return url;
  }, [id, scenes]);

  const clearCache = useCallback(() => {
    cache.current.forEach((u) => URL.revokeObjectURL(u));
    cache.current.clear();
  }, []);

  const stop = useCallback(() => {
    readingRef.current = false;
    setReading(false);
    setBuffering(false);
    const a = audioRef.current;
    if (a) { a.pause(); audioRef.current = null; }
    clearCache();
  }, [clearCache]);

  const start = useCallback(async (from = 0) => {
    if (readingRef.current || scenes.length === 0) return;
    readingRef.current = true;
    setReading(true);
    let idx = Math.max(0, Math.min(from, scenes.length - 1));

    while (readingRef.current && idx < scenes.length) {
      setCurrent(idx);
      onJump(scenes[idx].ai, scenes[idx].si);

      let url: string | null = null;
      setBuffering(true);
      try { url = await fetchScene(idx); } catch { url = null; }
      setBuffering(false);
      if (!readingRef.current) break;

      // Prefetch the next scene while this one plays.
      void fetchScene(idx + 1).catch(() => {});

      if (url) {
        await new Promise<void>((resolve) => {
          const audio = new Audio(url as string);
          audioRef.current = audio;
          audio.onended = () => resolve();
          audio.onerror = () => resolve();
          audio.play().catch(() => resolve());
        });
      }
      if (!readingRef.current) break;

      // Free the played scene (keep the prefetched next one).
      const played = cache.current.get(idx);
      if (played) { URL.revokeObjectURL(played); cache.current.delete(idx); }
      idx++;
    }

    readingRef.current = false;
    setReading(false);
  }, [scenes, fetchScene, onJump]);

  // Clean up on unmount.
  useEffect(() => () => {
    readingRef.current = false;
    audioRef.current?.pause();
    clearCache();
  }, [clearCache]);

  return { reading, current, buffering, total: scenes.length, start, stop };
}
