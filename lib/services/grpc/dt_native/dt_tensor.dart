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

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'dt_fpzip.dart';

/// Draw Things NNC tensor codec — a 1:1 port of `image_to_nnc_tensor` /
/// `nnc_tensor_to_image` in tools/dt-grpc-python/client.py.
///
/// Wire layout: `[uint32 identifier][ccv_nnc_tensor_param_t (64 bytes)][data]`
/// where params = { int32 type, format, datatype, reserved, dim[12] }.
/// identifier 0 → raw payload; anything else → fpzip-compressed payload
/// (what the Draw Things server sends back for generated images).

const _ccvTensorCpuMemory = 0x1;
const _ccvTensorFormatNHWC = 0x02;
const _ccv16F = 0x20000; // float16
const _ccv32F = 0x04000; // float32
const _headerLen = 68; // 4-byte identifier + 16 int32 params

/// float32 → IEEE 754 half, round-to-nearest-even (matches numpy astype).
int floatToHalf(double value) {
  final f32 = ByteData(4)..setFloat32(0, value, Endian.little);
  final x = f32.getUint32(0, Endian.little);
  final sign = (x >>> 16) & 0x8000;
  var exp = (x >>> 23) & 0xff;
  var mant = x & 0x7fffff;
  if (exp == 0xff) return sign | 0x7c00 | (mant != 0 ? 0x200 : 0); // inf/nan
  // Normalized rebias.
  var e = exp - 127 + 15;
  if (e >= 0x1f) return sign | 0x7c00; // overflow → inf
  if (e <= 0) {
    // Subnormal half (or underflow to zero).
    if (e < -10) return sign;
    mant |= 0x800000;
    final shift = 14 - e;
    final half = mant >>> shift;
    final rem = mant & ((1 << shift) - 1);
    final halfway = 1 << (shift - 1);
    if (rem > halfway || (rem == halfway && (half & 1) == 1)) {
      return sign | (half + 1);
    }
    return sign | half;
  }
  var half = (e << 10) | (mant >>> 13);
  final rem = mant & 0x1fff;
  if (rem > 0x1000 || (rem == 0x1000 && (half & 1) == 1)) half += 1;
  return sign | half;
}

/// IEEE 754 half → float32.
double halfToFloat(int h) {
  final sign = (h & 0x8000) << 16;
  var exp = (h >>> 10) & 0x1f;
  var mant = h & 0x3ff;
  int bits;
  if (exp == 0) {
    if (mant == 0) {
      bits = sign;
    } else {
      // Subnormal: normalize.
      exp = 127 - 15 + 1;
      while ((mant & 0x400) == 0) {
        mant <<= 1;
        exp -= 1;
      }
      mant &= 0x3ff;
      bits = sign | (exp << 23) | (mant << 13);
    }
  } else if (exp == 0x1f) {
    bits = sign | 0x7f800000 | (mant << 13);
  } else {
    bits = sign | ((exp - 15 + 127) << 23) | (mant << 13);
  }
  final b = ByteData(4)..setUint32(0, bits, Endian.little);
  return b.getFloat32(0, Endian.little);
}

