// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A control that is present but cannot be used here: faded, taking no taps
// or focus, saying why on hover (pointer) or long-press (touch). The web twin
// of the desktop GreyedOut (docs/design/group-editor.md A2).

import { useEffect, useRef, useState, type ReactNode } from 'react';

const LONG_PRESS_MS = 500;
const SHOWN_MS = 2500;

export function GreyedOut({ tooltip, children }: { tooltip: string; children: ReactNode }) {
  const body = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);
  const press = useRef<number | undefined>(undefined);
  const hide = useRef<number | undefined>(undefined);
  // `inert` takes the body out of the tab order and the accessibility tree's
  // actions; React 18 does not type it, so it is set on the element.
  useEffect(() => {
    body.current?.setAttribute('inert', '');
  }, []);
  useEffect(
    () => () => {
      window.clearTimeout(press.current);
      window.clearTimeout(hide.current);
    },
    [],
  );
  const start = () => {
    press.current = window.setTimeout(() => {
      setShown(true);
      hide.current = window.setTimeout(() => setShown(false), SHOWN_MS);
    }, LONG_PRESS_MS);
  };
  const cancel = () => window.clearTimeout(press.current);
  return (
    <div
      className="greyed-out"
      title={tooltip}
      aria-disabled="true"
      data-testid="greyed-out"
      onTouchStart={start}
      onTouchEnd={cancel}
      onTouchMove={cancel}
      onTouchCancel={cancel}
    >
      <div className="greyed-out-body" ref={body}>
        {children}
      </div>
      {shown && (
        <span role="tooltip" className="greyed-out-tip">
          {tooltip}
        </span>
      )}
    </div>
  );
}
