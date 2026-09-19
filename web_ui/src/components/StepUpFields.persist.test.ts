// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings save must step up for worker URL/key the same way as the mouth
// remote. Unchanged URL + blank key stay session-only.

import { describe, expect, it } from 'vitest';
import { settingsPersistNeedsStepUp } from './StepUpFields';

// Imported symbol is added with the product fix. The cases below are the
// stolen-session contract.

const base = {
  remoteApiUrl: 'https://openrouter.ai/api/v1',
  savedRemoteApiUrl: 'https://openrouter.ai/api/v1',
  apiKey: '',
  workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
  savedWorkerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
  workerApiKey: '',
};

describe('settingsPersistNeedsStepUp', () => {
  it('unchanged hosts and blank keys stay session-only', () => {
    expect(settingsPersistNeedsStepUp(base)).toBe(false);
  });

  it('a new worker URL needs step-up', () => {
    expect(
      settingsPersistNeedsStepUp({
        ...base,
        workerRemoteApiUrl: 'https://attacker.example/v1',
      }),
    ).toBe(true);
  });

  it('a typed worker key needs step-up', () => {
    expect(settingsPersistNeedsStepUp({ ...base, workerApiKey: 'sk-stolen' })).toBe(
      true,
    );
  });

  it('a new mouth URL still needs step-up', () => {
    expect(
      settingsPersistNeedsStepUp({
        ...base,
        remoteApiUrl: 'https://attacker.example/v1',
      }),
    ).toBe(true);
  });
});
