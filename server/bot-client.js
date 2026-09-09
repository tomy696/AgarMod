'use strict';

const WebSocket = require('ws');
const EventEmitter = require('events');
const proto = require('./protocol');

let SocksProxyAgent, HttpsProxyAgent;
try { SocksProxyAgent = require('socks-proxy-agent').SocksProxyAgent; } catch (_) {}
try { HttpsProxyAgent = require('https-proxy-agent').HttpsProxyAgent; } catch (_) {}

const BOT_STATES = {
  DISCONNECTED: 'disconnected',
  CONNECTING: 'connecting',
  HANDSHAKE: 'handshake',
  ENCRYPTED: 'encrypted',
  SPAWNING: 'spawning',
  IN_GAME: 'in_game',
  DEAD: 'dead',
};

class BotClient extends EventEmitter {
  constructor(config) {
    super();
    this.id = config.id;
    this.name = config.name || `Bot_${config.id}`;
    this.partyCode = config.partyCode || null;

    this.ws = null;
    this.state = BOT_STATES.DISCONNECTED;
    this.serverIP = null;
    this.serverUrl = null;

    this.encryptionKey = 0;
    this.decryptionKey = 0;
    this.cellsIDs = [];
    this.isAlive = false;
    this.entities = {};
    this.offsetX = 0;
    this.offsetY = 0;

    this.targetX = 0;
    this.targetY = 0;
    this.mode = 'follow';

    this._moveInterval = null;
    this._respawnTimeout = null;
    this._spawnDelay = null;
  }

  connect(serverIP, proxy) {
    if (this.state !== BOT_STATES.DISCONNECTED) this.disconnect();

    this.serverIP = serverIP;
    this.state = BOT_STATES.CONNECTING;

    this.encryptionKey = 0;
    this.decryptionKey = 0;
    this.cellsIDs = [];
    this.isAlive = false;
    this.entities = {};
    this.offsetX = 0;
    this.offsetY = 0;

    let url = serverIP.startsWith('ws://') || serverIP.startsWith('wss://')
      ? serverIP
      : `wss://${serverIP}`;

    if (this.partyCode && !url.includes('party_id=')) {
      url += (url.includes('?') ? '&' : '?') + `party_id=${this.partyCode}`;
    }

    this.serverUrl = url;

    const via = proxy ? ` via proxy` : ' (direct)';
    console.log(`[Bot ${this.id}] Connecting to ${url}${via}`);

    try {
      const wsOpts = {
        headers: {
          'Origin': 'https://agar.io',
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        },
        rejectUnauthorized: false,
        handshakeTimeout: 15000,
      };

      if (proxy) {
        const isSocks = proxy.type === 'socks5' || proxy.type === 'socks4' || proxy.url.startsWith('socks');
        if (isSocks && SocksProxyAgent) {
          wsOpts.agent = new SocksProxyAgent(proxy.url);
        } else if (HttpsProxyAgent) {
          wsOpts.agent = new HttpsProxyAgent(proxy.url);
        }
      }

      this.ws = new WebSocket(url, wsOpts);
      this.ws.binaryType = 'nodebuffer';

      this.ws.on('open', () => this._onOpen());
      this.ws.on('message', (data) => this._onMessage(data));
      this.ws.on('close', (code, reason) => this._onClose(code, reason));
      this.ws.on('error', (err) => this._onError(err));
    } catch (err) {
      console.error(`[Bot ${this.id}] Connection error:`, err.message);
      this.state = BOT_STATES.DISCONNECTED;
      this.emit('error', err);
    }
  }

  disconnect() {
    this._clearTimers();
    if (this.ws) {
      try { this.ws.close(); } catch (_) {}
      this.ws = null;
    }
    this.state = BOT_STATES.DISCONNECTED;
    this.isAlive = false;
    this.cellsIDs = [];
    this.emit('disconnected');
  }

