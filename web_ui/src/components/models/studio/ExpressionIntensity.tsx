// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { previewPrompts, rerollPack, type ExpressionIntensity, type PackSlot, type PackView } from './packApi';

export function IntensityPicker({value, onChange, disabled, label = 'Expression intensity'}: {
  value: ExpressionIntensity; onChange: (value: ExpressionIntensity) => void; disabled?: boolean; label?: string;
}) {
  return <label className="pack-intensity">{label}<select aria-label={label} value={value} disabled={disabled}
    onChange={(e) => onChange(e.target.value as ExpressionIntensity)}>
    <option value="current">Default (original)</option><option value="subtle">Subtle</option>
    <option value="clear">Clear</option><option value="strong">Strong</option>
  </select><small>Adjusts expression wording. Results depend on the model.</small></label>;
}

export function SlotIntensityEditor({slot, pack, disabled, onBegin, onDone, onEnd}: {
  slot: PackSlot; pack: PackView; disabled: boolean;
  onBegin: () => void; onDone: (pack: PackView) => void; onEnd: () => void;
}) {
  const [override, setOverride] = useState<ExpressionIntensity | null>(slot.intensityOverride ?? null);
  const [intensityChanged, setIntensityChanged] = useState(false);
  const intensity = override ?? pack.intensity ?? 'current';
  const [prompt, setPrompt] = useState(slot.prompt ?? '');
  const [generated, setGenerated] = useState(false);
  const [edited, setEdited] = useState(slot.customPrompt === true);
  const [newSeed, setNewSeed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState('');
  const request = useRef(0);
  useEffect(() => () => {request.current++;}, []);
  const preview = async (level = intensity) => {
    const id = ++request.current;
    setBusy(true); setProblem('');
    try {
      const value = await previewPrompts({ activePack: true, promptRules: pack.promptRules ?? {prefix:'',suffix:'',replacements:[]},
        prompt: '', set: 'full', intensity: level, useIntensityPrompt: true });
      if (id !== request.current) return;
      const found = value.previews.find((p) => p.emotion === slot.emotion);
      if (!found) throw new Error('This expression is no longer in the pack.');
      setPrompt(found.effective); setGenerated(true); setEdited(false);
    } catch (e) { if (id === request.current) setProblem(e instanceof Error ? e.message : 'Could not preview wording.'); }
    finally { if (id === request.current) setBusy(false); }
  };
  const run = async () => {
    onBegin(); setBusy(true); setProblem('');
    try { onDone(await rerollPack(slot.emotion, {...(intensityChanged ? (override === null ? {followPackIntensity:true} : {intensity:override}) : {}), newSeed, useIntensityPrompt: generated, ...(edited ? {promptOverride: prompt} : {})})); }
    catch (e) { setProblem(e instanceof Error ? e.message : 'Could not retry expression.'); }
    finally { setBusy(false); onEnd(); }
  };
  return <details><summary>Tune {slot.emotion}</summary><fieldset disabled={disabled || busy}>
    <label className="pack-intensity">Intensity for {slot.emotion}
      <select aria-label={`Intensity for ${slot.emotion}`} value={override ?? 'pack'} onChange={event => {
        const value = event.target.value === 'pack' ? null : event.target.value as ExpressionIntensity;
        setOverride(value); setIntensityChanged(true);
        if (!edited) void preview(value ?? pack.intensity ?? 'current');
      }}><option value="pack">Follow pack</option><option value="current">Default (original)</option>
        <option value="subtle">Subtle</option><option value="clear">Clear</option><option value="strong">Strong</option>
      </select>
    </label>
    <button type="button" onClick={() => void preview()}>Use intensity wording for {slot.emotion}</button>
    {edited && !generated ? <p>A custom prompt overrides intensity until you replace its wording.</p> : null}
    <label>Final prompt<textarea aria-label={`Prompt for ${slot.emotion}`} value={prompt}
      onChange={(e) => {setPrompt(e.target.value); setGenerated(false); setEdited(true);}} /></label>
    <label><input type="checkbox" checked={newSeed} onChange={(e) => setNewSeed(e.target.checked)} />New random seed</label>
    <button type="button" onClick={() => void run()}>Retry {slot.emotion} with these settings</button>
    {problem ? <p role="alert">{problem}</p> : null}
  </fieldset></details>;
}
