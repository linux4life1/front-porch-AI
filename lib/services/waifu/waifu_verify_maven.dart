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
  'additionalclasspathelements',
  'maven.test.additionalclasspath',
  'maven.test.additionalclasspathdependencies',
  'generatedtestsourcesdirectory',
  'generatedsourcesdirectory',
  'project.build.generatedsourcesdirectory',
  'project.build.generatedtestsourcesdirectory',
  'classesdirectory',
  'project.build.outputdirectory',
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
  'surefire.additionalclasspathelements',
  'surefire.generatedtestsourcesdirectory',
  'surefire.classesdirectory',
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
  'failsafe.additionalclasspathelements',
  'failsafe.generatedtestsourcesdirectory',
  'failsafe.classesdirectory',
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

/// Maven argv theater: reactor subset + non-default `-f`/`--file`.
///
/// Default POM (`pom.xml` / `./pom.xml`, after stripping a leading
/// `./`) is a full receipt. A different path — spaced, `=`, or glued —
/// is theater. Fail-policy shorts (`-fae`/`-ff`/`-fn`) are not
/// glued `-fPATH`.
///
/// Reactor selectors (`-pl`/`--projects`, `-rf`/`--resume-from`,
/// `-N`/`--non-recursive`, also-make) are a subset of the reactor.
bool _mavenArgvTheater(List<String> args) {
  const failPolicyShorts = {'-fae', '-ff', '-fn'};
  for (var i = 0; i < args.length; i++) {
    final t = args[i];
    if (t.startsWith('-pl') ||
        t.startsWith('--projects') ||
        t.startsWith('-rf') ||
        t.startsWith('--resume-from') ||
        t == '-n' ||
        t == '--non-recursive' ||
        t == '-r' ||
        t == '--resume' ||
        t == '-am' ||
        t == '-amd' ||
        t.startsWith('--also-make')) {
      return true;
    }
    String? file;
    if (t == '-f' || t == '--file') {
      if (i + 1 < args.length) file = args[i + 1];
    } else if (t.startsWith('-f=')) {
      file = t.substring(3);
    } else if (t.startsWith('--file=')) {
      file = t.substring(7);
    } else if (t.startsWith('--file') && t != '--file') {
      file = t.substring(6);
    } else if (t.startsWith('-f') &&
        t != '-f' &&
        !failPolicyShorts.contains(t)) {
      file = t.substring(2);
    }
    if (file == null) continue;
    var pom = file;
    while (pom.startsWith('./') || pom.startsWith(r'.\')) {
      pom = pom.substring(2);
    }
    if (pom != 'pom.xml') return true;
  }
  return false;
}
