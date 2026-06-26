// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reader: the assembled novel in reading order (act → scene → beat prose), with
// a per-scene 🔊 read-aloud (reuses the chat's TTS). Mirrors StoryReaderPage.

import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { SpeakButton } from '../components/VoiceControls';

export function StoryReaderPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, error } = useStory(id);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  const sceneProse = (ai: number, si: number): string => {
    const beats = p.beats[`${ai}-${si}`] ?? [];
    return beats
      .map((_, bi) => {
        const pr = p.prose[`${ai}-${si}-${bi}`];
        return pr?.final || pr?.draft || '';
      })
      .filter(Boolean)
      .join('\n\n');
  };

  return (
    <div className="page reader">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate(`/stories/${id}`)}>← {p.title}</button>
        <h2>{p.title}</h2>
      </div>

      {p.acts.map((act, ai) => {
        const scenes = p.scenes[String(ai)] ?? [];
        return (
          <div key={ai} className="reader-act">
            <h3 className="reader-act-title">Act {act.number}{act.title ? `: ${act.title}` : ''}</h3>
            {scenes.map((sc, si) => {
              const text = sceneProse(ai, si);
              if (!text) return null;
              return (
                <section key={si} className="reader-scene">
                  <div className="reader-scene-head">
                    <h4>{sc.title || `Scene ${sc.number}`}</h4>
                    <SpeakButton text={text} />
                  </div>
                  {text.split(/\n\n+/).map((para, pi) => <p key={pi}>{para}</p>)}
                </section>
              );
            })}
          </div>
        );
      })}
    </div>
  );
}
