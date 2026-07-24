import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

/** Story Calendar (docs/design/story-calendar.md §6) — web twin of the
 *  desktop StoryCalendarDialog: a month grid over the chat's real dates.
 *  The current story date glows porch amber, days holding journal memories
 *  for the selected diary owner carry a dot, tapping a marked day lists that
 *  day's memories, and the anchor controls re-anchor "story begins on…" or
 *  set the current date & time. Phone gets the full-screen treatment via the
 *  shared `[data-layout="phone"]` modal override. */

interface CalendarCard {
  content: string;
  category: string;
  feeling: string | null;
  intensity: string | null;
  pinned: boolean;
}

interface CalendarPayload {
  storyStartDate: string;
  storyClock: string;
  currentDay: number;
  owner: string | null;
  owners: { id: string; name: string }[];
  days: { day: number; cards: CalendarCard[] }[];
}

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const DAY_MS = 86400000;

function parseUtcDate(iso: string): Date {
  // Date-only strings parse as UTC midnight already; full ISO keeps its zone.
  return new Date(iso.length <= 10 ? `${iso}T00:00:00Z` : iso);
}

function utcMidnight(d: Date): number {
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

function fmtShort(ms: number): string {
  const d = new Date(ms);
  return `${WEEKDAYS[(d.getUTCDay() + 6) % 7].slice(0, 3)}, ${MONTHS[d.getUTCMonth()].slice(0, 3)} ${d.getUTCDate()}`;
}

export function StoryCalendarModal({
  focusedId,
  canEdit,
  onClose,
  onChanged,
}: {
  focusedId: string | null | undefined;
  canEdit: boolean;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [data, setData] = useState<CalendarPayload | null>(null);
  const [ownerId, setOwnerId] = useState<string | null>(focusedId ?? null);
  const [month, setMonth] = useState<{ y: number; m: number } | null>(null);
  const [selectedDay, setSelectedDay] = useState<number | null>(null);

  const load = useCallback(async (owner: string | null) => {
    const q = owner ? `?owner=${encodeURIComponent(owner)}` : '';
    const payload = await api.get<CalendarPayload>(`/api/chat/tools/calendar${q}`);
    setData(payload);
    setOwnerId(payload.owner);
    setMonth((m) => {
      if (m) return m;
      const clock = parseUtcDate(payload.storyClock);
      return { y: clock.getUTCFullYear(), m: clock.getUTCMonth() };
    });
  }, []);

  useEffect(() => {
    load(ownerId).catch(() => setData(null));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!data || !month) {
    return (
      <div className="drawer-backdrop center" onClick={onClose}>
        <div className="modal story-calendar-modal" onClick={(e) => e.stopPropagation()}>
          <div className="drawer-head"><span>📅 Story Calendar</span>
            <button className="link-btn" onClick={onClose}>Close</button>
          </div>
          <div className="centered"><div className="spinner" /></div>
        </div>
      </div>
    );
  }

  const startMs = utcMidnight(parseUtcDate(data.storyStartDate));
  const clock = parseUtcDate(data.storyClock);
  const currentMs = utcMidnight(clock);
  const cardsByDay = new Map(data.days.map((d) => [d.day, d.cards]));
  const ownerName = data.owners.find((o) => o.id === ownerId)?.name ?? '';

  const firstOfMonth = Date.UTC(month.y, month.m, 1);
  const daysInMonth = new Date(Date.UTC(month.y, month.m + 1, 0)).getUTCDate();
  const leadBlanks = (new Date(firstOfMonth).getUTCDay() + 6) % 7; // Mon-first

  const dayFor = (ms: number) => Math.max(1, Math.floor((ms - startMs) / DAY_MS) + 1);

  const shiftMonth = (delta: number) => {
    const d = new Date(Date.UTC(month.y, month.m + delta, 1));
    setMonth({ y: d.getUTCFullYear(), m: d.getUTCMonth() });
  };

  const post = async (body: Record<string, unknown>) => {
    await api.post(`/api/chat/tools/time`, body);
    setMonth(null);
    setSelectedDay(null);
    await load(ownerId);
    onChanged();
  };

  const clockHHMM = `${String(clock.getUTCHours()).padStart(2, '0')}:${String(clock.getUTCMinutes()).padStart(2, '0')}`;
  const clockLocalValue = `${clock.getUTCFullYear()}-${String(clock.getUTCMonth() + 1).padStart(2, '0')}-${String(clock.getUTCDate()).padStart(2, '0')}T${clockHHMM}`;
  const startValue = data.storyStartDate;

  const selectedCards = selectedDay != null ? cardsByDay.get(selectedDay) ?? [] : [];

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal story-calendar-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>📅 Story Calendar</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <p className="muted small">
          {fmtShort(currentMs)} · Day {data.currentDay}
        </p>

        <div className="story-cal-nav">
          <button className="link-btn" onClick={() => shiftMonth(-1)}>◀</button>
          <span>{MONTHS[month.m]} {month.y}</span>
          <button className="link-btn" onClick={() => shiftMonth(1)}>▶</button>
        </div>

        <div className="story-cal-grid">
          {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((w, i) => (
            <span key={`h${i}`} className="story-cal-head">{w}</span>
          ))}
          {Array.from({ length: leadBlanks }, (_, i) => <span key={`b${i}`} />)}
          {Array.from({ length: daysInMonth }, (_, i) => {
            const ms = firstOfMonth + i * DAY_MS;
            const inStory = ms >= startMs && ms <= currentMs;
            const day = dayFor(ms);
            const marked = inStory && cardsByDay.has(day);
            const isCurrent = ms === currentMs;
            const isSelected = inStory && selectedDay === day;
            return (
              <button
                key={ms}
                className={
                  'story-cal-day' +
                  (isCurrent ? ' current' : '') +
                  (isSelected ? ' selected' : '') +
                  (inStory ? '' : ' outside')
                }
                disabled={!marked}
                onClick={() => setSelectedDay(isSelected ? null : day)}
              >
                <span>{i + 1}</span>
                <span className={`story-cal-dot${marked ? ' on' : ''}`} />
              </button>
            );
          })}
        </div>

        {data.owners.length > 1 && (
          <label className="story-cal-owner muted small">
            Memories:{' '}
            <select
              value={ownerId ?? ''}
              onChange={(e) => {
                setSelectedDay(null);
                setOwnerId(e.target.value);
                load(e.target.value).catch(() => undefined);
              }}
            >
              {data.owners.map((o) => (
                <option key={o.id} value={o.id}>{o.name}</option>
              ))}
            </select>
          </label>
        )}

        <div className="story-cal-detail">
          {selectedDay == null ? (
            <p className="muted small">
              {data.days.length === 0
                ? `No dated memories yet — ${ownerName}'s journal marks the calendar as the story unfolds.`
                : `Tap a marked day to read what ${ownerName} remembers from it.`}
            </p>
          ) : (
            <>
              <div className="story-cal-detail-head">
                DAY {selectedDay} — {fmtShort(startMs + (selectedDay - 1) * DAY_MS).toUpperCase()}
              </div>
              {selectedCards.map((c, i) => (
                <div key={i} className="story-cal-card">
                  <div>{c.content}</div>
                  {c.feeling && <div className="muted small">felt {c.feeling}{c.pinned ? ' · pinned' : ''}</div>}
                </div>
              ))}
            </>
          )}
        </div>

        {canEdit && (
          <div className="story-cal-anchors">
            <label className="muted small">
              Story begins
              <input
                type="date"
                defaultValue={startValue}
                onChange={(e) => e.target.value && post({ setStartDate: e.target.value })}
              />
            </label>
            <label className="muted small">
              Now
              <input
                type="datetime-local"
                defaultValue={clockLocalValue}
                onChange={(e) => e.target.value && post({ setClock: `${e.target.value}:00Z` })}
              />
            </label>
          </div>
        )}
      </div>
    </div>
  );
}
