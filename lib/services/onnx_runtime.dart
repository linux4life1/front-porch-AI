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

import 'dart:io';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

/// Creates an [OrtSession] from a model file on every desktop platform.
///
/// `OrtSession.fromFile` in onnxruntime_v2 hands the path to the C API's
/// `CreateSession` as UTF-8 bytes, but on Windows that parameter is a
/// wide-char `ORTCHAR_T*` (UTF-16) — the bytes get reinterpreted as UTF-16
/// garbage, so loading by path fails for EVERY path there, even pure-ASCII
/// ones. `CreateSessionFromArray` takes no path at all, so on Windows we
/// read the model bytes and go through `fromBuffer` instead. ONNX-format
/// models are copied during session init and the plugin frees its transient
/// native copy before returning, so the extra memory is short-lived.
///
/// Shared by the in-process embedding, expression, and photo-caption
/// engines (docs/design/sidecar-retirement.md phases 2 and 5).
OrtSession ortSessionFromFile(File modelFile, OrtSessionOptions options) {
  if (Platform.isWindows) {
    return OrtSession.fromBuffer(modelFile.readAsBytesSync(), options);
  }
  return OrtSession.fromFile(modelFile, options);
}
