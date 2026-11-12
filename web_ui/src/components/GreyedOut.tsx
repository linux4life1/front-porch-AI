// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A control that is present but cannot be used here: faded, taking no taps
// or focus, saying why on hover (pointer) or long-press (touch). The web twin
// of the desktop GreyedOut (docs/design/group-editor.md A2).

import { useEffect, useRef, useState, type ReactNode, type SyntheticEvent } from 'react';

const LONG_PRESS_MS = 500;
const SHOWN_MS = 2500;

/** Anything a keyboard can land on that a disabled fieldset does not cover. */
const FOCUSABLE = 'a[href], [tabindex], [contenteditable="true"], [role="slider"], [role="switch"], [role="button"]';

export function GreyedOut({ tooltip, children }: { tooltip: string; children: ReactNode }) {
  const body = useRef<HTMLFieldSetElement>(null);
  const [shown, setShown] = useState(false);
  const press = useRef<number | undefined>(undefined);
  const hide = useRef<number | undefined>(undefined);
  // Native controls are disabled by the fieldset (not focusable, not
  // changeable, whatever the input). Custom ones (role=slider and the like)
  // are taken out of the tab order here, and the capture handlers below stop
  // a click or key reaching them. Nothing covers the controls, so a person
  // or a test sees exactly what is there.
  useEffect(() => {
    body.current?.querySelectorAll(FOCUSABLE).forEach((el) => {
      el.setAttribute('tabindex', '-1');
      el.setAttribute('aria-disabled', 'true');
    });
  });
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
  const block = (e: SyntheticEvent) => {
    e.preventDefault();
    e.stopPropagation();
  };
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
      <fieldset
        className="greyed-out-body"
        ref={body}
        disabled
        onClickCapture={block}
        onKeyDownCapture={block}
        onKeyUpCapture={block}
        onInputCapture={block}
        onChangeCapture={block}
        onPointerDownCapture={block}
      >
        {children}
      </fieldset>
      {shown && (
        <span role="tooltip" className="greyed-out-tip">
          {tooltip}
        </span>
      )}
    </div>
  );
}
