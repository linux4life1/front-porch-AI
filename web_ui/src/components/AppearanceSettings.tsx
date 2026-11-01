// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Appearance. The desktop's Dark Mode switch (it sits
// right under Follow streaming replies there too), and this device's own
// choice: follow the desktop, or keep dark, light or the browser's setting
// here. Both palettes come from the desktop; this card only picks one.

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import {
  THEME_EVENT, type ThemeChoice, currentThemeWire, loadThemeChoice, saveThemeChoice,
} from '../theme/appTheme';

type AmbientScene = 'off' | 'tint' | 'effects';
const AMBIENT: { value: AmbientScene; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'tint', label: 'Tint only' },
  { value: 'effects', label: 'Tint and effects' },
];
const asScene = (v: unknown): AmbientScene => (v === 'tint' || v === 'effects' ? v : 'off');
/** Writes the scene sound volume; on unmount nobody is left to show a failure, so it is logged. */
const postVolume = (value: number) =>
  api.post('/api/settings', { sceneSoundVolume: value }).catch((e: unknown) => {
    console.warn('Could not change the scene sound volume', e);
    throw e;
  });
const asVolume = (v: unknown): number =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.5;

type MoodLevel = 'off' | 'portrait' | 'all';
const MOOD: { value: MoodLevel; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'portrait', label: 'Portrait and needs' },
  { value: 'all', label: 'Portrait, needs and bubbles' },
];
const asMood = (v: unknown): MoodLevel => (v === 'portrait' || v === 'all' ? v : 'off');
// The Drama slider's range, the desktop's own (kMoodDramaMin..Max).
const asDrama = (v: unknown): number =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(1.6, Math.max(0.4, v)) : 1;
/** Writes the Drama; on unmount nobody is left to show a failure, so it is logged. */
const postDrama = (value: number) =>
  api.post('/api/settings', { moodDrama: value }).catch((e: unknown) => {
    console.warn('Could not change the mood drama', e);
    throw e;
  });

const CHOICES: { value: ThemeChoice; label: string }[] = [
  { value: 'desktop', label: 'Follow the desktop' },
  { value: 'dark', label: 'Dark' },
  { value: 'light', label: 'Light' },
  { value: 'system', label: 'Match this device' },
];

