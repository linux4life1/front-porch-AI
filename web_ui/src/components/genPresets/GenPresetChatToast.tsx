// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The model-switch toast on the chat page: a switch from the model chip says
// which values the new model writes with, and how many of this chat's own
// values still sit on top. The host applies the switch's preset a moment
// after the save answers (it looks the model up first), so the notice is
// read a few times after the chip says it switched, and again on every
// settings_changed the chat page's socket hears (a switch made elsewhere).

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../api/client';
import { MODEL_SWITCHED_EVENT, SETTINGS_CHANGED_EVENT, type ChatGeneration } from './genPresets';
import { GenPresetToast, useOnFreshNotice } from './GenPresetToast';
import { useGenPresets } from './useGenPresets';

const READS_AFTER_SWITCH_MS = [300, 1000, 2500];

/** Said after the switch notice when the chat has values of its own. */
export function chatOwnWords(overrides: number | undefined): string {
  if (!overrides) return '';
  return `This chat's own changes (${overrides}) still apply.`;
}

export function GenPresetChatToast() {
  const { data, act, reload } = useGenPresets(false);
  const [extra, setExtra] = useState('');
  useEffect(() => {
    let timers: ReturnType<typeof setTimeout>[] = [];
    const onSwitch = () => {
      timers.forEach(clearTimeout);
      timers = READS_AFTER_SWITCH_MS.map((ms) => setTimeout(reload, ms));
    };
    window.addEventListener(MODEL_SWITCHED_EVENT, onSwitch);
    window.addEventListener(SETTINGS_CHANGED_EVENT, reload);
    return () => {
      window.removeEventListener(MODEL_SWITCHED_EVENT, onSwitch);
      window.removeEventListener(SETTINGS_CHANGED_EVENT, reload);
      timers.forEach(clearTimeout);
    };
  }, [reload]);
  const onNotice = useCallback(() => {
    api
      .get<ChatGeneration>('/api/chat/generation')
      .then((c) => setExtra(chatOwnWords(c.open ? c.overrides : 0)))
      .catch((e) => console.warn('[gen-presets] chat values read failed', e));
  }, []);
  useOnFreshNotice(data, onNotice);
  return <GenPresetToast data={data} act={act} extra={extra} />;
}
