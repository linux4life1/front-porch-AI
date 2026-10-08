// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Dismissible banners above the transcript: an import result, a send that
// never reached the desktop (with its text and a one-tap retry), and a
// transcript action the desktop refused.

type SendError = { text: string; message: string; retrying: boolean };

function Notice({
  children,
  onDismiss,
  alert = false,
}: {
  children: React.ReactNode;
  onDismiss: () => void;
  alert?: boolean;
}) {
  return (
    <div className="chat-import-notice" role={alert ? 'alert' : undefined}>
      {children}
      <button type="button" className="link-btn" aria-label="Dismiss" onClick={onDismiss}>
        ✕
      </button>
    </div>
  );
}

export function ChatNotices({
  importNotice,
  onDismissImport,
  sendError,
  onRetrySend,
  onDismissSendError,
  actionError,
  onDismissActionError,
}: {
  importNotice: string;
  onDismissImport: () => void;
  sendError: SendError | null;
  onRetrySend: () => void;
  onDismissSendError: () => void;
  actionError: string | null;
  onDismissActionError: () => void;
}) {
  return (
    <>
      {importNotice && (
        <Notice onDismiss={onDismissImport}>
          <p>{importNotice}</p>
        </Notice>
      )}
      {sendError && (
        <Notice onDismiss={onDismissSendError} alert>
          <p>
            ⚠️ {sendError.message}
            <br />
            <span className="muted">Still here, not sent: “{sendError.text}”</span>
          </p>
          <button
            type="button"
            className="link-btn"
            disabled={sendError.retrying}
            onClick={onRetrySend}
          >
            {sendError.retrying ? 'Sending…' : 'Try again'}
          </button>
        </Notice>
      )}
      {actionError && (
        <Notice onDismiss={onDismissActionError} alert>
          <p>⚠️ {actionError}</p>
        </Notice>
      )}
    </>
  );
}