export function AppearanceSettings() {
  const [choice, setChoice] = useState<ThemeChoice>(loadThemeChoice);
  // Null until the desktop has said which mode it is in.
  const [desktopDark, setDesktopDark] = useState<boolean | null>(() => {
    const mode = currentThemeWire()?.mode;
    return mode ? mode === 'dark' : null;
  });
  const [error, setError] = useState('');
  // Appearance → Ambient scene, the desktop's own setting (null until read).
  const [ambient, setAmbient] = useState<AmbientScene | null>(null);
  // Appearance → Pause effects while generating (null until read).
  const [pauseGen, setPauseGen] = useState<boolean | null>(null);
  // Appearance → Scene sound and its volume, 0 to 1 (null until read).
  const [sound, setSound] = useState<boolean | null>(null);
  const [volume, setVolume] = useState<number | null>(null);
  // Appearance → Mood on the character and its Drama (null until read).
  const [mood, setMood] = useState<MoodLevel | null>(null);
  const [drama, setDrama] = useState<number | null>(null);
  // Porch Life's Story Weather and Realism Engine: with either off its
  // section is not shown here, as on the desktop (missing reads as on).
  const [weatherOn, setWeatherOn] = useState(true);
  const [realismAllowed, setRealismAllowed] = useState(true);
  // A drag of the volume posts once it settles, not on every step; a
  // value still waiting when the card closes is posted then.
  const volumePost = useRef<{ timer: ReturnType<typeof setTimeout>; value: number } | null>(null);
  const dramaPost = useRef<{ timer: ReturnType<typeof setTimeout>; value: number } | null>(null);

  // Live: the server broadcasts `settings_changed` whenever a setting is
  // written (on the desktop or another browser), so the control re-reads on
  // it and on a reconnect instead of keeping its first read.
  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{
          ambientScene?: unknown; pauseEffectsWhileGenerating?: unknown; sceneSound?: unknown; sceneSoundVolume?: unknown;
          moodOnCharacter?: unknown; moodDrama?: unknown;
          realism?: { weatherEnabled?: unknown; realismAllowed?: unknown };
        }>('/api/settings')
        .then((s) => {
          if (!alive) return;
          setAmbient(asScene(s.ambientScene));
          setPauseGen(s.pauseEffectsWhileGenerating !== false);
          setSound(s.sceneSound === true);
          setVolume(asVolume(s.sceneSoundVolume));
          setMood(asMood(s.moodOnCharacter));
          setDrama(asDrama(s.moodDrama));
          setWeatherOn(s.realism?.weatherEnabled !== false);
          setRealismAllowed(s.realism?.realismAllowed !== false);
        })
        .catch((e: unknown) => console.warn('Could not read the ambient scene setting', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
      const pending = volumePost.current;
      if (pending) {
        clearTimeout(pending.timer);
        volumePost.current = null;
        // Already logged by postVolume; nobody is left to show it.
        postVolume(pending.value).catch(() => undefined);
      }
      const pendingDrama = dramaPost.current;
      if (pendingDrama) {
        clearTimeout(pendingDrama.timer);
        dramaPost.current = null;
        postDrama(pendingDrama.value).catch(() => undefined);
      }
    };
  }, []);

  const setMoodLevel = (next: MoodLevel) => {
    const before = mood;
    setMood(next);
    setError('');
    api.post('/api/settings', { moodOnCharacter: next }).catch((e: unknown) => {
      setMood(before);
      setError(`Could not change Mood on the character: ${String(e)}`);
    });
  };

  const changeDrama = (next: number) => {
    setDrama(next);
    setError('');
    if (dramaPost.current) clearTimeout(dramaPost.current.timer);
    dramaPost.current = {
      value: next,
      timer: setTimeout(() => {
        dramaPost.current = null;
        postDrama(next).catch((e: unknown) => {
          setError(`Could not change the mood drama: ${String(e)}`);
        });
      }, 250),
    };
  };

  const setScene = (next: AmbientScene) => {
    const before = ambient;
    setAmbient(next);
    setError('');
    api.post('/api/settings', { ambientScene: next }).catch((e: unknown) => {
      setAmbient(before);
      setError(`Could not change the ambient scene: ${String(e)}`);
    });
  };

  const setPause = (next: boolean) => {
    const before = pauseGen;
    setPauseGen(next);
    setError('');
    api.post('/api/settings', { pauseEffectsWhileGenerating: next }).catch((e: unknown) => {
      setPauseGen(before);
      setError(`Could not change the effects pause: ${String(e)}`);
    });
  };

  const setSoundOn = (next: boolean) => {
    const before = sound;
    setSound(next);
    setError('');
    api.post('/api/settings', { sceneSound: next }).catch((e: unknown) => {
      setSound(before);
      setError(`Could not change the scene sound: ${String(e)}`);
    });
  };

  const changeVolume = (next: number) => {
    setVolume(next);
    setError('');
    if (volumePost.current) clearTimeout(volumePost.current.timer);
    volumePost.current = {
      value: next,
      timer: setTimeout(() => {
        volumePost.current = null;
        postVolume(next).catch((e: unknown) => {
          setError(`Could not change the scene sound volume: ${String(e)}`);
        });
      }, 250),
    };
  };

  useEffect(() => {
    const onWire = () => {
      const mode = currentThemeWire()?.mode;
      if (mode) setDesktopDark(mode === 'dark');
    };
    window.addEventListener(THEME_EVENT, onWire);
    // A wire that landed between the first render and this subscription
    // fired no event this card heard.
    onWire();
    return () => window.removeEventListener(THEME_EVENT, onWire);
  }, []);

  const pick = (next: ThemeChoice) => {
    setChoice(next);
    saveThemeChoice(next);
  };

  const setDark = (dark: boolean) => {
    setDesktopDark(dark);
    setError('');
    api.post('/api/settings', { darkMode: dark }).catch((e: unknown) => {
      setDesktopDark(!dark);
      setError(`Could not change the desktop's mode: ${String(e)}`);
    });
  };

  return (
    <section className="card" data-testid="appearance-card">
      <h3>Appearance</h3>
      <label>
        <input
          type="checkbox"
          checked={desktopDark ?? true}
          disabled={desktopDark === null}
          onChange={(e) => setDark(e.target.checked)}
          aria-label="Dark mode"
        />
        {' '}Dark mode
      </label>
      <p className="reading-blurb">The desktop app's own switch. Changing it here changes it there too.</p>
      {error && <p className="error">{error}</p>}
      <label>
        On this device
        <select
          value={choice}
          onChange={(e) => pick(e.target.value as ThemeChoice)}
          aria-label="Theme on this device"
        >
          {CHOICES.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
      {weatherOn && (
      <div className="settings-subgroup" data-testid="background-weather">
      <h4 className="subgroup-head">
        Background weather
        <span
          className="info-tip"
          tabIndex={0}
          title="The story's weather and sky behind the chat. It shows only in chats whose character or group has a world with climate turned on and the story clock running; other chats keep their plain background."
          aria-label="About background weather"
        >ⓘ</span>
      </h4>
      <p className="reading-blurb">Only in chats with a world that has climate on. Other chats keep their plain background.</p>
      <label>
        Ambient scene
        <select
          value={ambient ?? 'off'}
          disabled={ambient === null}
          onChange={(e) => setScene(e.target.value as AmbientScene)}
          aria-label="Ambient scene"
        >
          {AMBIENT.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
      <label>
        <input
          type="checkbox"
          checked={pauseGen ?? true}
          disabled={pauseGen === null}
          onChange={(e) => setPause(e.target.checked)}
          aria-label="Pause effects while generating"
        />
        {' '}Pause effects while generating
      </label>
      <label>
        <input
          type="checkbox"
          checked={sound ?? false}
          disabled={sound === null}
          onChange={(e) => setSoundOn(e.target.checked)}
          aria-label="Scene sound"
        />
        {' '}Scene sound
      </label>
      <label>
        Scene sound volume
        <input
          type="range"
          min={0}
          max={100}
          step={5}
          value={Math.round((volume ?? 0.5) * 100)}
          disabled={!sound || volume === null}
          onChange={(e) => changeVolume(Number(e.target.value) / 100)}
          aria-label="Scene sound volume"
        />
      </label>
      <p className="reading-blurb">The story's weather as a wash over the chat background, in a world with climate on; Tint and effects adds rain, snow, clouds, fog and lightning, held still while a reply is written if you like, so a local model keeps the graphics card. The High Contrast theme stays at the wash. The desktop's settings; changing them here changes them there too.</p>
      <p className="reading-blurb">Scene sound plays rain, wind, birds or crickets with the scene and thunder after a storm's flash, quieter while a voice speaks. Browsers start sound only once you have touched the page, so a tap in the chat may be needed.</p>
      </div>
      )}
      {realismAllowed && (
      <div className="settings-subgroup" data-testid="mood-on-character">
      <h4 className="subgroup-head">Chat appearance</h4>
      <label>
        Mood on the character
        <select
          value={mood ?? 'off'}
          disabled={mood === null}
          onChange={(e) => setMoodLevel(e.target.value as MoodLevel)}
          aria-label="Mood on the character"
        >
          {MOOD.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
      <label>
        Drama
        <input
          type="range"
          min={40}
          max={160}
          step={10}
          value={Math.round((drama ?? 1) * 100)}
          disabled={mood === null || mood === 'off' || drama === null}
          onChange={(e) => changeDrama(Number(e.target.value) / 100)}
          aria-label="Drama"
        />
      </label>
      <p className="reading-blurb">Each character's mood on their portrait and needs bars, in their own Realism colours. Needs Realism on for the chat. The desktop's settings; changing them here changes them there too.</p>
      </div>
      )}
    </section>
  );
}
