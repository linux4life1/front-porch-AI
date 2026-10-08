// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Cast screen's own dialogs: the whole interview and the voice a character
// reads aloud with. (Add / Edit is the shared FieldsDialog.) Same titles as the
// desktop's showStoryDialog calls in cast_section.dart.

import type { StoryCastMember, StoryVoice } from '../../../storyTypes';
import { Dialog } from '../setup/primitives';

export function InterviewDialog({ member, onClose }: { member: StoryCastMember; onClose: () => void }) {
  return (
    <Dialog title={`${member.name}, interviewed`} onClose={onClose} testid="cast-interview-dialog" actions={(
      <button type="button" className="s-btn-ghost" onClick={onClose}>Close</button>
    )}>
      <div className="s-w560 s-prose sm s-pre">{member.interview}</div>
    </Dialog>
  );
}

/** Default narrator, then every voice the app has; the current one in bold, its engine on the right. */
export function VoiceDialog({ current, voices, onPick, onCancel }: {
  current: string;
  voices: StoryVoice[];
  onPick: (voiceId: string) => void;
  onCancel: () => void;
}) {
  const rows: { id: string; name: string; engine?: string }[] = [{ id: '', name: 'Default narrator' }, ...voices];
  return (
    <Dialog title="Reads aloud as" wide testid="cast-voice-dialog" onClose={onCancel} actions={(
      <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
    )}>
      <div className="s-col" style={{ gap: 0 }}>
        {rows.map((v) => (
          <button key={v.id || 'default'} type="button" className="s-listrow" aria-current={v.id === current ? 'true' : undefined}
            onClick={() => onPick(v.id)}>
            <span className={`s-grow s-ell${v.id === current ? ' s-bold' : ''}`}>{v.name}</span>
            {v.engine && <span className="s-muted s-small">{v.engine}</span>}
          </button>
        ))}
      </div>
    </Dialog>
  );
}
