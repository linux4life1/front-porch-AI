// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Each group member's Recovery block, while Afterglow runs for them: the
// phone twin of the Recovery block on each member's card in desktop Group
// Settings → Realism. It saves to the member through the chat's tools a
// moment after the last change, and leaving the panel sends what is left.

import { useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import { describeActionFailure } from '../../pages/chat/chatActionError';
import { RecoveryBlock } from '../realism/RecoveryBlock';
import { recoveryFromDetail, type RecoveryProfileValue } from '../realism/realismTypes';

export interface MemberRecoveryRow {
  id: string;
  name: string;
  /** Porch Life, the group chat's switch and the member's own (additive). */
  afterglowRuns?: boolean;
  recovery?: unknown;
  sex?: string;
}

const SETTLE_MS = 400;

export function GroupMemberRecoverySection({ members }: { members: MemberRecoveryRow[] }) {
  const [values, setValues] = useState<Record<string, RecoveryProfileValue>>({});
  const [error, setError] = useState('');
  const pending = useRef<Record<string, RecoveryProfileValue>>({});
  const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  const send = (id: string) => {
    clearTimeout(timers.current[id]);
    const recovery = pending.current[id];
    delete pending.current[id];
    if (!recovery) return;
    void api
      .post('/api/chat/tools/member-recovery', { id, recovery })
      .then(() => setError(''))
      .catch((e) => {
        console.warn('[group] member recovery save failed', e);
        setError(describeActionFailure('save the Recovery block', e));
      });
  };
  // A fresh snapshot is the truth again for every member not waiting to save,
  // so a change made elsewhere shows here instead of being posted over.
  useEffect(() => {
    setValues((v) => Object.fromEntries(Object.entries(v).filter(([id]) => pending.current[id])));
  }, [members]);
  // Leaving the panel must not drop the last change.
  useEffect(() => () => Object.keys(pending.current).forEach(send), []);

  const shown = members.filter((m) => m.afterglowRuns === true);
  if (shown.length === 0) return null;
  return (
    <div data-testid="member-recovery-section">
      {error && (
        <p className="error" role="alert">
          ⚠️ {error}
        </p>
      )}
      {shown.map((m) => (
        <div key={m.id} data-testid={`member-recovery-${m.id}`}>
          <h4 className="section-label">{m.name}</h4>
          <RecoveryBlock
            recovery={values[m.id] ?? recoveryFromDetail(m.recovery)}
            sex={m.sex}
            onChange={(recovery) => {
              setValues((v) => ({ ...v, [m.id]: recovery }));
              pending.current[m.id] = recovery;
              clearTimeout(timers.current[m.id]);
              timers.current[m.id] = setTimeout(() => send(m.id), SETTLE_MS);
            }}
          />
        </div>
      ))}
    </div>
  );
}
