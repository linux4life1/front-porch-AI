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
import { type Message } from '../../components/chatTypes';
import { useReprocessNeeds } from './useReprocessNeeds';

export function ChatOverlays(props: {
  showPicker: boolean;
  pickerFull?: boolean;
  pickerFilter?: string;
  onPick: (name: string, full: boolean) => void;
  onClosePicker: () => void;
  editTarget: { index: number; text: string } | null;
  onCancelEdit: () => void;
  onSaveEdit: (text: string) => Promise<void>;
  showPersona: boolean;
  onClosePersona: () => void;
  onPersonaChanged: () => void | Promise<void>;
  reprocessIndex: number | null;
  messages: Message[];
  onSubmitReprocess: (critique: string, onlyNeeds: string[]) => Promise<void>;
  onSubmitReprocessFeelings: () => Promise<void>;
  onCloseReprocess: () => void;
  chance: { event: string; revealed: boolean } | null;
  onReveal: () => void;
  onAccept: () => void | Promise<void>;
  imagePromptReview?: string;
}) {
  const {
    showPicker,
    pickerFull,
    pickerFilter,
    onPick,
    onClosePicker,
    editTarget,
    onCancelEdit,
    onSaveEdit,
    showPersona,
    onClosePersona,
    onPersonaChanged,
    reprocessIndex,
    messages,
    onSubmitReprocess,
    onSubmitReprocessFeelings,
    onCloseReprocess,
    chance,
    onReveal,
    onAccept,
    imagePromptReview,
  } = props;
  const { enabledNeeds, speaker, speakerName, feelingsSpeaker } = useReprocessNeeds(
    reprocessIndex,
    messages,
  );

  return (
    <>
      {editTarget && (
        <MessageEditModal
          initialText={editTarget.text}
          showThinking={!messages.find((m) => m.index === editTarget.index)?.isUser}
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
          feelingsSpeaker={feelingsSpeaker}
          onSubmit={onSubmitReprocess}
          onSubmitFeelings={onSubmitReprocessFeelings}
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
