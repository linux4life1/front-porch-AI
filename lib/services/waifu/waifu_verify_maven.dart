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
  'basedir',
  'project.basedir',
  'maven.multimoduleprojectdirectory',
  'session.executionrootdirectory',
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
  'maven.test.error.ignore',
  'testerrorignore',
  'surefire.testerrorignore',
  'failsafe.testerrorignore',
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
/// `-fPATH`. `-fn` / `--fail-never` is theater (red still receipts);
/// `-fae` / `--fail-at-end` and `-ff` / `--fail-fast` stay full.
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
        t.startsWith('--activate-profiles') ||
        t == '-fn' ||
        t.startsWith('--fail-never')) {
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
/// - GitHub Actions Linux `/home/runner/work/<repo>/<repo>`
///   (the two repo segments must be identical)
/// - GitHub Actions Windows `X:/a/<repo>/<repo>` (any drive +
///   `a` + identical trailing repo pair)
/// - Azure Pipelines classic `X:/a/<id>/s` (any drive + `a` +
///   numeric-or-id + sources dir `s`)
/// - Azure Pipelines Linux `/home/vsts/work/<id>/s` (same id rule)
/// - container checkout `/github/workspace`
///
/// Nested modules stay theater (`/workspace/module/pom.xml`,
/// `/home/runner/work/repo/module/pom.xml`,
/// `D:/a/repo/module/pom.xml`, `D:/a/1/s/module/pom.xml`,
/// `/home/vsts/work/1/s/module/pom.xml`).
/// Not a GHA/Azure layout: `/home/user/proj/pom.xml`.
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
    if (segs.length == 5 &&
        segs[0] == 'home' &&
        segs[1] == 'vsts' &&
        segs[2] == 'work' &&
        segs[4] == 's' &&
        _kMavenCiBuildId.hasMatch(segs[3])) {
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
    if (segs.length == 1) return false;
    if (segs.length == 3 && segs[0] == 'a' && segs[1] == segs[2]) {
      return false;
    }
    if (segs.length == 3 &&
        segs[0] == 'a' &&
        segs[2] == 's' &&
        _kMavenCiBuildId.hasMatch(segs[1])) {
      return false;
    }
    return true;
  }
  return true;
}

/// Azure / GHA agent build-id segment (lowered).
final _kMavenCiBuildId = RegExp(r'^[0-9a-z][0-9a-z._-]*$');

/// Cwd Gradle script basenames (optional `./` already stripped).
const _kGradleCwdScripts = {
  'build.gradle',
  'build.gradle.kts',
  'settings.gradle',
  'settings.gradle.kts',
};

/// Gradle argv theater: `--continue` (soft Done), `--include-build`
/// (composite), project-dir / build-file / settings-file relocate.
///
/// `-p` / `--project-dir` theater when the value is not cwd (`.` /
/// `./`), including `-p=` / empty. `-b` / `-c` / `--build-file` /
/// `--settings-file` use the same relocate rule, plus cwd default
/// script basenames (`build.gradle`, `settings.gradle(.kts)`).
/// Missing or empty is theater. [rawArgs] keeps case so glued
/// `-Pfoo` is not project-dir. `--continuous` is not `--continue`.
/// Short `-c` is `--settings-file`; long `--console` is not.
bool _gradleArgvTheater(List<String> args, List<String> rawArgs) {
  for (var i = 0; i < args.length; i++) {
    final t = args[i];
    if (t == '--continue' || t.startsWith('--continue=')) return true;
    if (t == '--include-build' || t.startsWith('--include-build')) {
      return true;
    }
    String? dir;
    var projectDir = false;
    if (t == '-p' || t == '--project-dir') {
      dir = i + 1 < args.length ? args[i + 1] : '';
      projectDir = true;
    } else if (t == '-b' ||
        t == '-c' ||
        t == '--build-file' ||
        t == '--settings-file') {
      dir = i + 1 < args.length ? args[i + 1] : '';
    } else if (t.startsWith('--project-dir=')) {
      dir = t.substring(14);
      projectDir = true;
    } else if (t.startsWith('--project-dir') && t != '--project-dir') {
      dir = t.substring(13);
      projectDir = true;
    } else if (t.startsWith('--build-file=')) {
      dir = t.substring(13);
    } else if (t.startsWith('--build-file') && t != '--build-file') {
      dir = t.substring(12);
    } else if (t.startsWith('--settings-file=')) {
      dir = t.substring(16);
    } else if (t.startsWith('--settings-file') && t != '--settings-file') {
      dir = t.substring(15);
    } else if (t.startsWith('-p=')) {
      if (i >= rawArgs.length ||
          rawArgs[i].length < 2 ||
          rawArgs[i][1] != 'p') {
        continue;
      }
      dir = t.substring(3);
      projectDir = true;
    } else if (t.startsWith('-b=')) {
      dir = t.substring(3);
    } else if (t.startsWith('-c=')) {
      dir = t.substring(3);
    } else if (!t.startsWith('--') &&
        t.startsWith('-b') &&
        t != '-b' &&
        !t.contains('=')) {
      dir = t.substring(2);
    } else if (!t.startsWith('--') &&
        t.startsWith('-c') &&
        t != '-c' &&
        !t.contains('=')) {
      dir = t.substring(2);
    } else if (t.startsWith('-p') && t != '-p' && !t.contains('=')) {
      if (i >= rawArgs.length ||
          rawArgs[i].length < 2 ||
          rawArgs[i][1] != 'p') {
        continue;
      }
      dir = t.substring(2);
      projectDir = true;
    }
    if (dir == null) continue;
    if (dir.isEmpty) return true;
    var path = dir.replaceAll(r'\', '/');
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isEmpty || path == '.') continue;
    if (!projectDir &&
        !path.contains('/') &&
        _kGradleCwdScripts.contains(path)) {
      continue;
    }
    return true;
  }
  return false;
}
