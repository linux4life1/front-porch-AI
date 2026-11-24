// The milestone wire (docs/design/boons-and-bogies.md §7): MilestoneView.toJson
// from lib/services/chat/doors/realism/milestone_view.dart — the same words
// the desktop card reads, built once on the host.

export interface MilestoneViewJson {
  id: string;
  kind: string;
  status: 'pending' | 'accepted' | 'rejected' | string;
  seen: boolean;
  title: string;
  pill: 'BOON' | 'BOGEY' | string;
  tierLine: string;
  text: string;
  receipt: string;
  ask: string;
  ownerName: string;
  inGroup: boolean;
  meter: number;
}

/** The card on screen, from the chat-state snapshot's `milestone`. */
export interface MilestoneShowing extends MilestoneViewJson {
  replaying: boolean;
  seed: number;
}

/** GET /api/chat/tools/growth/moments */
export interface MomentsResponse {
  revision: number;
  moments: MilestoneViewJson[];
}
