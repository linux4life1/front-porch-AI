// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GET /api/image/remote-panel: the computer judges what the Remote panel
// shows, so the phone reads the same words and choices as the desktop.

import { api } from '../../../api/client';
import type { Mode } from './types';

export interface RemoteTile {
  id: string;
  label: string;
  url: string;
  sub: string;
  selected: boolean;
  hasKey: boolean;
}

export interface RemoteChoice {
  value: string;
  label: string;
  selected: boolean;
}

export interface RemotePanel {
  hosts: RemoteTile[];
  hostId: string;
  hostLabel: string;
  url: string;
  billing: string;
  needsKey: boolean;
  keyPrompt: string;
  keyHint: string;
  keyNote: string;
  needsKeyLine: string;
  reachable: boolean;
  status: string;
  modelName: string;
  modelId: string;
  badges: string[];
  price: string;
  sizeMode: 'pixels' | 'xai' | 'none';
  sizeTitle: string;
  sizes: RemoteChoice[];
  resolutions: RemoteChoice[];
  sizeNote: string;
}

/** [refresh] asks the host for its models again instead of the last list. */
export const fetchRemotePanel = (mode: Mode, refresh: boolean) =>
  api.get<RemotePanel>(`/api/image/remote-panel?mode=${mode}${refresh ? '&refresh=1' : ''}`);
