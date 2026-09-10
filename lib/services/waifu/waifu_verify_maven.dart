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

/// Maven `-D` keys that skip the *unit* suite or ignore its failures.
/// `=false` still runs / still hard-fails. Failsafe / `-DskipITs`
/// only skip ITs — Surefire still runs. Failure-ignore twins live
/// here (not the filter set) so `=false` stays a hard receipt.
const _kMavenSkipProps = {
  'skiptests',
  'maven.test.skip',
  'maven.test.skip.exec',
  'surefire.skip',
  'surefire.skipexec',
  'testfailureignore',
  'maven.test.failure.ignore',
  'surefire.testfailureignore',
  'failsafe.testfailureignore',
};

/// Maven argv theater: reactor subset, settings/profiles/toolchains,
/// and non-root `-f`/`--file`.
///
/// `-f` / `--file` is a full receipt when the basename is `pom.xml`
/// and the parent is empty / `.`, exactly one absolute segment
/// (`/workspace/pom.xml`, `C:/proj/pom.xml`), or a known CI
/// checkout root (see [_mavenNonRootPom]). Nested absolute
/// (`/workspace/module/pom.xml`) and relative (`other/pom.xml`) are
/// theater. Fail-policy shorts (`-fae`/`-ff`/`-fn`) are not glued
/// `-fPATH`.
///
/// Reactor selectors, settings, profiles, and toolchains
/// (`-t`/`--toolchains`, `-gt`/`--global-toolchains`) are presence
/// theater. Short `-t` is toolchains only when the value is not a
/// threads spec (`-T 1C` lowers to `-t 1c` and stays a full run).
bool _mavenArgvTheater(List<String> args) {
  const failPolicyShorts = {'-fae', '-ff', '-fn'};
  final threads = RegExp(r'^\d+(\.\d+)?c?$');
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
        t.startsWith('--also-make') ||
        t == '-s' ||
        t.startsWith('-s') ||
        t.startsWith('--settings') ||
        t == '-gs' ||
        t.startsWith('-gs') ||
        t.startsWith('--global-settings') ||
        t == '-gt' ||
        t.startsWith('-gt') ||
        t.startsWith('--global-toolchains') ||
        t.startsWith('--toolchains') ||
        t == '-p' ||
        (t.startsWith('-p') && !t.startsWith('-pl')) ||
        t.startsWith('--activate-profiles')) {
      return true;
    }
    String? tc;
    if (t == '-t') {
      if (i + 1 < args.length) tc = args[i + 1];
    } else if (t.startsWith('-t=')) {
      tc = t.substring(3);
    } else if (t.startsWith('-t') && t != '-t') {
      tc = t.substring(2);
    }
    if (tc != null && tc.isNotEmpty && !threads.hasMatch(tc)) {
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
    if (file != null && _mavenNonRootPom(file)) return true;
  }
  return false;
}

/// Basename + allowlisted parent for Maven `-f` / `--file`.
///
/// Full receipt when basename is `pom.xml` and parent is:
/// - empty / `.` (cwd `pom.xml` / `./pom.xml`)
/// - exactly one absolute segment (`/workspace/pom.xml`,
///   `C:/proj/pom.xml`)
/// - GitHub Actions checkout `/home/runner/work/<repo>/<repo>`
///   (the two repo segments must be identical)
/// - container checkout `/github/workspace`
///
/// Nested modules stay theater (`/workspace/module/pom.xml`,
/// `/home/runner/work/repo/module/pom.xml`). Not a GHA layout:
/// `/home/user/proj/pom.xml`.
bool _mavenNonRootPom(String raw) {
  var path = raw.replaceAll(r'\', '/');
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  final slash = path.lastIndexOf('/');
  final base = slash < 0 ? path : path.substring(slash + 1);
  if (base != 'pom.xml') return true;
  final parent = slash < 0 ? '' : path.substring(0, slash);
  if (parent.isEmpty || parent == '.') return false;
  if (parent.startsWith('/')) {
    final segs = parent.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length == 1) return false;
    if (segs.length == 2 && segs[0] == 'github' && segs[1] == 'workspace') {
      return false;
    }
    if (segs.length == 5 &&
        segs[0] == 'home' &&
        segs[1] == 'runner' &&
        segs[2] == 'work' &&
        segs[3] == segs[4]) {
      return false;
    }
    return true;
  }
  if (parent.length >= 2 && parent[1] == ':') {
    final rest = parent.length > 2 && parent[2] == '/'
        ? parent.substring(3)
        : parent.substring(2);
    if (rest.isEmpty) return false;
    final segs = rest.split('/').where((s) => s.isNotEmpty).toList();
    return segs.length != 1;
  }
  return true;
}
