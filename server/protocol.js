'use strict';

const PROTOCOL_VERSION = 23;
let CLIENT_VERSION = 31129;

class Writer {
  constructor(size) {
    this.buffer = Buffer.allocUnsafe(size);
    this.byteOffset = 0;
  }
  writeUint8(v) { this.buffer.writeUInt8(v, this.byteOffset++); }
  writeInt32(v) { this.buffer.writeInt32LE(v, this.byteOffset); this.byteOffset += 4; }
  writeUint32(v) { this.buffer.writeUInt32LE(v, this.byteOffset); this.byteOffset += 4; }
  writeString(s) {
    for (let i = 0; i < s.length; i++) this.writeUint8(s.charCodeAt(i));
    this.writeUint8(0);
  }
}

class Reader {
  constructor(buf) { this.buffer = buf; this.byteOffset = 0; }
  readUint8() { return this.buffer.readUInt8(this.byteOffset++); }
  readUint16() { const v = this.buffer.readUInt16LE(this.byteOffset); this.byteOffset += 2; return v; }
  readInt32() { const v = this.buffer.readInt32LE(this.byteOffset); this.byteOffset += 4; return v; }
  readUint32() { const v = this.buffer.readUInt32LE(this.byteOffset); this.byteOffset += 4; return v; }
  readDouble() { const v = this.buffer.readDoubleLE(this.byteOffset); this.byteOffset += 8; return v; }
  readString() {
    let s = '';
    while (this.byteOffset < this.buffer.length) {
      const c = this.readUint8();
      if (c === 0) break;
      s += String.fromCharCode(c);
    }
    return s;
  }
}

function rotateKey(key) {
  key = Math.imul(key, 1540483477) | 0;
  key = (Math.imul(key >>> 24 ^ key, 1540483477) | 0) ^ 114296087;
  key = Math.imul(key >>> 13 ^ key, 1540483477) | 0;
  return key >>> 15 ^ key;
}

function xorBytes(buffer, key) {
  const out = Buffer.from(buffer);
  for (let i = 0; i < out.byteLength; i++)
    out.writeUInt8(out.readUInt8(i) ^ (key >>> (i % 4 * 8)) & 255, i);
  return out;
}

function lz4Decompress(input, output) {
  for (let i = 0, j = 0; i < input.length;) {
    const byte = input[i++];
    let litLen = byte >> 4;
    if (litLen > 0) {
      let len = litLen + 240;
      while (len === 255) { len = input[i++]; litLen += len; }
      const end = i + litLen;
      while (i < end) output[j++] = input[i++];
      if (i === input.length) return output;
    }
    const offset = input[i++] | (input[i++] << 8);
    if (offset === 0 || offset > j) return null;
    let matchLen = byte & 15;
    let len = matchLen + 240;
    while (len === 255) { len = input[i++]; matchLen += len; }
    let pos = j - offset;
    const end = j + matchLen + 4;
    while (j < end) output[j++] = output[pos++];
  }
  return output;
}

function computeEncryptionKey(serverHost, serverName) {
  const hostnameBytes = Buffer.from(serverHost, 'ascii');
  const nameBytes = Buffer.from(serverName + '\0', 'ascii');
  const s = hostnameBytes.length + nameBytes.length;
  const o = new Uint8Array(s);
  o.set(hostnameBytes, 0);
  o.set(nameBytes, hostnameBytes.length);
  const m = new DataView(o.buffer);
  let r = s - 1;
  const g = (4 + (-4 & (r - 4))) | 0;
  let h = 255 ^ r;
  let f = 0;
  let e = null;
  while (r > 3) {
    e = Math.imul(m.getInt32(f, true), 1540483477) | 0;
    h = (Math.imul(e >>> 24 ^ e, 1540483477) | 0) ^ (Math.imul(h, 1540483477) | 0);
    r -= 4;
    f += 4;
  }
  switch (r) {
    case 3: h = o[g + 2] << 16 ^ h; h = o[g + 1] << 8 ^ h; break;
    case 2: h = o[g + 1] << 8 ^ h; break;
    case 1: break;
    default: e = h; break;
  }
  if (e !== h) e = Math.imul(o[g] ^ h, 1540483477) | 0;
  e ^= e >>> 13;
  e = Math.imul(e, 1540483477) | 0;
  e ^= e >>> 15;
  return e >>> 0;
}

