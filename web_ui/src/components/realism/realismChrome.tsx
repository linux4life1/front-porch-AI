// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop Realism form's chrome (lib/ui/widgets/realism_form_section.dart,
// realism_section_header.dart, identity_chip_lists.dart, story_begins_row.dart,
// birthday_row.dart): an accent section heading with its Material icon, the
// rounded bordered card each section sits in, the story-start chips under
// Time & Day and the Birthday row. Presentation only; colours are theme
// tokens (styles/realism-desktop.css).

import { useRef, type ReactNode } from 'react';

/** Line icons for the section headings and toggle rows, one per Material
 *  icon the desktop draws. Decorative: the heading or row text names each. */
function Line({ children }: { children: ReactNode }) {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {children}
    </svg>
  );
}

export const RlIcon = {
  /** Icons.schedule */
  clock: () => (<Line><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></Line>),
  /** Icons.favorite */
  heart: () => (<Line><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" fill="currentColor" /></Line>),
  /** Icons.favorite_outline */
  heartOutline: () => (<Line><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" /></Line>),
  /** Icons.mood */
  mood: () => (<Line><circle cx="12" cy="12" r="9" /><path d="M8.5 14s1.3 2 3.5 2 3.5-2 3.5-2M9 9.5h.01M15 9.5h.01" /></Line>),
  /** Icons.tune */
  tune: () => (<Line><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></Line>),
  /** Icons.flag */
  flag: () => (<Line><path d="M5 21V4h10l1 2h4v9h-6l-1-2H5" fill="currentColor" /></Line>),
  /** Icons.flag_outlined */
  flagOutline: () => (<Line><path d="M5 21V4h10l1 2h4v9h-6l-1-2H5" /></Line>),
  /** Icons.work_outline */
  work: () => (<Line><rect x="3" y="7" width="18" height="13" rx="2" /><path d="M9 7V5h6v2" /></Line>),
  /** Icons.cake_outlined */
  cake: () => (<Line><path d="M4 21h16v-7H4ZM4 17c2 1 4-1 4-1s2 2 4 0 4 0 4 0 2 2 4 1" /><path d="M8 14v-3M12 14v-3M16 14v-3M12 8V6" /></Line>),
  /** Icons.checkroom (the hanger) */
  hanger: () => (<Line><path d="M12 7a2 2 0 1 1 2-2c0 1.2-2 1.8-2 3L3 16h18l-9-8" /></Line>),
  /** Icons.nightlight_round */
  moon: () => (<Line><path d="M15 3a9 9 0 1 0 0 18 7 7 0 0 1 0-18Z" fill="currentColor" /></Line>),
  /** Icons.battery_full */
  battery: () => (<Line><rect x="8" y="4" width="8" height="17" rx="1.5" fill="currentColor" /><path d="M10 2h4" /></Line>),
  /** Icons.water_drop_outlined */
  drop: () => (<Line><path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11Z" /></Line>),
  /** Icons.local_fire_department */
  flame: () => (<Line><path d="M12 21a6 6 0 0 0 6-6c0-4-3-6-4-10-2 2-3 4-3 6-1-1-2-2-2-4-2 2-3 5-3 8a6 6 0 0 0 6 6Z" /></Line>),
  /** Icons.casino */
  dice: () => (<Line><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M9 9h.01M15 9h.01M12 12h.01M9 15h.01M15 15h.01" /></Line>),
  /** Icons.verified_user */
  shield: () => (<Line><path d="M12 3 5 6v5c0 5 3 8 7 10 4-2 7-5 7-10V6Z" /><path d="m9 12 2 2 4-4" /></Line>),
  /** Icons.psychology */
  brain: () => (<Line><path d="M9 21v-3H6a2 2 0 0 1-2-2v-3l-2-1 2-3a8 8 0 0 1 16 2c0 2.5-1.2 4.4-3 5.6V21" /><circle cx="12" cy="10" r="2" /></Line>),
};

/** The desktop's RealismSectionHeader: icon + title in the section's accent.
 *  Keeps `realism-head` (tests and siblings find headings by it). */
export function SectionHead({
  icon,
  title,
  tone = 'accent',
}: {
  icon: ReactNode;
  title: string;
  tone?: 'accent' | 'intimate';
}) {
  return (
    <h4 className={`realism-head rl-head ${tone}`}>
      <span className="rl-head-icon">{icon}</span>
      {title}
    </h4>
  );
}

/** The rounded bordered card a desktop section sits in. */
export function RlCard({ children, testid }: { children: ReactNode; testid?: string }) {
  return (
    <div className="rl-card" data-testid={testid}>
      {children}
    </div>
  );
}

/** Opens the browser's own picker for a hidden date or time input. */
function openPicker(el: HTMLInputElement | null) {
  if (!el) return;
  try {
    el.showPicker();
  } catch {
    el.focus();
    el.click();
  }
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "Jun 1, 1887" for an ISO date, as the desktop's StoryClock.formatShortDate. */
export function shortDate(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  return `${MONTHS[Number(m[2]) - 1] ?? m[2]} ${Number(m[3])}, ${m[1]}`;
}

/** "11:45 PM" for an HH:MM, as the desktop's StoryClock.formatClock. */
export function clockText(hhmm: string): string {
  const m = /^(\d{1,2}):(\d{2})/.exec(hhmm);
  if (!m) return hhmm;
  const h = Number(m[1]);
  return `${h % 12 === 0 ? 12 : h % 12}:${m[2]} ${h < 12 ? 'AM' : 'PM'}`;
}

/** One story-start chip: a button that opens the hidden picker, and × to
 *  clear when set (desktop StoryBeginsRow). */
function StoryChip({
  icon,
  text,
  type,
  label,
  value,
  onChange,
}: {
  icon: ReactNode;
  text: string;
  type: 'date' | 'time';
  label: string;
  value: string | null | undefined;
  onChange: (v: string | null) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  return (
    <div className={`rl-chip${value ? ' set' : ''}`}>
      <button type="button" className="rl-chip-main" onClick={() => openPicker(input.current)}>
        <span className="rl-chip-icon">{icon}</span>
        <span>{text}</span>
      </button>
      {value && (
        <button type="button" className="rl-chip-clear" aria-label={`Clear: ${label}`} onClick={() => onChange(null)}>
          ×
        </button>
      )}
      <input
        ref={input}
        className="rl-hidden-picker"
        type={type}
        aria-label={label}
        tabIndex={-1}
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value || null)}
      />
    </div>
  );
}

/** "Story begins: the day the chat starts" / "Opens at: time-of-day default",
 *  or the chosen date and time with × to clear. */
export function StoryStartChips({
  date,
  time,
  onDate,
  onTime,
}: {
  date: string | null | undefined;
  time: string | null | undefined;
  onDate: (v: string | null) => void;
  onTime: (v: string | null) => void;
}) {
  return (
    <div className="rl-chips" data-testid="story-begins-row">
      <StoryChip
        icon={<RlIcon.flagOutline />}
        text={date ? `Story begins ${shortDate(date)}` : 'Story begins: the day the chat starts'}
        type="date"
        label="Story begins"
        value={date}
        onChange={onDate}
      />
      <StoryChip
        icon={<RlIcon.clock />}
        text={time ? `Opens at ${clockText(time)}` : 'Opens at: time-of-day default'}
        type="time"
        label="Opens at"
        value={time}
        onChange={onTime}
      />
    </div>
  );
}
