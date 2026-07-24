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

import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire codec for the handful of Draw Things messages the
/// native client uses (image_service.proto). Hand-rolled instead of protoc
/// codegen so the client has zero build-time tooling; correctness is locked
/// by golden tests against bytes produced by the Python `protobuf` runtime
/// (test/services/grpc/dt_native/). Only the fields the client reads/writes
/// are modeled; unknown fields are skipped per wire type on decode.

/// Streaming writer for protobuf wire format.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder();

  void _varint(int v) {
    // Dart ints are 64-bit; values here are non-negative.
    var n = v;
    while (n >= 0x80) {
      _b.addByte((n & 0x7f) | 0x80);
      n >>>= 7;
    }
    _b.addByte(n);
  }

  void _tag(int field, int wireType) => _varint((field << 3) | wireType);

  void int32(int field, int v) {
    if (v == 0) return; // proto3 default omitted
    _tag(field, 0);
    _varint(v & 0xFFFFFFFFFFFFFFFF);
  }

  void bytes(int field, List<int> v) {
    _tag(field, 2);
    _varint(v.length);
    _b.add(v);
  }

  void string(int field, String v) {
    if (v.isEmpty) return; // proto3 default omitted
    bytes(field, utf8.encode(v));
  }

  Uint8List take() => _b.takeBytes();
}

/// Streaming reader for protobuf wire format with unknown-field skipping.
class ProtoReader {
  final Uint8List _d;
  int _i = 0;
  ProtoReader(this._d);

  bool get hasMore => _i < _d.length;

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (true) {
      final b = _d[_i++];
      result |= (b & 0x7f) << shift;
      if (b < 0x80) return result;
      shift += 7;
    }
  }

  /// Returns (fieldNumber, wireType).
  (int, int) readTag() {
    final t = readVarint();
    return (t >>> 3, t & 0x7);
  }

  Uint8List readBytes() {
    final len = readVarint();
    final out = Uint8List.sublistView(_d, _i, _i + len);
    _i += len;
    return out;
  }

  String readString() => utf8.decode(readBytes());

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _i += 8;
      case 2:
        // NOT `_i += readVarint()`: compound assignment reads the OLD _i
        // before readVarint() advances it past the length bytes, leaving the
        // reader 1-5 bytes short inside every skipped field. That misparse
        // was the intermittent DATA_LOSS on Echo (DT's ~20KB model-metadata
        // JSON is a skipped field) and killed every streamed generation.
        final len = readVarint();
        _i += len;
      case 5:
        _i += 4;
      default:
        throw FormatException('Unsupported protobuf wire type $wireType');
    }
  }
}

/// EchoRequest { string name = 1; }
Uint8List encodeEchoRequest(String name) {
  final w = ProtoWriter();
  w.string(1, name);
  return w.take();
}

/// EchoReply { string message = 1; repeated string files = 2; ... }
class EchoReply {
  final String message;
  final List<String> files;
  EchoReply(this.message, this.files);

  static EchoReply decode(List<int> data) {
    final r = ProtoReader(Uint8List.fromList(data));
    var message = '';
    final files = <String>[];
    while (r.hasMore) {
      final (field, wt) = r.readTag();
      if (field == 1 && wt == 2) {
        message = r.readString();
      } else if (field == 2 && wt == 2) {
        files.add(r.readString());
      } else {
        r.skip(wt);
      }
    }
    return EchoReply(message, files);
  }
}

/// ImageGenerationRequest — only the fields the Python client sends:
///   optional bytes image = 1;        (sha256 of the reference tensor)
///   int32 scaleFactor = 2;
///   string prompt = 5;
///   string negativePrompt = 6;
///   bytes configuration = 7;         (FlatBuffer GenerationConfiguration)
///   string user = 10;
///   repeated bytes contents = 12;    (content-addressable tensor payloads)
class ImageGenerationRequest {
  final Uint8List? image;
  final int scaleFactor;
  final String prompt;
  final String negativePrompt;
  final Uint8List configuration;
  final String user;
  final List<Uint8List> contents;

  ImageGenerationRequest({
    this.image,
    this.scaleFactor = 1,
    required this.prompt,
    this.negativePrompt = '',
    required this.configuration,
    this.user = 'front-porch-ai',
    this.contents = const [],
  });

  Uint8List encode() {
    final w = ProtoWriter();
    if (image != null) w.bytes(1, image!);
    w.int32(2, scaleFactor);
    w.string(5, prompt);
    w.string(6, negativePrompt);
    w.bytes(7, configuration);
    w.string(10, user);
    for (final c in contents) {
      w.bytes(12, c);
    }
    return w.take();
  }
}

/// The signpost kinds the client surfaces (oneof field numbers in
/// ImageGenerationSignpostProto).
enum DtSignpost {
  textEncoded(1),
  imageEncoded(2),
  sampling(3),
  imageDecoded(4),
  secondPassImageEncoded(5),
  secondPassSampling(6),
  secondPassImageDecoded(7),
  faceRestored(8),
  imageUpscaled(9);

  final int fieldNumber;
  const DtSignpost(this.fieldNumber);
}

/// ImageGenerationResponse — decoded fields:
///   repeated bytes generatedImages = 1;
///   optional ImageGenerationSignpostProto currentSignpost = 2;
///     (oneof; Sampling { int32 step = 1; } at oneof field 3 / 6)
class ImageGenerationResponse {
  final List<Uint8List> generatedImages;
  final DtSignpost? signpost;
  final int? samplingStep;

  ImageGenerationResponse(this.generatedImages, this.signpost, this.samplingStep);

  static ImageGenerationResponse decode(List<int> data) {
    final r = ProtoReader(Uint8List.fromList(data));
    final images = <Uint8List>[];
    DtSignpost? signpost;
    int? step;
    while (r.hasMore) {
      final (field, wt) = r.readTag();
      if (field == 1 && wt == 2) {
        images.add(Uint8List.fromList(r.readBytes()));
      } else if (field == 2 && wt == 2) {
        final sp = ProtoReader(r.readBytes());
        while (sp.hasMore) {
          final (spField, spWt) = sp.readTag();
          final match = DtSignpost.values
              .where((s) => s.fieldNumber == spField)
              .firstOrNull;
          if (match != null && spWt == 2) {
            signpost = match;
            final inner = ProtoReader(sp.readBytes());
            // Sampling / SecondPassSampling carry { int32 step = 1; }.
            while (inner.hasMore) {
              final (inField, inWt) = inner.readTag();
              if (inField == 1 && inWt == 0) {
                step = inner.readVarint();
              } else {
                inner.skip(inWt);
              }
            }
          } else {
            sp.skip(spWt);
          }
        }
      } else {
        r.skip(wt);
      }
    }
    return ImageGenerationResponse(images, signpost, step);
  }
}
