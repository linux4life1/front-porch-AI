// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

part of 'waifu_verify.dart';

/// Soft-Done families. Flag-shaped tokens only — never path substrings.
/// Coverage / transform / watch-FS ignores are not collection filters.
bool _isTheaterFlag(String w) {
  if (!w.startsWith('-')) return false;
  if (w == '-h' || w == '--help' || w.startsWith('--help')) return true;
  if (_mavenSkipProperty(w) || _polyglotSoftDone(w)) return true;
  if (w == '--ignore' ||
      w.startsWith('--ignore=') ||
      w.startsWith('--ignore-glob')) {
    return true;
  }
  if ('--co,--listtests,--listtestfiles,--just-print,--recon'
      .split(',')
      .contains(w)) {
    return true;
  }
  return '--show-only,--collect-only,--list-test,--list-suite,--list-group,--no-run,--question,--dry-run,--dryrun,--dry_run,--total-shards,--shard-index,--typecheck,--testpathignore,--test-path-ignore,--modulepathignore,--module-path-ignore,--exclude,--shard,--filter'
      .split(',')
      .any(w.startsWith);
}

const _kJsSuiteFilters = {'-t', '--testnamepattern', '--testpathpattern'};

const _kJsFailedOnly = {
  '--onlyfailures',
  '--onlychanged',
  '-o',
  '--lf',
  '--last-failed',
  '--ff',
  '--failed-first',
  '--changedsince',
  '--findrelatedtests',
  '--lastcommit',
  '--changed',
  '--related',
  '--watch',
  '--watchall',
  '--changedfileswithancestor',
  '--workspace',
  '--project',
  '--dir',
  '--ui',
  '--selectprojects',
  '--runtestsbypath',
};

const _kSuiteFilterFlags = <String, Set<String>>{
  'gradle': {'--tests'},
  'dotnet': {'--filter'},
  'swift': {'--filter', '--skip'},
  'pytest': {'-k', '--keyword', '-m', '--sw', '--stepwise', '--looponfail'},
  'flutter': {'--name', '--plain-name', '--tags', '--exclude-tags', '-t', '-x'},
  'dart': {'--name', '--plain-name', '--tags', '--exclude-tags', '-t', '-x'},
  'jest': _kJsSuiteFilters,
  'vitest': _kJsSuiteFilters,
  'phpunit': {'--filter', '--testsuite', '--group', '--exclude-group'},
  'rspec': {'-e', '--example', '--tag', '-t', '--pattern', '--exclude-pattern'},
  'npm': _kJsSuiteFilters,
  'pnpm': _kJsSuiteFilters,
  'yarn': _kJsSuiteFilters,
  'bun': {..._kJsSuiteFilters, '--filter'},
  'deno': {..._kJsSuiteFilters, '--filter'},
  'test': _kJsSuiteFilters,
};

const _kFailedOnlyFlags = <String, Set<String>>{
  'pytest': {'--lf', '--last-failed', '--ff', '--failed-first', '-f'},
  'phpunit': {'-g', '--order-by', '--covers', '--uses'},
  'jest': _kJsFailedOnly,
  'vitest': _kJsFailedOnly,
  'rspec': {'--only-failures', '--next-failure', '-n', '--example-matches'},
  'npm': _kJsFailedOnly,
  'pnpm': _kJsFailedOnly,
  'yarn': _kJsFailedOnly,
  'bun': _kJsFailedOnly,
  'deno': {..._kJsFailedOnly, '--doc'},
  'test': _kJsFailedOnly,
  'mix': {'--failed', '--stale', '--only', '--exclude'},
  'go': {'-short', '-skip', '-list', '-fuzz'},
};

/// Peeled `test` / `test:*` and JS hosts share [_kJsFailedOnly].
Set<String>? _failedOnlyFor(String cmd) =>
    _kFailedOnlyFlags[cmd] ?? (cmd.startsWith('test:') ? _kJsFailedOnly : null);

/// Twin: peeled `test:*` shares [_kJsSuiteFilters] via `test`.
Set<String>? _suiteFiltersFor(String cmd) =>
    _kSuiteFilterFlags[cmd] ??
    (cmd.startsWith('test:') ? _kJsSuiteFilters : null);
