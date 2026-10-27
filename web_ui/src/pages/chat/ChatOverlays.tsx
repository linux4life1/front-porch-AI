// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chance Time, reprocess, persona, image-prompt review, "Did time pass?",
// message edit, and the delete / fork confirms.
// Drawers (conversations / theme / stats) stay on the page — they are layout.

import { useState } from 'react';
import { CharacterPicker } from '../../components/CharacterPicker';
import { ReprocessNeedsModal } from '../../components/ReprocessNeedsModal';
import { ChatPersonaModal } from '../../components/ChatPersonaModal';
import { ChanceTimeModal } from '../../components/ChanceTimeModal';
import { ImagePromptReviewModal } from '../../components/ImagePromptReviewModal';
import { SkipConfirmSheet, type PendingSkip } from '../../components/SkipConfirmSheet';
import { MessageEditModal } from '../../components/MessageEditModal';
import { ConfirmDialog } from '../../components/library/LibraryDialogs';
import { api, ApiError } from '../../api/client';
import { type Message } from '../../components/chatTypes';
import { useReprocessNeeds } from './useReprocessNeeds';
import type { PendingConfirm } from './useChatSend';

// The desktop bubble's Delete Message / Fork Conversation confirms, same words.
function confirmCopy({ kind, index }: PendingConfirm) {
  return kind === 'delete'
    ? {
        title: 'Delete Message',
        message: "This can't be undone. Are you sure you want to delete this message?",
        confirmLabel: 'Delete',
        danger: true,
      }
    : {
        title: 'Fork Conversation',
        message: `Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.`,
        confirmLabel: 'Fork',
        danger: false,
      };
}

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
  pendingSkip?: PendingSkip | null;
  placeMove?: { id: string; name: string } | null;
  placeMint?: { name: string; descriptor: string; settingName?: string } | null;
  onAnswerPlaceMint?: (action: 'add_move' | 'add' | 'ignore') => void | Promise<void>;
  onAnswerPlaceMove?: (accept: boolean) => void | Promise<void>;
  pendingConfirm: PendingConfirm | null;
  onConfirmPending: () => void | Promise<void>;
  onCancelPending: () => void;
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
    pendingConfirm,
    onConfirmPending,
    onCancelPending,
  } = props;
  const { enabledNeeds, speaker, speakerName, feelingsSpeaker } = useReprocessNeeds(
    reprocessIndex,
    messages,
  );

  return (
    <>
      {pendingConfirm && (
        <ConfirmDialog
          {...confirmCopy(pendingConfirm)}
          onConfirm={() => void onConfirmPending()}
          onClose={onCancelPending}
        />
      )}

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

      {props.placeMint && (
        <PlaceMintModal
          mint={props.placeMint}
          onAnswer={(action) =>
            void (props.onAnswerPlaceMint ?? (() => {}))(action)
          }
        />
      )}

      {props.placeMove && (
        <PlaceMoveModal
          move={props.placeMove}
          onAnswer={(accept) => void (props.onAnswerPlaceMove ?? (() => {}))(accept)}
        />
      )}

      {props.pendingSkip && <SkipConfirmOverlay pending={props.pendingSkip} />}

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

/// The sheet posts its answer; a bad "Other…" keeps it open with the
/// server's reason. Keyed by the question so a new one starts fresh.
function SkipConfirmOverlay({ pending }: { pending: PendingSkip }) {
  const [error, setError] = useState<string | null>(null);
  return (
    <SkipConfirmSheet
      key={`${pending.line}|${pending.now}`}
      pending={pending}
      error={error}
      onAnswer={(answer) => {
        setError(null);
        // A 409 means it was answered elsewhere; the next snapshot closes
        // the sheet. Any other failure stays open and says why.
        api.post('/api/chat/skip-confirm', answer).catch((e: unknown) => {
          if (e instanceof ApiError && e.status === 409) return;
          setError(e instanceof Error ? e.message : String(e));
        });
      }}
    />
  );
}

/// Slice 6: the web twin of the desktop PlaceMoveDialog — same question,
/// same two answers, straight from the snapshot flag.
export function PlaceMoveModal(props: {
  move: { id: string; name: string };
  onAnswer: (accept: boolean) => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" role="dialog" aria-label="The scene moved">
      <div className="fp-card w-[420px] max-w-[92vw] p-5">
        <div className="mb-2 font-semibold">🧭 The scene moved</div>
        <p className="fp-dim">
          The story reads as arriving at {props.move.name}. Move the scene there?
        </p>
        <div className="mt-4 flex justify-end gap-2">
          <button className="fp-btn" onClick={() => props.onAnswer(false)}>Stay</button>
          <button className="fp-btn fp-btn-accent" onClick={() => props.onAnswer(true)}>Move there</button>
        </div>
      </div>
    </div>
  );
}

/// Slice 7: the web twin of the desktop mint dialog. Same question,
/// the same three honest answers, straight from the snapshot flag.
export function PlaceMintModal(props: {
  mint: { name: string; descriptor: string; settingName?: string };
  onAnswer: (action: 'add_move' | 'add' | 'ignore') => void;
}) {
  const { name, descriptor, settingName } = props.mint;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" role="dialog" aria-label="A new place in the story">
      <div className="fp-card w-[420px] max-w-[92vw] p-5">
        <div className="mb-2 font-semibold">✨ A new place in the story</div>
        <p className="fp-dim">
          The story just described {name}
          {descriptor ? ` — ${descriptor}` : ''}.{' '}
          {settingName
            ? `Save it as a place inside ${settingName}?`
            : 'Save it as a place?'}
        </p>
        <p className="fp-faint mt-2 text-xs">
          It arrives with a short description and a few lore entries written
          from what the story showed, inheriting the setting's weather. You
          can edit or delete it later like any place.
        </p>
        <div className="mt-4 flex justify-end gap-2">
          <button className="fp-btn" onClick={() => props.onAnswer('ignore')}>Ignore</button>
          <button className="fp-btn" onClick={() => props.onAnswer('add')}>Just add</button>
          <button className="fp-btn fp-btn-accent" onClick={() => props.onAnswer('add_move')}>Add and move</button>
        </div>
      </div>
    </div>
  );
}
