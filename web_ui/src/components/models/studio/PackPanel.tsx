// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError } from "../../../api/client";
import type { Picture } from "./DeskRail";
import { PackDraft } from './PackDraft';
import { PackDiscardConfirmation } from './PackDiscardConfirmation';
import type { Mode } from './types';
import {
  cancelPack,
  resumePack,
  rerollPack,
  fetchPack,
  importPack,
  packPicture,
  startPack,
  type PackStart,
  type PackView,
  fetchPackPortrait,
  discardPack,
  onPackChanged,
} from "./packApi";

interface CharacterRow {
  id: string;
  name: string;
}

const REMEMBER = "fpai.pack.character";

function remembered(): string {
  try {
    return window.localStorage.getItem(REMEMBER) ?? "";
  } catch {
    return "";
  }
}

function remember(id: string) {
  try {
    window.localStorage.setItem(REMEMBER, id);
  } catch {
    /* private window: the choice just is not remembered */
  }
}

const message = (e: unknown, fallback: string) =>
  e instanceof ApiError ? e.message : fallback;

/**
 * Expression packs: pick a character, start one, watch it, stop it, and
 * import what it made. The pictures are made on the computer, by the Edit
 * graph or with the reason it cannot; nothing here decides that.
 */
export function PackPanel(props: {
  prompt: string; picture: Picture | null; workspace?: boolean;
  lastSaved?: { name: string; url: string } | null;
  sharedBusy?: boolean; configMode?: Mode; onBusy?: (busy: boolean) => void;
}) {
  const [pack, setPack] = useState<PackView | null>(null);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [character, setCharacter] = useState("");
  const [full, setFull] = useState(false);
  const [skipExisting, setSkipExisting] = useState(true);
  const [replaceExisting, setReplaceExisting] = useState(true);
  const [denoise, setDenoise] = useState(0.7);
  const [left, setLeft] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  // Why the last thing pressed did not work, shown beside the button that was
  // pressed (the desk's own note is far down the screen).
  const [startProblem, setStartProblem] = useState("");
  const [packProblem, setPackProblem] = useState("");
  const [stopped, setStopped] = useState(false);
  const [description, setDescription] = useState('');
  const [picture, setPicture] = useState<Picture | null>(null);
  const [portrait, setPortrait] = useState<string | null>(null);
  const [portraitLoading, setPortraitLoading] = useState(false);
  const [pictureLoading, setPictureLoading] = useState(false);
  const [portraitTick, setPortraitTick] = useState(0);
  const [statusLoaded, setStatusLoaded] = useState(false);
  const [captured, setCaptured] = useState(false);
  const [confirmNew, setConfirmNew] = useState(false);
  const newPackButton = useRef<HTMLButtonElement>(null);
  const draftPrompt = props.workspace ? description : props.prompt;
  const draftPicture = props.workspace ? picture : props.picture;
  const frozen = props.workspace === true && (pack != null || busy || !statusLoaded);
  const showCaptured = captured && pack?.origin === 'phone' && pack.characterId === character;

  const refreshEpoch = useRef(0);
  const refresh = useCallback(() => {
    const ticket = ++refreshEpoch.current;
    fetchPack()
      .then((value) => { if (ticket === refreshEpoch.current) setPack(value); })
      .catch((e: unknown) => {
        if (ticket === refreshEpoch.current && e instanceof ApiError && e.status === 404) setPack(null);
      }).finally(() => { if (ticket === refreshEpoch.current) setStatusLoaded(true); });
  }, []);

  const running = pack?.running === true;
  const onBusy = props.onBusy;
  useEffect(() => onBusy?.(running || busy), [running, busy, onBusy]);
  useEffect(() => {
    if (!props.workspace) return;
    return onPackChanged(refresh);
  }, [props.workspace, refresh]);
  useEffect(() => {
    if (!props.workspace || !character || pack || busy) return;
    let live = true;
    setPortraitLoading(true);
    setPortrait(null);
    fetchPackPortrait(character).then((value) => {
      if (live) setPortrait(value.image);
    }).catch((e: unknown) => {
      if (live) setStartProblem(message(e, 'Could not read the current card portrait.'));
    }).finally(() => { if (live) setPortraitLoading(false); });
    return () => { live = false; };
  }, [props.workspace, character, pack, busy, portraitTick]);
  // Looked at once, and then only while a pack is running: with no pack, or
  // one that has stopped, nothing is asked. What this panel starts or stops it
  // already has in the answer.
  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    if (!running && !props.workspace) return;
    const timer = window.setInterval(refresh, 2000);
    return () => window.clearInterval(timer);
  }, [running, refresh, props.workspace]);

  useEffect(() => {
    let live = true;
    api
      .get<CharacterRow[]>("/api/characters")
      .then((rows) => {
        if (!live) return;
        setCharacters(rows);
        const saved = remembered();
        setCharacter(
          rows.some((r) => r.id === saved) ? saved : (rows[0]?.id ?? ""),
        );
      })
      .catch(() => {
        if (live) setCharacters([]);
      });
    return () => {
      live = false;
    };
  }, []);

  const start = () => {
    if (props.workspace && (frozen || props.sharedBusy || portraitLoading || pictureLoading)) return;
    const body: PackStart = {
      characterId: character,
      set: full ? "full" : "starter",
      skipExisting,
      replaceExisting,
      denoise,
      prompt: draftPrompt,
    };
    if (draftPicture?.kind === "file")
      body.referenceImage = draftPicture.dataUrl;
    if (draftPicture?.kind === "saved")
      body.referenceFilename = draftPicture.name;
    if (props.workspace) {
      body.workspace = true;
      body.baseSource = 'currentPortrait';
      if (!draftPicture && portrait) body.referenceImage = portrait;
    }
    refreshEpoch.current++;
    setBusy(true);
    setLeft(new Set());
    setStartProblem("");
    setStopped(false);
    startPack(body)
      .then((value) => { refreshEpoch.current++; setPack(value); setCaptured(true); })
      .catch((e: unknown) =>
        setStartProblem(message(e, "Could not start the pack.")),
      )
      .finally(() => setBusy(false));
  };

  const stop = () => {
    setPackProblem("");
    cancelPack()
      .then((view) => {
        refreshEpoch.current++;
        setPack(view);
        setStopped(true);
      })
      .catch((e: unknown) =>
        setPackProblem(message(e, "Could not stop the pack.")),
      );
  };

  const doImport = () => {
    if (!pack) return;
    const keep = pack.slots
      .filter((s) => s.state === "done" && !left.has(s.emotion))
      .map((s) => s.emotion);
    refreshEpoch.current++;
    setBusy(true);
    setPackProblem("");
    importPack(keep)
      .then((value) => { refreshEpoch.current++; setPack(value); })
      .catch((e: unknown) =>
        setPackProblem(message(e, "Could not import the pack.")),
      )
      .finally(() => setBusy(false));
  };

  const iterate = (emotion?: string) => {
    refreshEpoch.current++;
    setBusy(true);
    setPackProblem("");
    setStopped(false);
    (emotion ? rerollPack(emotion) : resumePack())
      .then((value) => { refreshEpoch.current++; setPack(value); })
      .catch((e: unknown) =>
        setPackProblem(message(e, "Could not continue the pack.")),
      )
      .finally(() => setBusy(false));
  };

  const toggle = (emotion: string) =>
    setLeft((prev) => {
      const next = new Set(prev);
      if (next.has(emotion)) next.delete(emotion);
      else next.add(emotion);
      return next;
    });

  const kept = pack
    ? pack.slots.filter((s) => s.state === "done" && !left.has(s.emotion))
        .length
    : 0;
  const newPack = async () => {
    refreshEpoch.current++;
    setBusy(true);
    setPackProblem('');
    try {
      await discardPack();
      refreshEpoch.current++;
      setPack(null);
      setCaptured(false);
      setConfirmNew(false);
      setLeft(new Set());
      setStopped(false);
    } catch (e) {
      setPackProblem(message(e, 'Could not discard this pack.'));
    } finally { setBusy(false); }
  };
  return (
    <div className="fp-pack" data-region="pack">
      <p>
        A pack makes each expression from a portrait, one after another. On
        ComfyUI it runs your Edit graph; if that graph is not ready it stops and
        says what is missing.
      </p>
      {props.workspace && pack && !showCaptured ? <p>
        Target: {pack.characterName}. This pack retains its original source portrait and description.
      </p> : null}
      {props.workspace && (!pack || showCaptured) ? <PackDraft
        description={description} onDescription={setDescription}
        picture={picture} onPicture={setPicture} portrait={portrait}
        portraitLoading={portraitLoading}
        characterName={characters.find((c) => c.id === character)?.name ?? ''}
        characterId={character} onPictureLoading={setPictureLoading}
        onReloadPortrait={() => { setPortrait(null); setPortraitLoading(true); setPortraitTick((value) => value + 1); }}
        lastSaved={props.lastSaved} frozen={frozen} onProblem={setStartProblem} /> : null}
      <fieldset className="fp-pack-options" disabled={props.workspace ? frozen : running}>
      <legend>Pack target and options</legend>
      <label>
        Character
        <select
          aria-label="Character"
          value={props.workspace && pack ? pack.characterId ?? '' : character}
          disabled={running || frozen}
          onChange={(e) => {
            setCharacter(e.target.value);
            remember(e.target.value);
          }}
        >
          {characters.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <div>
        <button
          type="button"
          className="fp-pill"
          aria-pressed={!full}
          onClick={() => setFull(false)}
        >
          Starter (8)
        </button>
        <button
          type="button"
          className="fp-pill"
          aria-pressed={full}
          onClick={() => setFull(true)}
        >
          Full (28)
        </button>
      </div>
      <label>
        <input
          type="checkbox"
          checked={skipExisting}
          onChange={(e) => setSkipExisting(e.target.checked)}
        />
        Keep the ones it already has
      </label>
      <label>
        <input
          type="checkbox"
          checked={replaceExisting}
          onChange={(e) => setReplaceExisting(e.target.checked)}
        />
        Replace old images when one is made again
      </label>
      <label>
        Variation strength {denoise.toFixed(2)}
        <input
          type="range"
          aria-label="Variation strength"
          min={0.3}
          max={0.85}
          step={0.05}
          value={denoise}
          onChange={(e) => setDenoise(Number(e.target.value))}
        />
      </label>
      </fieldset>
      {!props.workspace ? <p>
        {draftPicture
          ? `Built from ${draftPicture.name}.`
          : "Built from the character’s portrait. Choose a picture above to use another."}
      </p> : null}
      <button
        type="button"
        disabled={busy || running || !character || frozen || props.sharedBusy === true ||
          (props.workspace === true && (pictureLoading || portraitLoading || (!draftPicture && !portrait) ||
            (props.configMode === 'create' && !description.trim())))}
        onClick={start}
      >
        Start pack
      </button>
      {startProblem ? <p role="alert">{startProblem}</p> : null}
      {pack ? (
        <div data-region="pack-status">
          {props.workspace && !running && pack.origin === 'phone' ? <button type="button" ref={newPackButton}
            disabled={busy || props.sharedBusy} onClick={() => setConfirmNew(true)}>New pack</button> : null}
          {confirmNew ? <PackDiscardConfirmation busy={busy} trigger={newPackButton}
            onDiscard={() => void newPack()} onKeep={() => setConfirmNew(false)} /> : null}
          <p>
            {pack.characterName}: {pack.done} of {pack.total} made
            {running ? " — working…" : ""}
          </p>
          <p>
            {pack.mode === "edit"
              ? "Made with the Edit graph."
              : "This engine has no Edit path, so the pack varies the portrait (img2img)."}
          </p>
          {pack.note ? <p>{pack.note}</p> : null}
          {pack.origin === "desktop" ? <p>Started on the computer.</p> : null}
          <ul>
            {pack.slots.map((slot) => (
              <li key={slot.emotion}>
                {slot.state === "done" ? (
                  <img
                    alt={slot.emotion}
                    src={packPicture(slot.emotion)}
                    width={64}
                    height={64}
                  />
                ) : null}
                <span>
                  {slot.emotion}:{" "}
                  {slot.state === "generating" ? "making" : slot.state}
                </span>
                {!running &&
                pack.origin === "phone" &&
                pack.imported == null ? (
                  <button
                    type="button"
                    disabled={busy || props.sharedBusy}
                    onClick={() => iterate(slot.emotion)}
                  >
                    Reroll {slot.emotion}
                  </button>
                ) : null}
                {slot.error ? <span> — {slot.error}</span> : null}
                {slot.verdict &&
                !(slot.verdict.samePerson && slot.verdict.expressionMatches) ? (
                  <span>
                    {" "}
                    — check{slot.verdict.note ? `: ${slot.verdict.note}` : ""}
                  </span>
                ) : null}
                {pack.canImport && slot.state === "done" ? (
                  <label>
                    <input
                      type="checkbox"
                      aria-label={`Keep ${slot.emotion}`}
                      checked={!left.has(slot.emotion)}
                      onChange={() => toggle(slot.emotion)}
                    />
                    Keep
                  </label>
                ) : null}
              </li>
            ))}
          </ul>
          {!running &&
          pack.origin === "phone" &&
          pack.imported == null &&
          pack.slots.some((slot) => slot.state === "pending") ? (
            <button type="button" disabled={busy || props.sharedBusy} onClick={() => iterate()}>
              Generate remaining
            </button>
          ) : null}
          {running ? (
            <button type="button" onClick={stop}>
              Cancel pack
            </button>
          ) : null}
          {stopped && !running ? <p role="status">Pack stopped.</p> : null}
          {pack.canImport ? (
            <button
              type="button"
              disabled={busy || kept === 0}
              onClick={doImport}
            >
              Import {kept} to {pack.characterName}
            </button>
          ) : null}
          {packProblem ? <p role="alert">{packProblem}</p> : null}
          {pack.imported != null ? (
            <p>
              Imported {pack.imported} for {pack.characterName}.
            </p>
          ) : null}
          {!running && pack.origin === "desktop" && pack.done > 0 ? (
            <p>Import it from Image Studio on the computer.</p>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
