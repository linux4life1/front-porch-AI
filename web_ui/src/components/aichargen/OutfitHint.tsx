// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Realism step's note after the first message was rewritten or edited
// on the Greetings step (#370): the outfit below still follows the old one,
// and nothing was changed. Re-read it, or keep it. The desktop's OutfitHint
// (lib/ui/character_creator/widgets/outfit_hint.dart), word for word, in
// the creator's hint box.

import { CreatorHint } from './CreatorHint';

export function OutfitHint({
  reading,
  error,
  onReread,
  onKeep,
}: {
  reading: boolean;
  error: string | null;
  onReread: () => void;
  onKeep: () => void;
}) {
  return (
    <CreatorHint
      testid="outfit-hint"
      title="The first message changed"
      body="The outfit below was set from the old first message. Nothing was changed for you."
      action={reading ? 'Reading the outfit…' : 'Re-read the outfit from it'}
      onAction={onReread}
      dismiss="Keep this outfit"
      onDismiss={onKeep}
      disabled={reading}
      error={error}
    />
  );
}
