import { useEffect, useState } from 'react';
import { api } from '../../api/client';

// The install's 18+ master switch, for surfaces that show or hide adult
// controls — currently the "Intimate preferences" chip lists in the character
// editor and creator.
//
// Rides the SAME /api/settings `realism` object PorchLifeSettings already
// reads, rather than a new endpoint, so there is one server-side source of
// truth (StorageService.realismSettings.adultThemesEnabled) and the web cannot
// disagree with desktop about whether 18+ is on.
//
// Defaults FALSE while loading and on any error: the safe direction is to hide
// adult controls from someone who has not opted in, not to flash them for a
// frame. Nothing typed is lost either way — the values stay on the card, the
// same as flipping the master switch on desktop.
//
// `afterglow` is Porch Life Afterglow, which counts only while 18+ is on
// (desktop RealismSettings.afterglowEnabled): the Afterglow switches on
// characters, groups and chats, and a character's Recovery block, show while
// it is on.
export function useAdultFlags(): { adult: boolean; afterglow: boolean } {
  const [flags, setFlags] = useState({ adult: false, afterglow: false });
  useEffect(() => {
    let alive = true;
    // Deferred, so a page whose api has no get (a narrow test double) stays
    // hidden instead of throwing mid-render.
    Promise.resolve()
      .then(() =>
        api.get<{ realism?: { adultThemesEnabled?: boolean; nsfwCooldownDefault?: boolean } }>(
          '/api/settings',
        ),
      )
      .then((s) => {
        if (!alive) return;
        const adult = s.realism?.adultThemesEnabled === true;
        setFlags({ adult, afterglow: adult && s.realism?.nsfwCooldownDefault === true });
      })
      .catch(() => {
        /* stay hidden — see above */
      });
    return () => {
      alive = false;
    };
  }, []);
  return flags;
}
