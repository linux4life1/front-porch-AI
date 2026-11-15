// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Realism step on the web — the desktop's RealismStep
// (lib/ui/character_creator/steps/realism_step.dart): "Porch Life", its
// paragraph, then the shared Realism form with the Needs editor inside, on
// the character the creator already saved. It saves as you go, as the
// Greetings step does: a change is written once typing pauses, and only the
// Realism values are sent, so the greetings and profile stay as saved. The
// engine switch shows the card's own value; the creator saved the card with
// it where Porch Life has the engine (`realismDefault`, ruling 2026-10-14).
// The intimate rows show only with 18+ themes on. When the first message
// changed since the outfit was read, the outfit hint sits above Pockets &
// Wardrobe with Re-read and Keep (#370); the re-read holds the wizard.

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { NeedsFormSection } from '../realism/NeedsFormSection';
import { RealismFormSection } from '../realism/RealismFormSection';
import { type RealismValues } from '../realism/realismTypes';
import { useAdultFlags } from '../realism/useAdultThemes';
import { usePassageOfTime } from '../realism/usePassageOfTime';
import { OutfitHint } from './OutfitHint';
import {
  keepOutfit,
  loadRealism,
  outfitStatus,
  rereadOutfit,
  saveRealism,
  type OutfitStatus,
} from './realismStepApi';

export type RealismStepHandle = { flush: () => Promise<void> };

const SAVE_PAUSE_MS = 700;

export const RealismStep = forwardRef<
  RealismStepHandle,
  {
    characterId: string;
    /** True while a change waits to be saved or is saving: the wizard's
     *  Back and the last button wait for it. */
    onWritingChange?: (writing: boolean) => void;
  }
>(function RealismStep({ characterId: id, onWritingChange }, ref) {
  const [v, setV] = useState<RealismValues | null>(null);
  const [loadError, setLoadError] = useState('');
  const [saveError, setSaveError] = useState('');
  const [saving, setSaving] = useState(false);
  const [outfit, setOutfit] = useState<OutfitStatus | null>(null);
  const { adult, afterglow, planner } = useAdultFlags();
  const clockOn = usePassageOfTime();

  const vRef = useRef<RealismValues | null>(null);
  vRef.current = v;
  const dirty = useRef(false);
  const timer = useRef<number | undefined>(undefined);
  const inFlight = useRef<Promise<void> | null>(null);

  useEffect(() => {
    let alive = true;
    setV(null);
    setLoadError('');
    loadRealism(id)
      .then((r) => alive && setV(r))
      .catch((err) => {
        console.warn('[creator] the Realism values could not be loaded', err);
        if (alive) setLoadError('This character could not be loaded. Open it from the library instead.');
      });
    outfitStatus(id)
      .then((o) => alive && setOutfit(o))
      .catch((err) => console.warn('[creator] could not ask whether the first message changed', err));
    // One socket for the step: the re-read's end.
    const socket = new ChatSocket((e) => {
      if (e.characterId !== undefined && String(e.characterId) !== id) return;
      if (e.event === 'chargen_outfit_done') {
        // Only the outfit came back; what is being typed stays.
        loadRealism(id)
          .then((fresh) => {
            if (!alive) return;
            const cur = vRef.current;
            const next = cur ? { ...cur, inventory: fresh.inventory } : fresh;
            vRef.current = next;
            setV(next);
          })
          .catch((err) => console.warn('[creator] the new outfit could not be loaded', err));
        outfitStatus(id)
          .then((o) => alive && setOutfit(o))
          .catch((err) => {
            console.warn('[creator] the outfit status could not be read', err);
            if (alive) setOutfit({ changed: false, reading: false, error: null });
          });
      } else if (e.event === 'chargen_outfit_error') {
        if (alive) setOutfit((o) => ({ changed: o?.changed ?? true, reading: false, error: e.error ?? null }));
      } else if (e.event === 'connected') {
        outfitStatus(id)
          .then((o) => alive && setOutfit(o))
          .catch((err) => console.warn('[creator] the outfit status could not be read', err));
      }
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
    };
  }, [id]);

  const reread = () => {
    setOutfit((o) => (o ? { ...o, reading: true, error: null } : o));
    rereadOutfit(id).catch((err) =>
      setOutfit((o) => ({
        changed: o?.changed ?? true,
        reading: false,
        error: err instanceof ApiError && err.message ? err.message : 'The re-read could not be started. Try again.',
      })),
    );
  };
  const keep = () => {
    keepOutfit(id)
      .then((o) => setOutfit(o))
      .catch((err) =>
        setOutfit((o) => ({
          changed: o?.changed ?? true,
          reading: false,
          error: err instanceof ApiError && err.message ? err.message : 'The outfit could not be kept. Try again.',
        })),
      );
  };

  /** Write what changed now (a pause, Back, or leaving the wizard). */
  const flush = useCallback(async () => {
    window.clearTimeout(timer.current);
    if (inFlight.current) await inFlight.current;
    const cur = vRef.current;
    if (!cur || !dirty.current) return;
    dirty.current = false;
    setSaving(true);
    const run = saveRealism(id, cur)
      .then(() => setSaveError(''))
      .catch((err) => {
        // Kept for the next try: the change is still on the page.
        dirty.current = true;
        setSaveError(
          err instanceof ApiError && err.message
            ? err.message
            : 'Your change could not be saved. Check the connection; it is tried again on your next change.',
        );
      })
      .finally(() => {
        inFlight.current = null;
        setSaving(false);
      });
    inFlight.current = run;
    await run;
  }, [id]);

  useImperativeHandle(ref, () => ({ flush }), [flush]);

  // Unmounting (Back, a jump in the step dots) saves what is left.
  useEffect(
    () => () => {
      if (dirty.current) void flush();
    },
    [flush],
  );

  const [pending, setPending] = useState(false);
  useEffect(() => {
    onWritingChange?.(pending || saving || !!outfit?.reading);
  }, [pending, saving, outfit?.reading, onWritingChange]);
  useEffect(() => () => onWritingChange?.(false), [onWritingChange]);

  const set = (patch: Partial<RealismValues>) => {
    if (!vRef.current) return;
    const next = { ...vRef.current, ...patch };
    vRef.current = next;
    setV(next);
    dirty.current = true;
    setPending(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      void flush().finally(() => setPending(false));
    }, SAVE_PAUSE_MS);
  };

  if (loadError) return <p className="error">{loadError}</p>;
  if (!v) return <p className="muted">Loading Porch Life…</p>;

  return (
    <div className="cg-greetings cg-realism" data-testid="realism-step">
      <div className="cg-g-intro">
        <h2>Porch Life</h2>
        <p>
          Wardrobe, likes, the story clock and Chaos work with or without the Realism Engine. This switch
          starts where Porch Life has the engine; with it on, bond, trust, mood and Needs seed the first
          chat.
        </p>
      </div>
      <RealismFormSection
        v={v}
        set={set}
        showIntimate={adult}
        afterglowOn={afterglow}
        showChargenSuggestion
        planner={planner}
        needs={<NeedsFormSection v={v} set={set} clockOn={clockOn} />}
        wardrobeNotice={
          outfit?.changed ? (
            <OutfitHint reading={outfit.reading} error={outfit.error} onReread={reread} onKeep={keep} />
          ) : undefined
        }
      />
      {saveError && (
        <p className="error" role="alert">
          {saveError}
        </p>
      )}
    </div>
  );
});