function buildProtocolVersion() {
  const w = new Writer(5);
  w.writeUint8(254);
  w.writeUint32(PROTOCOL_VERSION);
  return w.buffer;
}

function buildClientVersion() {
  const w = new Writer(5);
  w.writeUint8(255);
  w.writeUint32(CLIENT_VERSION);
  return w.buffer;
}

function buildSpawn(name) {
  const w = new Writer(2 + name.length);
  w.writeUint8(0);
  w.writeString(name);
  return w.buffer;
}

function buildMove(x, y, decryptionKey) {
  const w = new Writer(13);
  w.writeUint8(16);
  w.writeInt32(x);
  w.writeInt32(y);
  w.writeInt32(decryptionKey);
  return w.buffer;
}

function buildSplit() {
  const w = new Writer(1);
  w.writeUint8(17);
  return w.buffer;
}

function buildEjectMass() {
  const w = new Writer(1);
  w.writeUint8(21);
  return w.buffer;
}

function parseEntities(reader) {
  const entities = [];
  const eaten = [];
  const removed = [];

  const eatCount = reader.readUint16();
  for (let i = 0; i < eatCount; i++) {
    const eater = reader.readUint32();
    const eaten_id = reader.readUint32();
    eaten.push({ eater, eaten: eaten_id });
  }

  while (reader.byteOffset < reader.buffer.length - 4) {
    const id = reader.readUint32();
    if (id === 0) break;

    const entity = {
      id,
      x: reader.readInt32(),
      y: reader.readInt32(),
      size: reader.readUint16(),
      isVirus: false,
      isPellet: false,
      name: '',
    };

    const flags = reader.readUint8();
    const extFlags = (flags & 128) ? reader.readUint8() : 0;

    if (flags & 1) entity.isVirus = true;
    if (flags & 2) reader.byteOffset += 3;
    if (flags & 4) reader.readString();
    if (flags & 8) entity.name = reader.readString();
    if (extFlags & 1) entity.isPellet = true;
    if (extFlags & 4) reader.byteOffset += 4;

    entities.push(entity);
  }

  if (reader.byteOffset + 2 <= reader.buffer.length) {
    const removeCount = reader.readUint16();
    for (let i = 0; i < removeCount && reader.byteOffset + 4 <= reader.buffer.length; i++) {
      removed.push(reader.readUint32());
    }
  }

  return { entities, eaten, removed };
}

function parseBorders(reader) {
  const left = reader.readDouble();
  const top = reader.readDouble();
  const right = reader.readDouble();
  const bottom = reader.readDouble();
  return { left, top, right, bottom };
}

async function fetchClientVersion() {
  try {
    const https = require('https');
    return new Promise((resolve) => {
      const req = https.get('https://agar.io/mc/agario.js', {
        timeout: 10000,
        rejectUnauthorized: false,
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
          'Referer': 'https://agar.io/',
          'Origin': 'https://agar.io',
        },
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          const match = data.match(/versionString\s*=\s*"([^"]+)"/);
          if (match) {
            const parts = match[1].split('.');
            const version = 10000 * parseInt(parts[0]) + 100 * parseInt(parts[1]) + parseInt(parts[2] || 0);
            CLIENT_VERSION = version;
            console.log(`[Protocol] Fetched client version: ${match[1]} → ${version}`);
          }
          resolve(CLIENT_VERSION);
        });
      });
      req.on('error', () => resolve(CLIENT_VERSION));
      req.on('timeout', () => { req.destroy(); resolve(CLIENT_VERSION); });
    });
  } catch (e) {
    return CLIENT_VERSION;
  }
}

