// The Boons & Bogies milestone colours — the web twin of
// lib/ui/theme/milestone_palette.dart. The celebration's game identity is
// fixed in every theme (like Chance Time's); the card's chrome uses the
// theme tokens instead.

export const MILESTONE_PALETTE = {
  gold: '#FFD166', // theme-keep: milestone celebration identity
  goldDeep: '#FFC233', // theme-keep: milestone celebration identity
  onGold: '#1A1200', // theme-keep: milestone celebration identity
  violet: '#9B5DE5', // theme-keep: milestone celebration identity
  smoke: '#7D7590', // theme-keep: milestone celebration identity
  overcome: '#06D6A0', // theme-keep: milestone celebration identity
  pink: '#FF6B9D', // theme-keep: milestone celebration identity
  blue: '#118AB2', // theme-keep: milestone celebration identity
  white: '#FFFFFF', // theme-keep: milestone celebration identity
} as const;

/** The sim's colour slots, in BurstColor order (milestoneBurst.ts). */
export const MILESTONE_SLOTS: readonly string[] = [
  MILESTONE_PALETTE.gold,
  MILESTONE_PALETTE.goldDeep,
  MILESTONE_PALETTE.violet,
  MILESTONE_PALETTE.smoke,
  MILESTONE_PALETTE.overcome,
  MILESTONE_PALETTE.pink,
  MILESTONE_PALETTE.blue,
  MILESTONE_PALETTE.white,
];
