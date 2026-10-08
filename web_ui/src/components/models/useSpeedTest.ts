// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Local model card's speed test on the phone, run as the desktop's
// KoboldSpeedTestButton and its dialog run it: the host asks first, then
// starts it, and the phone follows it and can Cancel it. How it stands comes
// from the host twice over: the card's own read (every 10 s, and again when
// a test ends or the hub reconnects) and the hub's `speed_test` event each
// time it changes. The newer of the two is shown. Every sentence is the host's,
// except when a request does not get through: that is said in the phone's own
// plain words (describeActionFailure), never the browser's.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { describeActionFailure } from '../../pages/chat/chatActionError';
import type { SpeedTestCard, SpeedTestRun, SpeedTestState } from './types';

/** What the overlay shows: nothing, the question, why the test cannot run,
 *  or the test itself. */
export type SpeedTestView =
  | { kind: 'closed' }
  | { kind: 'ask'; words: string }
  | { kind: 'refused'; words: string }
  | { kind: 'watch' };

const STATES: readonly SpeedTestState[] = ['idle', 'running', 'stopping', 'done', 'stopped', 'failed'];

/** Asked to start, before the host has said anything: running, no words yet. */
export const SPEED_TEST_STARTING: SpeedTestRun = {
  state: 'running',
  step: 0,
  steps: 0,
  left: null,
  doing: '',
  line: null,
};

/** Running or stopping: the button reopens the test, and Cancel is offered. */
export const speedTestRuns = (run: SpeedTestRun | null): boolean =>
  run?.state === 'running' || run?.state === 'stopping';

const ended = (run: SpeedTestRun) =>
  run.state === 'done' || run.state === 'stopped' || run.state === 'failed';

/** The speed test a `speed_test` event carries, or null when it carries none. */
export function speedTestOf(x: unknown): SpeedTestRun | null {
  if (typeof x !== 'object' || x === null) return null;
  const o = x as Record<string, unknown>;
  const state = STATES.find((s) => s === o.state);
  if (!state) return null;
  return {
    state,
    step: typeof o.step === 'number' ? o.step : 0,
    steps: typeof o.steps === 'number' ? o.steps : 0,
    left: typeof o.left === 'string' ? o.left : null,
    doing: typeof o.doing === 'string' ? o.doing : '',
    line: typeof o.line === 'string' ? o.line : null,
  };
}

let ticks = 0;
/** The one clock the card's reads and the hub's events are put in order by:
 *  a read sent after an event knows more than that event, and an event that
 *  came after a read was sent knows more than that read. */
export const speedTestClock = (): number => ++ticks;

// A request that fails says so in the phone's own plain words, never the
// browser's ("Failed to fetch"): the computer may be off or out of reach.
const failed = (what: string) => (e: unknown) => describeActionFailure(what, e);

type Ask = { ask: string | null; refused: string | null };
type Start = { started: boolean; refused: string | null };

/**
 * [card] is the speed test on the card on screen, whose read was sent at
 * [cardAt] on [speedTestClock]; [reload] reads the card again.
 */
export function useSpeedTest(
  card: SpeedTestCard | undefined,
  cardAt: number,
  reload: () => unknown,
) {
  // The hub's latest word, and when it came.
  const [live, setLive] = useState<{ run: SpeedTestRun; at: number } | null>(null);
  const [view, setView] = useState<SpeedTestView>({ kind: 'closed' });
  // The question, a start or a Cancel is on its way to the host.
  const [busy, setBusy] = useState(false);
  // Why a Cancel did not reach the host.
  const [problem, setProblem] = useState('');

  // A host without the speed test sends no `speedTest`: nothing to follow.
  const supported = card !== undefined;
  useEffect(() => {
    if (!supported) return;
    const socket = new ChatSocket((e) => {
      // (Re)connected: events sent while the socket was down are gone.
      if (e.event === 'connected') return void reload();
      if (e.event !== 'speed_test') return;
      const run = speedTestOf(e.speedTest);
      if (!run) return;
      setLive({ run, at: speedTestClock() });
      // The card's line is how the last test of its model ended.
      if (ended(run)) void reload();
    });
    socket.connect();
    return () => socket.close();
  }, [supported, reload]);

  const run = live && live.at > cardAt ? live.run : (card ?? null);
  const running = speedTestRuns(run);

  const open = useCallback(async () => {
    // A second tap while the question is on its way asks nothing more.
    if (busy) return;
    setProblem('');
    if (running) return setView({ kind: 'watch' });
    setBusy(true);
    const next = await api.get<Ask>('/api/backend/local-model/speed-test').then(
      (a): SpeedTestView =>
        a.refused || !a.ask ? { kind: 'refused', words: a.refused ?? '' } : { kind: 'ask', words: a.ask },
      (e): SpeedTestView => ({ kind: 'refused', words: failed('open the speed test')(e) }),
    );
    setBusy(false);
    setView(next);
  }, [busy, running]);

  const start = useCallback(async () => {
    setBusy(true);
    // Running from here: what the host said before is not this test's.
    setLive({ run: SPEED_TEST_STARTING, at: speedTestClock() });
    const refused = await api
      .post<Start>('/api/backend/local-model/speed-test')
      .then((r) => (r.started ? null : (r.refused ?? '')), failed('start the speed test'));
    setBusy(false);
    if (refused === null) {
      // A card read sent before this answer may have been read before the
      // test started: the hub's word (or "starting") stays newer than it.
      const at = speedTestClock();
      setLive((l) => ({ run: l?.run ?? SPEED_TEST_STARTING, at }));
      return setView({ kind: 'watch' });
    }
    setLive((l) => (l?.run === SPEED_TEST_STARTING ? null : l));
    setView({ kind: 'refused', words: refused });
    void reload();
  }, [reload]);

  const cancel = useCallback(async () => {
    setProblem('');
    setBusy(true);
    await api
      .post('/api/backend/local-model/speed-test/cancel')
      .catch((e: unknown) => setProblem(failed('stop the speed test')(e)));
    setBusy(false);
  }, []);

  const close = useCallback(() => {
    setProblem('');
    setView({ kind: 'closed' });
  }, []);

  // Never closed under a test that runs, nor while a start is on its way.
  const closable = !busy && !(view.kind === 'watch' && running);

  return { run, running, view, busy, problem, closable, open, start, cancel, close };
}

export type SpeedTest = ReturnType<typeof useSpeedTest>;
