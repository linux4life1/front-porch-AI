// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The one line under every Needs switch while Passage of time is off
// (docs/design/needs-on-the-clock.md, "Clock off"). With the clock off nothing
// wears, so bars that sit still are working as meant; without this line they
// read as broken. Same words as the desktop NeedsClockOffNote
// (lib/ui/widgets/needs_clock_off_note.dart).
//
// `clockOn` is Porch Life's passageOfTimeDefault. Only an explicit false shows
// the line, so a caller that has not read the setting yet shows nothing.

export function NeedsClockOffNote({ clockOn }: { clockOn: boolean }) {
  if (clockOn !== false) return null;
  return (
    <p className="muted small needs-clock-off">
      With Passage of time off, needs change only when the story says so.
    </p>
  );
}
