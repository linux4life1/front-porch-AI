// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One model call, opened (sketch U): who ran it and how it went as chips, the
// note, then the prompt and the reply on two tabs, with Copy both and Close.
// Web twin of RunLogSection._open.

import { useEffect, useState } from 'react';
import type { StoryRunEntry } from '../../../storyTypes';
import { Dialog, Segmented } from '../setup/primitives';
import { Chip } from '../StudioShell';
import { bothText, seconds, verdictTone } from './runLogShape';
import { copyText } from './copyText';

type View = 'prompt' | 'reply';

export function RunDialog({ entry: e, onClose }: { entry: StoryRunEntry; onClose: () => void }) {
  const [view, setView] = useState<View>('prompt');
  const [copied, setCopied] = useState<'' | 'yes' | 'no'>('');
  const text = (view === 'prompt' ? e.prompt : e.response) || '(empty)';

  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(''), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  return (
    <Dialog title={e.stage || 'Model call'} testid="runlog-dialog" onClose={onClose} actions={(
      <>
        <button type="button" className="s-btn-ghost" data-testid="runlog-copy"
          onClick={() => { void copyText(bothText(e)).then((ok) => setCopied(ok ? 'yes' : 'no')); }}>
          {copied === 'yes' ? 'Copied' : copied === 'no' ? 'Could not copy' : 'Copy both'}
        </button>
        <button type="button" className="s-btn-primary" onClick={onClose}>Close</button>
      </>
    )}>
      <div className="s-w720 s-chips">
        <Chip>{e.backend}</Chip>
        <Chip>{e.role}</Chip>
        {e.attempt > 1 && <Chip>try {e.attempt}</Chip>}
        {e.verdict && <Chip tone={verdictTone(e.verdict)}>{e.verdict}</Chip>}
        <Chip>{seconds(e.millis)}s</Chip>
        <Chip>{e.tokens} tok</Chip>
      </div>
      {e.note && <div className="s-muted s-body">{e.note}</div>}
      <Segmented testid="runlog-view" options={{ prompt: 'Prompt', reply: 'Reply' }} selected={view} onSelect={(v) => setView(v as View)} />
      <pre className="s-logtext" tabIndex={0} data-testid="runlog-text">{text}</pre>
    </Dialog>
  );
}
