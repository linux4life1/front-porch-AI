// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { type Message } from '../../components/chatTypes';
import { useReprocessNeeds } from './useReprocessNeeds';

const msg = (chips?: Message['chips']): Message => ({
  index: 0,
  sender: 'Aria',
  text: 'Evening.',
  isUser: false,
  chips,
});

describe('useReprocessNeeds', () => {
  it('is empty when the sheet is closed', () => {
    expect(useReprocessNeeds(null, [msg()], 'Aria')).toEqual({
      enabledNeeds: [],
      speaker: '',
      speakerName: '',
    });
  });

  it('reads enabledNeeds and speaker from the message chips', () => {
    expect(
      useReprocessNeeds(
        0,
        [
          msg({
            enabledNeeds: ['hunger', 'energy'],
            needsSpeaker: 'Bram',
          }),
        ],
        'Aria',
      ),
    ).toEqual({
      enabledNeeds: ['hunger', 'energy'],
      speaker: 'Bram',
      speakerName: 'Bram',
    });
  });

  it('falls back to the character name when the chip has no speaker', () => {
    expect(useReprocessNeeds(0, [msg({ enabledNeeds: ['fun'] })], 'Aria')).toEqual({
      enabledNeeds: ['fun'],
      speaker: '',
      speakerName: 'Aria',
    });
  });
});
