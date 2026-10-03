// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useId, useRef, type RefObject } from 'react';

export function PackDiscardConfirmation(props: {
  busy: boolean;
  trigger: RefObject<HTMLButtonElement>;
  onDiscard: () => void;
  onKeep: () => void;
}) {
  const keep = useRef<HTMLButtonElement>(null);
  const description = useId();
  useEffect(() => {
    const trigger = props.trigger.current;
    keep.current?.focus();
    return () => { if (trigger?.isConnected) trigger.focus(); };
  }, [props.trigger]);
  return <div role="alertdialog" aria-label="Discard expression pack results" aria-describedby={description}
    onKeyDown={(e) => {
      if (e.key === 'Escape' && !props.busy) { e.preventDefault(); e.stopPropagation(); props.onKeep(); }
    }}>
    <p id={description}>Discard this pack's results and unlock its target, description and source?</p>
    <button type="button" disabled={props.busy} onClick={props.onDiscard}>Discard results and start a new pack</button>
    <button type="button" ref={keep} disabled={props.busy} onClick={props.onKeep}>Keep this pack</button>
  </div>;
}