/// Encode image file bytes (PNG/JPEG/...) as a raw NNC float16 NHWC tensor
/// normalized to [-1, 1], resized to [targetWidth] x [targetHeight] —
/// identical to the Python `image_to_nnc_tensor` (identifier 0 = raw).
Uint8List imageToNncTensor(
  Uint8List imageBytes, {
  required int targetWidth,
  required int targetHeight,
}) {
  var decoded = img.decodeImage(imageBytes);
  if (decoded == null) {
    throw const FormatException('Reference image could not be decoded');
  }
  if (decoded.width != targetWidth || decoded.height != targetHeight) {
    decoded = img.copyResize(
      decoded,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );
  }
  final h = decoded.height, w = decoded.width;
  final out = Uint8List(_headerLen + h * w * 3 * 2);
  final bd = ByteData.sublistView(out);
  bd.setUint32(0, 0, Endian.little); // identifier 0 → raw
  bd.setInt32(4, _ccvTensorCpuMemory, Endian.little);
  bd.setInt32(8, _ccvTensorFormatNHWC, Endian.little);
  bd.setInt32(12, _ccv16F, Endian.little);
  bd.setInt32(16, 0, Endian.little); // reserved
  final dims = [1, h, w, 3];
  for (var d = 0; d < 12; d++) {
    bd.setInt32(20 + d * 4, d < 4 ? dims[d] : 0, Endian.little);
  }
  var o = _headerLen;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      for (final c in [p.r, p.g, p.b]) {
        bd.setUint16(o, floatToHalf(c * 2.0 / 255.0 - 1.0), Endian.little);
        o += 2;
      }
    }
  }
  return out;
}

/// True when [data] is already an encoded image (PNG/JPEG) rather than an
/// NNC tensor — mirrors the magic-byte check in the Python `save()`.
bool isEncodedImage(Uint8List data) =>
    (data.length >= 4 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4e &&
        data[3] == 0x47) ||
    (data.length >= 2 && data[0] == 0xff && data[1] == 0xd8);

/// Decode a generated-image payload from the server into PNG bytes.
/// PNG/JPEG payloads pass through; NNC tensors are decoded — raw float16/32
/// directly, fpzip-compressed payloads via the fpzip FFI binding (throws
/// [DtFpzipUnavailableException] when the native library is missing, which
/// the caller turns into a sidecar fallback).
Uint8List decodeGeneratedImage(Uint8List data) {
  if (isEncodedImage(data)) return data;
  if (data.length <= _headerLen) {
    throw const FormatException('NNC tensor shorter than its header');
  }
  final bd = ByteData.sublistView(data);
  final identifier = bd.getUint32(0, Endian.little);
  final datatype = bd.getInt32(12, Endian.little);
  final n = bd.getInt32(20, Endian.little);
  final hh = bd.getInt32(24, Endian.little);
  final ww = bd.getInt32(28, Endian.little);
  final cc = bd.getInt32(32, Endian.little);
  final payload = Uint8List.sublistView(data, _headerLen);

  int h, w, c;
  Float32List floats;
  if (identifier == 0) {
    h = hh;
    w = ww;
    c = cc;
    final count = n * h * w * c;
    floats = Float32List(count);
    final pd = ByteData.sublistView(payload);
    if (datatype == _ccv32F) {
      for (var i = 0; i < count; i++) {
        floats[i] = pd.getFloat32(i * 4, Endian.little);
      }
    } else if (datatype == _ccv16F) {
      for (var i = 0; i < count; i++) {
        floats[i] = halfToFloat(pd.getUint16(i * 2, Endian.little));
      }
    } else {
      throw FormatException(
        'Unsupported raw NNC datatype 0x${datatype.toRadixString(16)}',
      );
    }
  } else {
    // Compressed payload — an embedded fpzip stream carrying its own dims
    // ((nf=1, nz=H, ny=W, nx=C) → C-order (H, W, C) float32).
    final result = DtFpzip.instance.decompress(payload);
    h = result.nz;
    w = result.ny;
    c = result.nx;
    floats = result.data;
  }

  if (c < 3 || h <= 0 || w <= 0) {
    throw FormatException('Unexpected NNC tensor shape (1,$h,$w,$c)');
  }
  final out = img.Image(width: w, height: h, numChannels: 3);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // (v + 1) * 255 / 2, clamped — matches nnc_tensor_to_image.
      final r = ((floats[i] + 1.0) * 127.5).clamp(0.0, 255.0).round();
      final g = ((floats[i + 1] + 1.0) * 127.5).clamp(0.0, 255.0).round();
      final b = ((floats[i + 2] + 1.0) * 127.5).clamp(0.0, 255.0).round();
      i += c;
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}
