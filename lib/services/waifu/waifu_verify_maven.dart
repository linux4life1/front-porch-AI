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

/// Surefire / Failsafe name, category, suite-XML, or scan-subset
/// filters. Presence: any value is theater. Keys are lowered
/// (`excludedGroups` → `excludedgroups`, `suiteXmlFiles` →
/// `suitexmlfiles`).
const _kMavenFilterProps = {
  'test',
  'groups',
  'excludedgroups',
  'includes',
  'excludes',
  'includesfile',
  'excludesfile',
  'includejunit5engines',
  'excludejunit5engines',
  'suitexmlfiles',
  'suitexmlfile',
  'dependenciestoscan',
  'testclassesdirectory',
  'testsourcedirectory',
  'testclasspathelements',
  'project.build.testoutputdirectory',
  'project.build.testsourcedirectory',
  'classpathdependencyexcludes',
  'classpathdependencyincludes',
  'classpathdependencyscopeexclude',
  'maven.test.dependency.excludes',
  'maven.test.dependency.includes',
  'surefire.includes',
  'surefire.excludes',
  'surefire.groups',
  'surefire.excludedgroups',
  'surefire.test',
  'surefire.includejunit5engines',
  'surefire.excludejunit5engines',
  'surefire.includesfile',
  'surefire.excludesfile',
  'surefire.suitexmlfiles',
  'surefire.suitexmlfile',
  'surefire.dependenciestoscan',
  'surefire.classpathdependencyexcludes',
  'surefire.classpathdependencyincludes',
  'surefire.classpathdependencyscopeexclude',
  'surefire.testclassesdirectory',
  'surefire.testsourcedirectory',
  'surefire.testclasspathelements',
  'it.test',
  'failsafe.test',
  'failsafe.groups',
  'failsafe.excludedgroups',
  'failsafe.includes',
  'failsafe.excludes',
  'failsafe.includejunit5engines',
  'failsafe.excludejunit5engines',
  'failsafe.includesfile',
  'failsafe.excludesfile',
  'failsafe.suitexmlfiles',
  'failsafe.suitexmlfile',
  'failsafe.dependenciestoscan',
  'failsafe.classpathdependencyexcludes',
  'failsafe.classpathdependencyincludes',
  'failsafe.classpathdependencyscopeexclude',
  'failsafe.testclassesdirectory',
  'failsafe.testsourcedirectory',
  'failsafe.testclasspathelements',
};

/// Maven `-D` keys that skip the *unit* suite. `=false` still runs.
/// Failsafe / `-DskipITs` only skip ITs — Surefire still runs.
const _kMavenSkipProps = {
  'skiptests',
  'maven.test.skip',
  'maven.test.skip.exec',
  'surefire.skip',
  'surefire.skipexec',
};