  _send(buf, encrypt = false) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    try {
      if (encrypt && this.encryptionKey) {
        buf = proto.xorBytes(Buffer.from(buf), this.encryptionKey);
        this.encryptionKey = proto.rotateKey(this.encryptionKey);
      }
      this.ws.send(buf);
    } catch (err) {
      console.error(`[Bot ${this.id}] Send error:`, err.message);
    }
  }

  // ---- WebSocket handlers ----

  _onOpen() {
    console.log(`[Bot ${this.id}] WebSocket open, sending handshake`);
    this.state = BOT_STATES.HANDSHAKE;
    this.emit('connected');

    this._send(proto.buildProtocolVersion());
    this._send(proto.buildClientVersion());
  }

  _onMessage(data) {
    let buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);

    if (this.decryptionKey) {
      buffer = proto.xorBytes(Buffer.from(buffer), this.decryptionKey ^ proto.CLIENT_VERSION);
    }

    if (buffer.length < 1) return;
    const opcode = buffer.readUInt8(0);

    switch (opcode) {
      case 241: this._handleEncryptionSetup(buffer); break;
      case 242: this._handleSpawnRequest(); break;
      case 32:  this._handleSpawnConfirm(buffer); break;
      case 85:  this._handleCaptchaFail(); break;
      case 255: this._handleCompressedData(buffer); break;
      case 54:  break; // leaderboard
      default:  break;
    }
  }

  _onClose(code, reason) {
    console.log(`[Bot ${this.id}] WebSocket closed: ${code}`);
    this._clearTimers();
    this.ws = null;
    this.state = BOT_STATES.DISCONNECTED;
    this.isAlive = false;
    this.cellsIDs = [];
    this.emit('disconnected', { code, reason: reason ? reason.toString() : '' });
  }

  _onError(err) {
    console.error(`[Bot ${this.id}] WS error:`, err.message);
    this.emit('error', err);
  }

  // ---- Protocol 22 handlers ----

  _handleEncryptionSetup(buffer) {
    const reader = new proto.Reader(buffer);
    reader.readUint8(); // opcode 241

    this.decryptionKey = reader.readInt32();

    const serverName = reader.readString();

    const hostname = this.serverUrl
      .replace(/^wss?:\/\//, '')
      .split(':')[0]
      .split('?')[0]
      .split('/')[0];

    this.encryptionKey = proto.computeEncryptionKey(hostname, serverName);
    this.state = BOT_STATES.ENCRYPTED;

    console.log(`[Bot ${this.id}] Encryption established (host: ${hostname})`);
  }

  _handleSpawnRequest() {
    console.log(`[Bot ${this.id}] Server ready, spawning as "${this.name}"`);
    this.state = BOT_STATES.SPAWNING;
    this._spawnDelay = setTimeout(() => {
      this._send(proto.buildSpawn(this.name), true);
    }, 500 + Math.random() * 1000);
  }

  _handleSpawnConfirm(buffer) {
    const reader = new proto.Reader(buffer);
    reader.readUint8(); // opcode 32
    const cellId = reader.readUint32();
    this.cellsIDs.push(cellId);
    this.isAlive = true;
    this.state = BOT_STATES.IN_GAME;

    console.log(`[Bot ${this.id}] Spawned! cellId=${cellId}`);
    this.emit('gameJoined');
    this._startMoveLoop();
  }

  _handleCaptchaFail() {
    console.log(`[Bot ${this.id}] Captcha required, disconnecting`);
    this.disconnect();
  }

  _handleCompressedData(buffer) {
    if (buffer.length < 5) return;
    const uncompSize = buffer.readUInt32LE(1);
    const compressed = buffer.slice(5);

    const decompressed = proto.lz4Decompress(
      new Uint8Array(compressed),
      new Uint8Array(uncompSize)
    );

    if (!decompressed || !(decompressed instanceof Uint8Array)) return;
    const decBuf = Buffer.from(decompressed.buffer, decompressed.byteOffset, decompressed.byteLength);
    if (decBuf.length < 1) return;

    const subOpcode = decBuf.readUInt8(0);
    const reader = new proto.Reader(decBuf);
    reader.readUint8(); // skip sub-opcode

    switch (subOpcode) {
      case 16: this._parseEntities(reader); break;
      case 64: this._parseBorders(reader); break;
    }
  }

  _parseEntities(reader) {
    try {
      const eatCount = reader.readUint16();
      for (let i = 0; i < eatCount; i++) {
        reader.byteOffset += 8;
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

        this.entities[id] = entity;
      }

      if (reader.byteOffset + 2 <= reader.buffer.length) {
        const removeCount = reader.readUint16();
        for (let i = 0; i < removeCount && reader.byteOffset + 4 <= reader.buffer.length; i++) {
          const id = reader.readUint32();
          delete this.entities[id];
          const idx = this.cellsIDs.indexOf(id);
          if (idx !== -1) this.cellsIDs.splice(idx, 1);
        }
      }

      if (this.isAlive && this.cellsIDs.length === 0) {
        console.log(`[Bot ${this.id}] Died, respawning in 3s`);
        this.isAlive = false;
        this.state = BOT_STATES.DEAD;
        this.emit('gameOver');
        this._respawnTimeout = setTimeout(() => {
          if (this.ws && this.ws.readyState === WebSocket.OPEN && this.encryptionKey) {
            this._send(proto.buildSpawn(this.name), true);
          }
        }, 3000 + Math.random() * 2000);
      }
    } catch (e) {
      // malformed packet, ignore
    }
  }

  _parseBorders(reader) {
    try {
      const left = reader.readDouble();
      const top = reader.readDouble();
      const right = reader.readDouble();
      const bottom = reader.readDouble();
      if (~~(right - left) === 14142 && ~~(bottom - top) === 14142) {
        this.offsetX = (left + right) / 2;
        this.offsetY = (top + bottom) / 2;
      }
    } catch (_) {}
  }

  // ---- Actions ----

  sendDirection(x, y) {
    if (!this.isAlive || !this.encryptionKey) return;
    this._send(proto.buildMove(
      Math.round(x + this.offsetX),
      Math.round(y + this.offsetY),
      this.decryptionKey
    ), true);
  }

  sendSplit() {
    if (!this.isAlive || !this.encryptionKey) return;
    this._send(proto.buildSplit(), true);
  }

  sendShootMass() {
    if (!this.isAlive || !this.encryptionKey) return;
    this._send(proto.buildEjectMass(), true);
  }

  updateTarget(x, y) {
    this.targetX = x;
    this.targetY = y;
  }

  setMode(mode) {
    this.mode = mode;
  }

  // ---- Movement loop ----

  _startMoveLoop() {
    if (this._moveInterval) clearInterval(this._moveInterval);
    this._moveInterval = setInterval(() => {
      if (!this.isAlive) return;
      this._executeBehavior();
    }, 40);
  }

  _executeBehavior() {
    switch (this.mode) {
      case 'follow': this._behaviorFollow(); break;
      case 'feed':   this._behaviorFeed(); break;
      case 'teamer': this._behaviorTeamer(); break;
      case 'ai':     this._behaviorAI(); break;
      case 'random': this._behaviorRandom(); break;
      default:       this._behaviorFollow(); break;
    }
  }

  _behaviorFollow() {
    this.sendDirection(this.targetX, this.targetY);
  }

  _behaviorFeed() {
    const center = this._getCenter();
    const dist = this._distance(center.x, center.y, this.targetX, this.targetY);
    this.sendDirection(this.targetX, this.targetY);
    if (dist < 300) this.sendShootMass();
  }

  _behaviorTeamer() {
    const center = this._getCenter();
    const totalMass = this._getTotalMass();
    const dToPlayer = this._distance(center.x, center.y, this.targetX, this.targetY);

    let nearestThreat = null;
    let nearestThreatDist = Infinity;
    for (const id in this.entities) {
      const e = this.entities[id];
      if (e.isPellet || e.isVirus) continue;
      if (this.cellsIDs.includes(e.id)) continue;
      const eMass = e.size * e.size / 100;
      const dToTarget = this._distance(this.targetX, this.targetY, e.x - this.offsetX, e.y - this.offsetY);
      if (dToTarget < 1500) {
        const dToSelf = this._distance(center.x, center.y, e.x - this.offsetX, e.y - this.offsetY);
        if (totalMass > eMass * 2.5 && dToSelf < nearestThreatDist) {
          nearestThreatDist = dToSelf;
          nearestThreat = e;
        }
      }
    }

    if (nearestThreat && nearestThreatDist < 700 && this.cellsIDs.length < 4) {
      this.sendDirection(nearestThreat.x - this.offsetX, nearestThreat.y - this.offsetY);
      this.sendSplit();
    } else if (dToPlayer > 400) {
      this.sendDirection(this.targetX, this.targetY);
    } else if (dToPlayer < 300 && totalMass > 50) {
      this.sendDirection(this.targetX, this.targetY);
      this.sendShootMass();
    } else {
      this.sendDirection(this.targetX, this.targetY);
    }
  }

  _behaviorAI() {
    const center = this._getCenter();
    const totalMass = this._getTotalMass();

    let nearestFood = null;
    let nearestFoodDist = Infinity;
    let nearestDanger = null;
    let nearestDangerDist = Infinity;

    for (const id in this.entities) {
      const e = this.entities[id];
      const ex = e.x - this.offsetX;
      const ey = e.y - this.offsetY;
      const d = this._distance(center.x, center.y, ex, ey);

      if (e.isPellet) {
        if (d < nearestFoodDist) { nearestFoodDist = d; nearestFood = e; }
      } else if (!e.isVirus && !this.cellsIDs.includes(e.id)) {
        const eMass = e.size * e.size / 100;
        if (eMass > totalMass * 1.25 && d < 420 && d < nearestDangerDist) {
          nearestDangerDist = d; nearestDanger = e;
        }
      }
    }

    if (nearestDanger) {
      const dx = center.x - (nearestDanger.x - this.offsetX);
      const dy = center.y - (nearestDanger.y - this.offsetY);
      this.sendDirection(center.x + dx * 3, center.y + dy * 3);
    } else if (nearestFood) {
      this.sendDirection(nearestFood.x - this.offsetX, nearestFood.y - this.offsetY);
    } else {
      this._behaviorRandom();
    }
  }

  _behaviorRandom() {
    if (!this._randomTarget || Math.random() < 0.02) {
      this._randomTarget = {
        x: (Math.random() - 0.5) * 14000,
        y: (Math.random() - 0.5) * 14000,
      };
    }
    this.sendDirection(this._randomTarget.x, this._randomTarget.y);
  }

  // ---- Helpers ----

  _getCenter() {
    if (this.cellsIDs.length === 0) return { x: 0, y: 0 };
    let tx = 0, ty = 0, count = 0;
    for (const cid of this.cellsIDs) {
      const e = this.entities[cid];
      if (e) {
        tx += e.x - this.offsetX;
        ty += e.y - this.offsetY;
        count++;
      }
    }
    return count > 0 ? { x: tx / count, y: ty / count } : { x: 0, y: 0 };
  }

  _getTotalMass() {
    let total = 0;
    for (const cid of this.cellsIDs) {
      const e = this.entities[cid];
      if (e) total += Math.floor(e.size * e.size / 100);
    }
    return total;
  }

  _distance(x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    return Math.sqrt(dx * dx + dy * dy);
  }

  _clearTimers() {
    if (this._moveInterval) { clearInterval(this._moveInterval); this._moveInterval = null; }
    if (this._respawnTimeout) { clearTimeout(this._respawnTimeout); this._respawnTimeout = null; }
    if (this._spawnDelay) { clearTimeout(this._spawnDelay); this._spawnDelay = null; }
  }

  getStatus() {
    return {
      id: this.id,
      name: this.name,
      state: this.state,
      mode: this.mode,
      cells: this.cellsIDs.length,
      mass: this._getTotalMass(),
      position: this._getCenter(),
    };
  }
}

module.exports = BotClient;
module.exports.BOT_STATES = BOT_STATES;
