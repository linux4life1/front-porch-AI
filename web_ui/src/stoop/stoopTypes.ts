// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shapes of the Stoop backend JSON relayed verbatim by /api/stoop/* (mirrors
// the desktop client's models in lib/services/backporch/). Parse defensively —
// fields the server adds later must not break older web bundles.

export interface StoopUser {
  id: string;
  email: string;
  displayName: string;
  role: 'USER' | 'MOD' | 'OWNER';
  ageVerified: boolean;
  nsfwEnabled: boolean;
  acceptedPolicyVersion: string | null;
  twoFactorEnabled: boolean;
}

export interface StoopCreatorRef {
  id: string;
  displayName: string;
}

export interface StoopCard {
  id: string;
  name: string;
  summary: string;
  type: 'SOLO' | 'GROUP';
  nsfw: boolean;
  score: number;
  downloadCount: number;
  modPick: boolean;
  creator: StoopCreatorRef | null;
  /**
   * Attribution: who originally made this character, when the uploader isn't
   * the author. Null/absent = the uploader's own work.
   */
  originalCreator?: string | null;
  primaryAssetId: string | null;
  tokenCount: number | null;
}

export interface StoopBrowsePage {
  total: number;
  page: number;
  items: StoopCard[];
}

export interface StoopCardDetail extends StoopCard {
  version: number;
  /** The raw V2/V2.5 card payload (description, personality, scenario, …). */
  card: Record<string, unknown>;
  tags: string[];
  myVote: number;
}

export interface StoopCreator {
  id: string;
  displayName: string;
  followers: number;
  following: boolean;
  isMe: boolean;
  cards: StoopCard[];
}

export interface StoopFollowedCreator {
  id: string;
  displayName: string;
  followers: number;
}

/** One of the signed-in user's own uploads, with moderation status. */
export interface StoopMine {
  id: string;
  name: string;
  type: 'SOLO' | 'GROUP';
  nsfw: boolean;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'TAKEN_DOWN';
  rejectionNote: string | null;
  summary: string;
  version: number;
  downloadCount: number;
  primaryAssetId: string | null;
}

export interface StoopMessage {
  id: string;
  fromMod: boolean;
  body: string;
  character: { id: string; name: string } | null;
  createdAt: string;
}

/** The bundled AUP document served by GET /api/stoop/aup. */
export interface StoopAup {
  id: string;
  intro: string;
  sections: { title: string; body: string }[];
}

/** Browse query — mirrors the desktop client's parameters exactly. */
export interface StoopBrowseQuery {
  sort?: 'newest' | 'top' | 'downloads';
  type?: 'solo' | 'group' | 'all';
  q?: string;
  pick?: boolean;
  following?: boolean;
  page?: number;
  take?: number;
}

export const REPORT_CATEGORIES = [
  'SPAM',
  'MISLABELED',
  'ILLEGAL',
  'STOLEN',
  'LOW_EFFORT',
  'PROHIBITED_IMAGE',
  'OTHER',
] as const;
