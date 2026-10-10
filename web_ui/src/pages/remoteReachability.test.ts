// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { remoteReachabilityLabel } from './remoteReachability';

describe('remote API status words', () => {
  it('a server that answered before a model was picked is connected, not red', () => {
    expect(remoteReachabilityLabel(false, 'reachable')).toEqual({
      text: 'Connected — pick a model',
      tone: 'configured',
    });
  });

  it('nothing answered and no model is still Not configured', () => {
    expect(remoteReachabilityLabel(false, 'unknown').text).toBe('Not configured');
    expect(remoteReachabilityLabel(false, 'unreachable').tone).toBe('down');
  });

  it('green Ready needs a model and an answer', () => {
    expect(remoteReachabilityLabel(true, 'reachable')).toEqual({ text: 'Ready', tone: 'ok' });
    expect(remoteReachabilityLabel(true, 'unknown').text).toBe('Configured');
  });
});
