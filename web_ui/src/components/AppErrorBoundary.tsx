// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Without a boundary, one render error anywhere unmounts the whole app to a
// blank page — and an installed PWA has no address bar to reload from, so it
// reads as "frozen, have to restart". This keeps the failure on screen in
// plain words with two ways out. Navigating anywhere clears it.

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { useLocation } from 'react-router-dom';

type Props = { children: ReactNode; pathname: string };
type State = { error: Error | null; pathname: string };

// Already on the library: changing the hash would not clear the error.
function backToLibrary() {
  if (window.location.hash === '#/' || window.location.hash === '') {
    window.location.reload();
  } else {
    window.location.hash = '#/';
  }
}

class Boundary extends Component<Props, State> {
  state: State = { error: null, pathname: this.props.pathname };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    return props.pathname !== state.pathname
      ? { error: null, pathname: props.pathname }
      : null;
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[app] screen crashed', error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="page centered-col" role="alert">
        <h2>Something went wrong on this screen</h2>
        <p className="muted">
          Your chats and characters are safe on your computer. Reload to try
          again, or go back to your library.
        </p>
        <p className="muted small">{this.state.error.message}</p>
        <button className="primary" onClick={() => window.location.reload()}>
          Reload
        </button>
        <button className="link-btn" onClick={backToLibrary}>
          Back to library
        </button>
      </div>
    );
  }
}

export function AppErrorBoundary({ children }: { children: ReactNode }) {
  const { pathname } = useLocation();
  return <Boundary pathname={pathname}>{children}</Boundary>;
}
