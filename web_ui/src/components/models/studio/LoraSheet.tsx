// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { fetchCatalog, fetchLocalCatalog } from './deskApi';
import { factsByFile, loraBadge } from './deskRules';
import type { LoraFact, Mode, ReadyFacts } from './types';

/** LoRA files the connected app lists. A tap fills the first empty slot. */
export function LoraSheet(props: {
  mode: Mode;
  backend: string;
  facts: ReadyFacts | null;
  onFacts: (facts: Record<string, LoraFact>) => void;
  onPick: (file: string) => void;
  onClose: () => void;
}) {
  const [files, setFiles] = useState<string[]>([]);
  const [known, setKnown] = useState<Record<string, LoraFact>>({});
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    const done = (list: string[] | undefined, facts: LoraFact[] | undefined) => {
      if (!live) return;
      setFiles(list ?? []);
      const byFile = factsByFile(props.facts?.loraFacts, facts);
      setKnown(byFile);
      props.onFacts(byFile);
    };
    if (props.backend === 'drawthings') {
      void fetchLocalCatalog(props.facts?.primary ?? '')
        .then((cat) => done(cat.loras, cat.loraFacts))
        .catch(() => live && setFailed(true));
    } else if (props.backend === 'comfyui') {
      void fetchCatalog(props.mode, { lora: true })
        .then((cat) => done(cat.loras, cat.loraFacts))
        .catch(() => live && setFailed(true));
    }
    return () => {
      live = false;
    };
    // Read once when the sheet opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const family = props.facts?.loraFamily;
  const fits = files.filter((f) => loraBadge(f, family, known) !== 'other base');
  const others = files.filter((f) => loraBadge(f, family, known) === 'other base');
  return (
    <div className="fp-sheet" role="dialog" aria-label="LoRA">
      <button type="button" onClick={props.onClose}>Close</button>
      <h2>LoRA</h2>
      <p>These are the LoRA files the connected app listed. A tap fills the first empty slot.</p>
      {failed ? <p>The list could not be read.</p> : null}
      <p>Matches this model</p>
      <ul>
        {fits.map((f) => (
          <li key={f}><button type="button" onClick={() => props.onPick(f)}>{f}</button></li>
        ))}
      </ul>
      <p>Other bases</p>
      <ul>
        {others.map((f) => (
          <li key={f}><button type="button" onClick={() => props.onPick(f)}>{f}</button></li>
        ))}
      </ul>
    </div>
  );
}
