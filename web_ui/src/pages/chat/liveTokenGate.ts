// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Whether a streamed token belongs on screen. Token frames carry no chat id,
// and switching chats waits (up to 15s) for the reply in flight to finish —
// its tokens keep arriving the whole time. Leaving a chat mid-reply therefore
// closes the gate until that reply is over: its `done`/`error`, a reconnect,
// or a state read that shows nothing generating.

export class LiveTokenGate {
  private abandoned = false;

  /** Called as the user leaves a chat; `replyInFlight` = it was mid-reply. */
  leaveChat(replyInFlight: boolean): void {
    this.abandoned = replyInFlight;
  }

  accepts(): boolean {
    return !this.abandoned;
  }

  /** `done`/`error`, a reconnect, or a state read with no generation. */
  replyOver(): void {
    this.abandoned = false;
  }
}
