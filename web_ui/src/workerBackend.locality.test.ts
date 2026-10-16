// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { backendLaneIsLocal, workerPairAllowed } from './workerBackend';

const otherPc = [
  'http://10.1.2.3:5001/v1',
  'http://172.16.0.4:5001/v1',
  'http://172.20.1.8:5001/v1',
  'http://172.31.255.9:5001/v1',
  'http://192.168.1.50:5001/v1',
  'http://100.64.0.8:5001/v1',
  'http://100.127.9.9:5001/v1',
  'http://server.local:5001/v1',
  'http://evalbox:5001/v1',
];

describe('worker locality is loopback only', () => {
  it('lets a Kobold mouth use another PC', () => {
    for (const url of otherPc) {
      expect(backendLaneIsLocal('openRouter', url), url).toBe(false);
      expect(workerPairAllowed('kobold', '', 'openRouter', url), url).toBe(true);
    }
  });

  it('keeps loopback, including [::1] and the rest of 127.0.0.0/8', () => {
    for (const url of [
      'http://localhost:5001/v1',
      'http://127.0.0.1:5001/v1',
      'http://127.0.0.2:5001/v1',
      'http://127.255.255.255:5001/v1',
      'http://[::1]:5001/v1',
      'http://0.0.0.0:5001/v1',
      'http://localhost:1234/v1',
    ]) {
      expect(backendLaneIsLocal('openRouter', url), url).toBe(true);
      expect(workerPairAllowed('kobold', '', 'openRouter', url), url).toBe(false);
    }
    expect(
      workerPairAllowed('kobold', '', 'openRouter', 'http://localhost:1234/v1', true),
    ).toBe(true);
    expect(workerPairAllowed('kobold', '', 'omlx', 'http://localhost:8000/v1')).toBe(
      false,
    );
  });

  it('still allows a cloud mouth with a LAN worker', () => {
    expect(
      workerPairAllowed(
        'openRouter',
        'https://openrouter.ai/api/v1',
        'openRouter',
        'http://192.168.1.50:5001/v1',
      ),
    ).toBe(true);
  });
});
