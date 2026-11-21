// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState, type ReactNode, type Ref } from 'react';
import type { ExpandSignal } from './FeatureGroup';

export type Need = 'alone' | 'needs' | 'core';

export function FeatureRow({
  icon,
  label,
  subtitle,
  blurb,
  need = 'alone',
  dependsOn,
  satisfied = true,
  showDependencyBadge = false,
  value,
  onChange,
  trailing,
  children,
  showChildWhenOff = false,
  featureChildren,
  onDependencyTap,
  expandDetailsSignal,
  highlighted = false,
  rowRef,
}: {
  icon: string;
  label: string;
  subtitle?: string;
  blurb: string;
  need?: Need;
  dependsOn?: string;
  satisfied?: boolean;
  /** True only when the dependency lives outside this item's own subgroup. */
  showDependencyBadge?: boolean;
  value: boolean;
  onChange?: (v: boolean) => void;
  /** Optional custom trailing control (e.g. segmented picker) instead of a toggle. */
  trailing?: ReactNode;
  children?: ReactNode;
  /** Show `children` with the switch off too (desktop FeatureRow parity). */
  showChildWhenOff?: boolean;
  /** Nested dependent rows rendered beneath a vertical tree connector. */
  featureChildren?: ReactNode;
  /** Called when a cross-subgroup dependent chip is clicked to scroll to its parent. */
  onDependencyTap?: () => void;
  expandDetailsSignal?: ExpandSignal;
  highlighted?: boolean;
  rowRef?: Ref<HTMLDivElement>;
}) {
  const [detailsExpanded, setDetailsExpanded] = useState(
    expandDetailsSignal ? expandDetailsSignal.expanded : true,
  );

  useEffect(() => {
    if (expandDetailsSignal && expandDetailsSignal.version > 0) {
      setDetailsExpanded(expandDetailsSignal.expanded);
    }
  }, [expandDetailsSignal]);

  const gated = need === 'needs' && !satisfied;
  const isCore = need === 'core';
  const railActive = value && !gated;
  const showChip = showDependencyBadge && need === 'needs' && !!dependsOn;

  return (
    <div className="pl-node">
      <div
        ref={rowRef}
        className={[
          'pl-row',
          isCore ? 'pl-row-core' : '',
          gated ? 'pl-row-gated' : '',
          highlighted ? 'pl-row-highlight' : '',
        ]
          .filter(Boolean)
          .join(' ')}
      >
        <div className="pl-row-main">
          <span className="pl-row-icon" aria-hidden="true">
            {icon}
          </span>
          <div className="pl-row-body">
            <div className="pl-row-head-wrap">
              <button
                type="button"
                className="pl-row-toggle"
                aria-expanded={detailsExpanded}
                title={
                  detailsExpanded
                    ? 'Click to hide details'
                    : 'Click to show details'
                }
                onClick={() => setDetailsExpanded((v) => !v)}
              >
                <span className="pl-label">{label}</span>
                {subtitle && <span className="pl-subtitle">{subtitle}</span>}
              </button>
              {showChip &&
                (onDependencyTap ? (
                  <button
                    type="button"
                    className="pl-chip pl-chip-needs pl-chip-link"
                    onClick={onDependencyTap}
                    title="Jump to required setting"
                  >
                    <span>needs {dependsOn}</span>
                    <span aria-hidden="true" className="pl-chip-arrow">
                      ↗
                    </span>
                  </button>
                ) : (
                  <span className="pl-chip pl-chip-needs">
                    needs {dependsOn}
                  </span>
                ))}
            </div>
          </div>
          {trailing ?? (
            <label className="pl-switch">
              <input
                type="checkbox"
                role="switch"
                className="switch"
                checked={value}
                onChange={(e) => onChange?.(e.target.checked)}
                disabled={gated}
                aria-label={label}
              />
            </label>
          )}
        </div>
        {detailsExpanded && (
          <div className="pl-details-wrap">
            <p className="pl-blurb">{blurb}</p>
          </div>
        )}
        {children && (value || showChildWhenOff) && !gated && (
          <div className="pl-child">{children}</div>
        )}
      </div>
      {featureChildren && (
        <div className={`pl-tree-children${railActive ? ' active' : ''}`}>
          {featureChildren}
        </div>
      )}
    </div>
  );
}