// ─── Bouncer (matchmaker) ──────────────────────────────────────────────────

const BOUNCER_HOST = 'webbouncer-live-v8-0.agario.miniclippt.com';

function buildBouncerRequest(region, gameMode) {
  function writeVarint(buf, value) {
    while (value > 0x7f) { buf.push((value & 0x7f) | 0x80); value >>>= 7; }
    buf.push(value & 0x7f);
  }
  function writeTag(buf, wireType, fieldNum) { writeVarint(buf, (fieldNum << 3) | wireType); }
  function writeStr(buf, str) {
    const enc = Buffer.from(str, 'utf8');
    writeVarint(buf, enc.length);
    for (const b of enc) buf.push(b);
  }
  function writeMsg(buf, fieldNum, fn) {
    writeTag(buf, 2, fieldNum);
    const inner = [];
    fn(inner);
    writeVarint(buf, inner.length);
    for (const b of inner) buf.push(b);
  }

  const buf = [];
  writeMsg(buf, 1, (inner) => {
    writeTag(inner, 2, 1); writeStr(inner, region);
    writeTag(inner, 2, 2); writeStr(inner, gameMode);
  });
  return Buffer.from(buf);
}

const REGION_MAP = {
  'eu-west-2': 'EU-London',
  'eu-west-3': 'EU-London',
  'eu-central-1': 'EU-London',
  'us-east-1': 'US-Atlanta',
  'us-east-2': 'US-Atlanta',
  'us-west-1': 'US-Atlanta',
  'sa-east-1': 'BR-Brazil',
  'ap-northeast-1': 'JP-Tokyo',
  'ap-southeast-1': 'SG-Singapore',
  'me-south-1': 'TK-Turkey',
};

async function findServer(region, gameMode) {
  const https = require('https');
  const bouncerRegion = REGION_MAP[region] || region;
  const body = buildBouncerRequest(bouncerRegion, gameMode || ':ffa');

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: BOUNCER_HOST,
      path: '/v4/findServer',
      method: 'POST',
      rejectUnauthorized: false,
      headers: {
        'Content-Type': 'application/octet-stream',
        'Accept': '*/*',
        'x-support-proto-version': '15.0.3',
        'x-client-version': '' + CLIENT_VERSION,
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        'Origin': 'https://agar.io',
        'Content-Length': body.length,
      },
    }, (res) => {
      let data = [];
      res.on('data', (c) => data.push(c));
      res.on('end', () => {
        const text = Buffer.concat(data).toString();
        try {
          const parsed = JSON.parse(text);
          if (parsed.status === 'ok' && parsed.endpoints) {
            const server = parsed.endpoints.https || parsed.endpoints.http;
            if (server && server !== '0.0.0.0:0') {
              console.log(`[Bouncer] Found server: ${server} (region: ${bouncerRegion})`);
              resolve({ server, token: parsed.token || null });
            } else {
              reject(new Error('Bouncer returned empty server'));
            }
          } else {
            reject(new Error(`Bouncer error: ${text.slice(0, 200)}`));
          }
        } catch (e) {
          reject(new Error(`Bouncer parse error: ${text.slice(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(); reject(new Error('Bouncer timeout')); });
    req.write(body);
    req.end();
  });
}

module.exports = {
  PROTOCOL_VERSION,
  get CLIENT_VERSION() { return CLIENT_VERSION; },
  Writer,
  Reader,
  rotateKey,
  xorBytes,
  lz4Decompress,
  computeEncryptionKey,
  buildProtocolVersion,
  buildClientVersion,
  buildSpawn,
  buildMove,
  buildSplit,
  buildEjectMass,
  parseEntities,
  parseBorders,
  fetchClientVersion,
  findServer,
  BOUNCER_HOST,
  REGION_MAP,
};
