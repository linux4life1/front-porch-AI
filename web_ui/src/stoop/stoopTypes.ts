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
  /** Additive: gold = owner, blue = trusted uploader. Absent on older servers. */
  verification?: 'gold' | 'blue' | null;
  role: 'USER' | 'MOD' | 'OWNER';
  ageVerified: boolean;
  /** Absent on older servers — treat missing as verified (nothing to nag). */
  emailVerified?: boolean;
  nsfwEnabled: boolean;
  acceptedPolicyVersion: string | null;
  twoFactorEnabled: boolean;
  /** Public creator-profile extras (absent on older servers). */
  bio?: string | null;
  profileLinks?: string[];
  avatarAssetId?: string | null;
  avatarLocked?: boolean;
  createdAt?: string;
  /** An email change awaiting confirmation at the NEW address, or null. */
  pendingEmail?: string | null;
}

export interface StoopCreatorRef {
  id: string;
  displayName: string;
  verification?: 'gold' | 'blue' | null;
}

/**
 * Worlds on The Stoop — client readiness flag (mirrors the desktop's
 * kStoopWorldsLive). Portable places (.fpworld) ride the same card endpoints
 * as a third `type: 'WORLD'` (payload = the .fpworld envelope, cover image as
 * the card avatar) and go through the same moderation pipeline as characters.
 * The backend doesn't accept WORLD yet; while false the UI shows Worlds as
 * "coming soon". Flip together with the desktop flag when the backend ships.
 */
export const STOOP_WORLDS_LIVE = true;

export interface StoopCard {
  id: string;
  name: string;
  summary: string;
  type: 'SOLO' | 'GROUP' | 'WORLD';
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
  /** Additive WORLD list DTO fields; full card envelopes may be omitted. */
  climateEnabled?: boolean | null;
  climate_enabled?: boolean | null;
  card?: Record<string, unknown>;
}

export interface StoopCommentReply {
  authorId: string;
  displayName: string;
  verification?: 'gold' | 'blue' | null;
  authorAvatarAssetId?: string | null;
  createdAt: string;
  body: string;
  deleted?: boolean;
}

export interface StoopComment {
  id: string;
  cardId: string;
  authorId: string;
  displayName: string;
  verification?: 'gold' | 'blue' | null;
  authorAvatarAssetId?: string | null;
  createdAt: string;
  body: string;
  deleted?: boolean;
  reply?: StoopCommentReply | null;
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
  /** Per-card Discussion opt-in. Missing => off. */
  commentsEnabled?: boolean;
  /** Owner kill-switch. True hides Discussion without wiping comments. */
  commentsLocked?: boolean;
}

export interface StoopCreator {
  id: string;
  displayName: string;
  verification?: 'gold' | 'blue' | null;
  followers: number;
  following: boolean;
  isMe: boolean;
  cards: StoopCard[];
  /** Profile extras + lifetime totals (absent on older servers). */
  bio?: string | null;
  links?: string[];
  avatarAssetId?: string | null;
  createdAt?: string;
  stats?: { cards: number; downloads: number; score: number };
}

export interface StoopFollowedCreator {
  id: string;
  displayName: string;
  verification?: 'gold' | 'blue' | null;
  followers: number;
  avatarAssetId?: string | null;
}

/** One of the signed-in user's own uploads, with moderation status. */
export interface StoopMine {
  id: string;
  name: string;
  type: 'SOLO' | 'GROUP' | 'WORLD';
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
  type?: 'solo' | 'group' | 'world' | 'all';
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
