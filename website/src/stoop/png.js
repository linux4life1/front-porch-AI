/* The Stoop hub — PNG tEXt chunk utilities.
   Character cards travel as PNGs with base64 JSON in a tEXt chunk:
   solo cards use the standard V2 'chara' keyword; Front Porch group cards
   use 'fpa_group' (see group_card_service.dart in the app repo). This file
   reads and writes both so the browser can produce files byte-compatible
   with what the desktop app imports and exports. */
(function () {
  'use strict';
  window.Stoop = window.Stoop || {};

  /* ---- CRC32 (PNG chunk checksums) ---- */
  var CRC_TABLE = (function () {
    var t = new Uint32Array(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(bytes, start, end) {
    var c = 0xffffffff;
    for (var i = start; i < end; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  var PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

  function isPng(bytes) {
    if (!bytes || bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) if (bytes[i] !== PNG_SIG[i]) return false;
    return true;
  }

  function readU32(bytes, off) {
    return ((bytes[off] << 24) | (bytes[off + 1] << 16) | (bytes[off + 2] << 8) | bytes[off + 3]) >>> 0;
  }

  /** Iterate chunks; cb(type, dataStart, dataLen, chunkStart, chunkLen). Return false from cb to stop. */
  function eachChunk(bytes, cb) {
    var off = 8;
    while (off + 12 <= bytes.length) {
      var len = readU32(bytes, off);
      var type = String.fromCharCode(bytes[off + 4], bytes[off + 5], bytes[off + 6], bytes[off + 7]);
      if (cb(type, off + 8, len, off, len + 12) === false) return;
      off += len + 12;
      if (type === 'IEND') return;
    }
  }

  /** Read all tEXt chunks → { keyword: value } (latin1 values — base64 payloads are ASCII-safe). */
  function readTextChunks(bytes) {
    var out = {};
    if (!isPng(bytes)) return out;
    eachChunk(bytes, function (type, dstart, dlen) {
      if (type !== 'tEXt') return;
      var nul = -1;
      for (var i = dstart; i < dstart + dlen; i++) if (bytes[i] === 0) { nul = i; break; }
      if (nul < 0) return;
      var kw = '', val = '';
      for (var a = dstart; a < nul; a++) kw += String.fromCharCode(bytes[a]);
      for (var b = nul + 1; b < dstart + dlen; b++) val += String.fromCharCode(bytes[b]);
      out[kw] = val;
    });
    return out;
  }

  /** Return new PNG bytes with a tEXt chunk (keyword=value) inserted after IHDR,
      replacing any existing chunk with the same keyword. Value must be latin1
      (base64 payloads always are). */
  function writeTextChunk(bytes, keyword, value) {
    if (!isPng(bytes)) throw new Error('not a PNG');
    var data = new Uint8Array(keyword.length + 1 + value.length);
    var i;
    for (i = 0; i < keyword.length; i++) data[i] = keyword.charCodeAt(i) & 0xff;
    data[keyword.length] = 0;
    for (i = 0; i < value.length; i++) data[keyword.length + 1 + i] = value.charCodeAt(i) & 0xff;

    var chunk = new Uint8Array(12 + data.length);
    var dv = new DataView(chunk.buffer);
    dv.setUint32(0, data.length);
    chunk[4] = 0x74; chunk[5] = 0x45; chunk[6] = 0x58; chunk[7] = 0x74; // tEXt
    chunk.set(data, 8);
    dv.setUint32(8 + data.length, crc32(chunk, 4, 8 + data.length));

    // Collect pieces: signature, then chunks (skipping same-keyword tEXt),
    // inserting ours right after IHDR.
    var pieces = [bytes.subarray(0, 8)];
    var inserted = false;
    eachChunk(bytes, function (type, dstart, dlen, cstart, clen) {
      if (type === 'tEXt') {
        var nul = -1;
        for (var j = dstart; j < dstart + dlen; j++) if (bytes[j] === 0) { nul = j; break; }
        var kw = '';
        for (var a = dstart; a < (nul < 0 ? dstart : nul); a++) kw += String.fromCharCode(bytes[a]);
        if (kw === keyword) return; // drop the old copy
      }
      pieces.push(bytes.subarray(cstart, cstart + clen));
      if (type === 'IHDR' && !inserted) { pieces.push(chunk); inserted = true; }
    });
    if (!inserted) pieces.splice(1, 0, chunk);

    var total = 0;
    pieces.forEach(function (p) { total += p.length; });
    var out = new Uint8Array(total);
    var off = 0;
    pieces.forEach(function (p) { out.set(p, off); off += p.length; });
    return out;
  }

  /* ---- base64 <-> utf8/bytes ---- */
  function bytesToBase64(bytes) {
    var s = '';
    var CH = 0x8000;
    for (var i = 0; i < bytes.length; i += CH) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, Math.min(i + CH, bytes.length)));
    }
    return btoa(s);
  }
  function base64ToBytes(b64) {
    var s = atob(b64.replace(/\s+/g, ''));
    var out = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }
  function jsonToBase64(obj) {
    return bytesToBase64(new TextEncoder().encode(JSON.stringify(obj)));
  }
  function base64ToJson(b64) {
    return JSON.parse(new TextDecoder().decode(base64ToBytes(b64)));
  }

  /** Normalize any image blob (png/jpeg/webp) to PNG bytes via canvas, so we can
      embed tEXt chunks. Returns a Promise<Uint8Array>. */
  function toPngBytes(blob) {
    return createImageBitmap(blob).then(function (bmp) {
      var canvas = document.createElement('canvas');
      canvas.width = bmp.width;
      canvas.height = bmp.height;
      canvas.getContext('2d').drawImage(bmp, 0, 0);
      bmp.close();
      return new Promise(function (resolve, reject) {
        canvas.toBlob(function (b) {
          if (!b) return reject(new Error('PNG encode failed'));
          b.arrayBuffer().then(function (buf) { resolve(new Uint8Array(buf)); }, reject);
        }, 'image/png');
      });
    });
  }

  /** Parse an uploaded card file (PNG or JSON). Resolves to
      { type: 'SOLO'|'GROUP', card: object, pngBytes: Uint8Array|null }
      or rejects with a friendly Error. */
  function parseCardFile(file) {
    var name = (file.name || '').toLowerCase();
    if (name.endsWith('.json')) {
      return file.text().then(function (text) {
        var json = JSON.parse(text);
        return classifyCardJson(json, null);
      });
    }
    return file.arrayBuffer().then(function (buf) {
      var bytes = new Uint8Array(buf);
      if (!isPng(bytes)) throw new Error('That file is not a PNG or JSON card.');
      var chunks = readTextChunks(bytes);
      if (chunks.fpa_group) return classifyCardJson(base64ToJson(chunks.fpa_group), bytes, 'GROUP');
      if (chunks.chara) return classifyCardJson(base64ToJson(chunks.chara), bytes, 'SOLO');
      throw new Error('No character data found in that PNG — export the card from your app first.');
    });
  }

  function classifyCardJson(json, pngBytes, hint) {
    // V2/V2.5/V3 envelope → unwrap to the data node the Stoop stores.
    if (json && typeof json.spec === 'string' && json.spec.indexOf('chara_card') === 0 && json.data) {
      return { type: 'SOLO', card: json.data, pngBytes: pngBytes };
    }
    if (hint === 'GROUP' || (json && (json.members || json.raw_member_data))) {
      return { type: 'GROUP', card: json, pngBytes: pngBytes };
    }
    if (json && (json.name || json.description || json.first_mes)) {
      return { type: 'SOLO', card: json, pngBytes: pngBytes };
    }
    throw new Error('That file does not look like a character or group card.');
  }

  window.Stoop.png = {
    isPng: isPng,
    readTextChunks: readTextChunks,
    writeTextChunk: writeTextChunk,
    bytesToBase64: bytesToBase64,
    base64ToBytes: base64ToBytes,
    jsonToBase64: jsonToBase64,
    base64ToJson: base64ToJson,
    toPngBytes: toPngBytes,
    parseCardFile: parseCardFile,
  };
})();
