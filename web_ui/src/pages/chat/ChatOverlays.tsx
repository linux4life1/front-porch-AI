// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chance Time, reprocess, persona, image-prompt review, and message edit.
// Drawers (conversations / theme / stats) stay on the page — they are layout.

import { CharacterPicker } from '../../components/CharacterPicker';
import { ReprocessNeedsModal } from '../../components/ReprocessNeedsModal';
import { ChatPersonaModal } from '../../components/ChatPersonaModal';
import { ChanceTimeModal } from '../../components/ChanceTimeModal';
import { ImagePromptReviewModal } from '../../components/ImagePromptReviewModal';
import { MessageEditModal } from '../../components/MessageEditModal';
import { api } from '../../api/client';
import { type ChatState } from './chatState';
import { useReprocessNeeds } from './useReprocessNeeds';

export function ChatOverlays(props: {
  showPicker: boolean;
  state: ChatState;
  onPick: (name: string, full: boolean) => void;
  onClosePicker: () => void;
  editTarget: { index: number; text: string } | null;
  onCancelEdit: () => void;
  onSaveEdit: (text: string) => void | Promise<void>;
  showPersona: boolean;
  onClosePersona: () => void;
  onPersonaChanged: () => void | Promise<void>;
  reprocessIndex: number | null;
  onSubmitReprocess: (critique: string, onlyNeeds: string[]) => Promise<void>;
  onCloseReprocess: () => void;
  chance: { event: string; revealed: boolean } | null;
  onReveal: () => void;
  onAccept: () => void | Promise<void>;
}) {
  const {
    showPicker,
    state,
    onPick,
    onClosePicker,
    editTarget,
    onCancelEdit,
    onSaveEdit,
    showPersona,
    onClosePersona,
    onPersonaChanged,
    reprocessIndex,
    onSubmitReprocess,
    onCloseReprocess,
    chance,
    onReveal,
    onAccept,
  } = props;
  const pickerFull = state.pendingPicker?.full ?? false;
  const pickerFilter = state.pendingPicker?.filter ?? '';
  const imagePromptReview = state.imagePromptReview;
  const { enabledNeeds, speaker, speakerName } = useReprocessNeeds(
    reprocessIndex,
    state.messages,
    state.character?.name,
  );

  return (
    <>
      {editTarget && (
        <MessageEditModal
          initialText={editTarget.text}
          onCancel={onCancelEdit}
          onSave={onSaveEdit}
        />
      )}

      {showPicker && (
        <CharacterPicker
          initialFull={pickerFull ?? false}
          initialFilter={pickerFilter ?? ''}
          onPick={(name, full) => {
            onPick(name, full);
            onClosePicker();
          }}
          onClose={onClosePicker}
        />
      )}

      {showPersona && (
        <ChatPersonaModal onClose={onClosePersona} onChanged={onPersonaChanged} />
      )}

      {reprocessIndex !== null && (
        <ReprocessNeedsModal
          enabledNeeds={enabledNeeds}
          speaker={speaker}
          speakerName={speakerName}
          onSubmit={onSubmitReprocess}
          onClose={onCloseReprocess}
        />
      )}

      {chance && (
        <ChanceTimeModal
          event={chance.event}
          revealed={chance.revealed}
          onReveal={onReveal}
          onAccept={onAccept}
        />
      )}

      {imagePromptReview && (
        <ImagePromptReviewModal
          prompt={imagePromptReview}
          onGenerate={(edited) =>
            void api.post('/api/chat/image-review', { prompt: edited }).catch(() => {})
          }
          onCancel={() => void api.post('/api/chat/image-review', {}).catch(() => {})}
        />
      )}
    </>
  );
}
