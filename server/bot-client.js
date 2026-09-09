'use strict';

const WebSocket = require('ws');
const EventEmitter = require('events');
const proto = require('./protocol');

let SocksProxyAgent, HttpsProxyAgent;
try { SocksProxyAgent = require('socks-proxy-agent').SocksProxyAgent; } catch (_) {}
try { HttpsProxyAgent = require('https-proxy-agent').HttpsProxyAgent; } catch (_) {}

// =============================================================================
// bot-client.js - Headless Agar.io WebSocket bot client
// =============================================================================

const BOT_STATES = {
  DISCONNECTED: 'disconnected',
  CONNECTING: 'connecting',
  CONNECTED: 'connected',
  LOGGING_IN: 'logging_in',
  IN_GAME: 'in_game',
  DEAD: 'dead',
};

class BotClient extends EventEmitter {
  /**
   * @param {object} config
   * @param {string} config.name - Bot display name
   * @param {number} config.id - Bot instance ID
   * @param {string} [config.partyCode] - Party code to join
   */
  constructor(config) {
    super();
    this.id = config.id;
    this.name = config.name || `Bot_${config.id}`;
    this.partyCode = config.partyCode || null;

    // Connection state
    this.ws = null;
    this.state = BOT_STATES.DISCONNECTED;
    this.serverIP = null;

    // Game state
    this.playerId = null;
    this.ownCells = new Map();    // cellId -> { x, y, radius, mass }
    this.visibleCells = new Map(); // cellId -> { x, y, radius, ownerId, name, isVirus, isFood, isEjected }
    this.arenaWidth = 14142;
    this.arenaHeight = 14142;

    // Target tracking
    this.targetX = 0;
    this.targetY = 0;

    // Bot behavior
    this.mode = 'move';
    this._directionInterval = null;
    this._behaviorInterval = null;
    this._pingInterval = null;
    this._reconnectTimeout = null;
    this._respawnTimeout = null;
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /**
   * Connect to an Agar.io game server, optionally through a proxy.
   * @param {string} serverIP - Server IP:port (e.g., "123.45.67.89:443")
   * @param {{ url: string, type: string }|null} [proxy] - SOCKS5/HTTP proxy
   */
  connect(serverIP, proxy) {
    if (this.state !== BOT_STATES.DISCONNECTED) {
      this.disconnect();
    }

    this.serverIP = serverIP;
    this.proxyUrl = proxy ? proxy.url : null;
    this.state = BOT_STATES.CONNECTING;

    const url = serverIP.startsWith('ws://') || serverIP.startsWith('wss://')
      ? serverIP
      : `wss://${serverIP}`;

    const via = proxy ? ` via ${proxy.url.replace(/\/\/.*@/, '//*:*@')}` : ' (direct)';
    console.log(`[Bot ${this.id}] Connecting to ${url}${via}`);

    try {
      const wsOpts = {
        headers: {
          'Origin': 'https://agar.io',
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        },
        rejectUnauthorized: false,
        handshakeTimeout: 10000,
      };

      // Route through proxy if provided
      if (proxy) {
        const isSocks = proxy.type === 'socks5' || proxy.type === 'socks4' ||
                        proxy.url.startsWith('socks');
        if (isSocks && SocksProxyAgent) {
          wsOpts.agent = new SocksProxyAgent(proxy.url);
        } else if (HttpsProxyAgent) {
          wsOpts.agent = new HttpsProxyAgent(proxy.url);
        }
      }

      this.ws = new WebSocket(url, wsOpts);
      this.ws.binaryType = 'arraybuffer';

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

  /**
   * Disconnect from the server.
   */
  disconnect() {
    this._clearIntervals();

    if (this.ws) {
      try {
        if (this.ws.readyState === WebSocket.OPEN) {
          const msg = proto.buildDisconnect();
          this.ws.send(msg);
        }
        this.ws.close();
      } catch (e) {
        // ignore close errors
      }
      this.ws = null;
    }

    this.state = BOT_STATES.DISCONNECTED;
    this.ownCells.clear();
    this.visibleCells.clear();
    this.playerId = null;
    this.emit('disconnected');
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Send a direction vector to move the bot.
   * @param {number} x - Target X coordinate in arena space.
   * @param {number} y - Target Y coordinate in arena space.
   */
  sendDirection(x, y) {
    if (this.state !== BOT_STATES.IN_GAME || !this.ws) return;

    // Compute direction vector from bot center to target
    const center = this._getCenter();
    const dx = x - center.x;
    const dy = y - center.y;
    const dist = Math.sqrt(dx * dx + dy * dy);

    let nx = 0;
    let ny = 0;
    if (dist > 1) {
      nx = dx / dist;
      ny = dy / dist;
    }

    this._send(proto.buildDirectionVector(nx, ny));
  }

  /**
   * Send a split action.
   */
  sendSplit() {
    if (this.state !== BOT_STATES.IN_GAME || !this.ws) return;
    this._send(proto.buildPlayerSplit());
  }

  /**
   * Send a shoot-mass (eject/feed) action.
   */
  sendShootMass() {
    if (this.state !== BOT_STATES.IN_GAME || !this.ws) return;
    this._send(proto.buildShootMass());
  }

  /**
   * Update the movement target coordinates.
   * @param {number} x
   * @param {number} y
   */
  updateTarget(x, y) {
    this.targetX = x;
    this.targetY = y;
  }

  /**
   * Set the bot behavior mode.
   * @param {string} mode - "move"|"feed"|"farm"|"makevirus"|"breakvirus"|"teamer"
   */
  setMode(mode) {
    this.mode = mode;
    this._restartBehavior();
  }

  // ---------------------------------------------------------------------------
  // WebSocket event handlers
  // ---------------------------------------------------------------------------

  _onOpen() {
    console.log(`[Bot ${this.id}] WebSocket connected`);
    this.state = BOT_STATES.CONNECTED;
    this.emit('connected');

    // Send login/connect handshake
    this._send(proto.buildLoginRequestV5(this.name));
    this.state = BOT_STATES.LOGGING_IN;

    // Start ping keepalive
    this._pingInterval = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this._send(proto.buildPing());
      }
    }, 5000);
  }

  _onMessage(data) {
    const buf = Buffer.from(data);
    const msg = proto.parseServerMessage(buf);
    if (!msg) return;

    switch (msg.type) {
      case proto.REQ_TYPE.LOGIN_RESPONSE:
        this._handleLoginResponse(msg.fields);
        break;
      case proto.REQ_TYPE.CONNECT_RESPONSE:
        this._handleConnectResponse(msg.fields);
        break;
      case proto.REQ_TYPE.GAME_ENTER_RESPONSE:
        this._handleGameEnterResponse(msg.fields);
        break;
      case proto.REQ_TYPE.GAME_JOINED:
        this._handleGameJoined(msg.fields);
        break;
      case proto.REQ_TYPE.GAME_ARENA_STATE:
        this._handleArenaState(msg.fields);
        break;
      case proto.REQ_TYPE.GAME_ARENA_LEADERBOARD:
        this._handleLeaderboard(msg.fields);
        break;
      case proto.REQ_TYPE.PONG:
        // Keepalive response, nothing to do
        break;
      case proto.REQ_TYPE.GAME_OVER:
        this._handleGameOver();
        break;
      case proto.REQ_TYPE.DISCONNECT:
        console.log(`[Bot ${this.id}] Server sent disconnect`);
        this.disconnect();
        break;
      case proto.REQ_TYPE.SERVER_GOING_OFFLINE:
        console.log(`[Bot ${this.id}] Server going offline`);
        this.disconnect();
        break;
      default:
        // Unhandled message type
        break;
    }
  }

  _onClose(code, reason) {
    console.log(`[Bot ${this.id}] WebSocket closed: ${code} ${reason || ''}`);
    this._clearIntervals();
    this.ws = null;
    const wasInGame = this.state === BOT_STATES.IN_GAME;
    this.state = BOT_STATES.DISCONNECTED;
    this.ownCells.clear();
    this.visibleCells.clear();
    this.emit('disconnected', { code, reason: reason ? reason.toString() : '', wasInGame });
  }

  _onError(err) {
    console.error(`[Bot ${this.id}] WebSocket error:`, err.message);
    this.emit('error', err);
  }

  // ---------------------------------------------------------------------------
  // Message handlers
  // ---------------------------------------------------------------------------

  _handleLoginResponse(fields) {
    const result = proto.parseLoginResponse(fields);
    console.log(`[Bot ${this.id}] Login response: success=${result.success}`);
    if (result.success) {
      // Send connect request
      this._send(proto.buildConnectRequest());
    }
  }

  _handleConnectResponse(fields) {
    const result = proto.parseConnectResponse(fields);
    console.log(`[Bot ${this.id}] Connect response: success=${result.success}`);
    if (result.success) {
      // Send game enter request
      this._send(proto.buildGameEnterRequest(this.name, null, this.partyCode));
    }
  }

  _handleGameEnterResponse(fields) {
    const result = proto.parseGameEnterResponse(fields);
    console.log(`[Bot ${this.id}] Game enter response: success=${result.success}, playerId=${result.playerId}`);
    if (result.success) {
      this.playerId = result.playerId;
    }
  }

  _handleGameJoined(fields) {
    const result = proto.parseGameJoined(fields);
    console.log(`[Bot ${this.id}] Game joined: arena=${result.arenaId}, size=${result.arenaWidth}x${result.arenaHeight}`);
    this.arenaWidth = result.arenaWidth;
    this.arenaHeight = result.arenaHeight;
    this.state = BOT_STATES.IN_GAME;
    this.emit('gameJoined', result);
    this._startBehavior();
  }

  _handleArenaState(fields) {
    const result = proto.parseGameArenaState(fields);

    // Update visible cells
    for (const cell of result.cells) {
      this.visibleCells.set(cell.id, cell);

      // Track own cells
      if (this.playerId && cell.ownerId === this.playerId) {
        this.ownCells.set(cell.id, {
          x: cell.x,
          y: cell.y,
          radius: cell.radius,
          mass: Math.floor(cell.radius * cell.radius / 100),
        });
      }
    }

    // Remove dead/disappeared cells
    for (const deadId of result.deaths) {
      this.visibleCells.delete(deadId);
      this.ownCells.delete(deadId);
    }

    // If all own cells are gone, we died
    if (this.state === BOT_STATES.IN_GAME && this.playerId && this.ownCells.size === 0) {
      // Check if we actually had cells before (avoid false trigger on first update)
      // The game_over message handles the official death, but this catches edge cases
    }

    this.emit('arenaState', result);
  }

  _handleLeaderboard(fields) {
    const result = proto.parseLeaderboard(fields);
    this.emit('leaderboard', result);
  }

  _handleGameOver() {
    console.log(`[Bot ${this.id}] Game over`);
    this.state = BOT_STATES.DEAD;
    this.ownCells.clear();
    this.emit('gameOver');

    // Auto-respawn after a delay
    this._respawnTimeout = setTimeout(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        console.log(`[Bot ${this.id}] Respawning`);
        this.state = BOT_STATES.CONNECTED;
        this._send(proto.buildGameEnterRequest(this.name, null, this.partyCode));
      }
    }, 2000 + Math.random() * 3000);
  }

  // ---------------------------------------------------------------------------
  // Bot behaviors
  // ---------------------------------------------------------------------------

  _startBehavior() {
    this._clearBehaviorIntervals();

    // Direction update loop (every 50ms as specified)
    this._directionInterval = setInterval(() => {
      if (this.state !== BOT_STATES.IN_GAME) return;
      this._executeBehavior();
    }, 50);
  }

  _restartBehavior() {
    if (this.state === BOT_STATES.IN_GAME) {
      this._startBehavior();
    }
  }

  _executeBehavior() {
    switch (this.mode) {
      case 'move':
        this._behaviorMove();
        break;
      case 'feed':
        this._behaviorFeed();
        break;
      case 'farm':
        this._behaviorFarm();
        break;
      case 'makevirus':
        this._behaviorMakeVirus();
        break;
      case 'breakvirus':
        this._behaviorBreakVirus();
        break;
      case 'teamer':
        this._behaviorTeamer();
        break;
      default:
        this._behaviorMove();
        break;
    }
  }

  /**
   * MOVE mode: Follow target coordinates (sent by the player's tweak).
   */
  _behaviorMove() {
    this.sendDirection(this.targetX, this.targetY);
  }

  /**
   * FEED mode: Move near the player's target position, then repeatedly eject mass.
   */
  _behaviorFeed() {
    const center = this._getCenter();
    const dx = this.targetX - center.x;
    const dy = this.targetY - center.y;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // Move toward target
    this.sendDirection(this.targetX, this.targetY);

    // If close enough, start feeding (ejecting mass)
    if (dist < 300) {
      this.sendShootMass();
    }
  }

  /**
   * FARM mode: Wander randomly, eat food pellets, split on smaller cells.
   */
  _behaviorFarm() {
    const center = this._getCenter();
    const totalMass = this._getTotalMass();

    // Find nearest food
    let nearestFood = null;
    let nearestFoodDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isFood || cell.isEjected) {
        const d = this._distance(center.x, center.y, cell.x, cell.y);
        if (d < nearestFoodDist) {
          nearestFoodDist = d;
          nearestFood = cell;
        }
      }
    }

    // Find smaller enemies to split-kill
    let splitTarget = null;
    let splitTargetDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isFood || cell.isVirus || cell.isEjected) continue;
      if (cell.ownerId === this.playerId) continue;
      const cellMass = cell.radius * cell.radius / 100;
      // Can eat if our mass > 1.25x theirs, and split-kill range
      if (totalMass > cellMass * 2.5 && cellMass > 10) {
        const d = this._distance(center.x, center.y, cell.x, cell.y);
        if (d < splitTargetDist && d < 800) {
          splitTargetDist = d;
          splitTarget = cell;
        }
      }
    }

    // Avoid viruses
    let avoidX = 0;
    let avoidY = 0;
    for (const [, cell] of this.visibleCells) {
      if (cell.isVirus && totalMass > 150) {
        const d = this._distance(center.x, center.y, cell.x, cell.y);
        if (d < 300) {
          avoidX += (center.x - cell.x) * 2;
          avoidY += (center.y - cell.y) * 2;
        }
      }
    }

    if (splitTarget && this.ownCells.size < 8) {
      // Split-kill smaller cells
      this.sendDirection(splitTarget.x, splitTarget.y);
      if (splitTargetDist < 500) {
        this.sendSplit();
      }
    } else if (nearestFood) {
      // Eat food
      this.sendDirection(
        nearestFood.x + avoidX,
        nearestFood.y + avoidY
      );
    } else {
      // Wander randomly
      const wanderX = center.x + (Math.random() - 0.5) * 2000 + avoidX;
      const wanderY = center.y + (Math.random() - 0.5) * 2000 + avoidY;
      this.sendDirection(
        Math.max(0, Math.min(this.arenaWidth, wanderX)),
        Math.max(0, Math.min(this.arenaHeight, wanderY))
      );
    }
  }

  /**
   * MAKEVIRUS mode: Find viruses and feed them toward enemies.
   */
  _behaviorMakeVirus() {
    const center = this._getCenter();

    // Find nearest virus
    let nearestVirus = null;
    let nearestVirusDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isVirus) {
        const d = this._distance(center.x, center.y, cell.x, cell.y);
        if (d < nearestVirusDist) {
          nearestVirusDist = d;
          nearestVirus = cell;
        }
      }
    }

    // Find nearest enemy (to aim the virus toward)
    let nearestEnemy = null;
    let nearestEnemyDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isFood || cell.isVirus || cell.isEjected) continue;
      if (cell.ownerId === this.playerId) continue;
      const d = this._distance(center.x, center.y, cell.x, cell.y);
      if (d < nearestEnemyDist) {
        nearestEnemyDist = d;
        nearestEnemy = cell;
      }
    }

    if (nearestVirus && nearestEnemy) {
      // Position between virus and enemy, then feed virus
      const virusToEnemyX = nearestEnemy.x - nearestVirus.x;
      const virusToEnemyY = nearestEnemy.y - nearestVirus.y;
      const dist = Math.sqrt(virusToEnemyX * virusToEnemyX + virusToEnemyY * virusToEnemyY);

      if (dist > 0) {
        // Move behind the virus (opposite side from enemy)
        const behindX = nearestVirus.x - (virusToEnemyX / dist) * 200;
        const behindY = nearestVirus.y - (virusToEnemyY / dist) * 200;

        const dToPos = this._distance(center.x, center.y, behindX, behindY);
        if (dToPos > 100) {
          this.sendDirection(behindX, behindY);
        } else {
          // In position, aim at virus and feed
          this.sendDirection(nearestVirus.x, nearestVirus.y);
          this.sendShootMass();
        }
      }
    } else if (nearestVirus) {
      // No enemy visible, move near virus
      this.sendDirection(nearestVirus.x, nearestVirus.y);
    } else {
      // No virus found, wander
      this.sendDirection(this.targetX, this.targetY);
    }
  }

  /**
   * BREAKVIRUS mode: Find viruses near the player and pop them by shooting mass.
   */
  _behaviorBreakVirus() {
    const center = this._getCenter();

    // Find nearest virus near the target/player position
    let nearestVirus = null;
    let nearestVirusDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isVirus) {
        const dToTarget = this._distance(this.targetX, this.targetY, cell.x, cell.y);
        if (dToTarget < 1000) {
          const dToSelf = this._distance(center.x, center.y, cell.x, cell.y);
          if (dToSelf < nearestVirusDist) {
            nearestVirusDist = dToSelf;
            nearestVirus = cell;
          }
        }
      }
    }

    if (nearestVirus) {
      if (nearestVirusDist > 200) {
        // Move toward the virus
        this.sendDirection(nearestVirus.x, nearestVirus.y);
      } else {
        // Close enough, feed into it to pop it
        this.sendDirection(nearestVirus.x, nearestVirus.y);
        this.sendShootMass();
      }
    } else {
      // No virus near player, follow player
      this.sendDirection(this.targetX, this.targetY);
    }
  }

  /**
   * TEAMER mode: Follow player closely, feed mass to player, split-kill
   * enemies near player.
   */
  _behaviorTeamer() {
    const center = this._getCenter();
    const totalMass = this._getTotalMass();

    // Follow the player (target position)
    const dToPlayer = this._distance(center.x, center.y, this.targetX, this.targetY);

    // Find enemies near the player
    let nearestThreat = null;
    let nearestThreatDist = Infinity;
    for (const [, cell] of this.visibleCells) {
      if (cell.isFood || cell.isVirus || cell.isEjected) continue;
      if (cell.ownerId === this.playerId) continue;
      const cellMass = cell.radius * cell.radius / 100;
      const dToTarget = this._distance(this.targetX, this.targetY, cell.x, cell.y);
      if (dToTarget < 1500) {
        const dToSelf = this._distance(center.x, center.y, cell.x, cell.y);
        // Can split-kill if we're big enough
        if (totalMass > cellMass * 2.5 && dToSelf < nearestThreatDist) {
          nearestThreatDist = dToSelf;
          nearestThreat = cell;
        }
      }
    }

    if (nearestThreat && nearestThreatDist < 700 && this.ownCells.size < 4) {
      // Split-kill enemy near player
      this.sendDirection(nearestThreat.x, nearestThreat.y);
      this.sendSplit();
    } else if (dToPlayer > 400) {
      // Follow player closely
      this.sendDirection(this.targetX, this.targetY);
    } else if (dToPlayer < 300) {
      // Close to player, feed mass
      this.sendDirection(this.targetX, this.targetY);
      if (totalMass > 50) {
        this.sendShootMass();
      }
    } else {
      // Stay near player
      this.sendDirection(this.targetX, this.targetY);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /**
   * Get the center position of all own cells (mass-weighted).
   * @returns {{ x: number, y: number }}
   */
  _getCenter() {
    if (this.ownCells.size === 0) {
      return { x: this.arenaWidth / 2, y: this.arenaHeight / 2 };
    }
    let totalX = 0;
    let totalY = 0;
    let totalMass = 0;
    for (const [, cell] of this.ownCells) {
      const mass = cell.mass || 1;
      totalX += cell.x * mass;
      totalY += cell.y * mass;
      totalMass += mass;
    }
    return {
      x: totalX / totalMass,
      y: totalY / totalMass,
    };
  }

  /**
   * Get the total mass across all own cells.
   * @returns {number}
   */
  _getTotalMass() {
    let total = 0;
    for (const [, cell] of this.ownCells) {
      total += cell.mass || 0;
    }
    return total;
  }

  /**
   * Euclidean distance between two points.
   * @param {number} x1
   * @param {number} y1
   * @param {number} x2
   * @param {number} y2
   * @returns {number}
   */
  _distance(x1, y1, x2, y2) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    return Math.sqrt(dx * dx + dy * dy);
  }

  /**
   * Send a binary buffer over the WebSocket.
   * @param {Buffer} buf
   */
  _send(buf) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        this.ws.send(buf);
      } catch (err) {
        console.error(`[Bot ${this.id}] Send error:`, err.message);
      }
    }
  }

  _clearBehaviorIntervals() {
    if (this._directionInterval) {
      clearInterval(this._directionInterval);
      this._directionInterval = null;
    }
    if (this._behaviorInterval) {
      clearInterval(this._behaviorInterval);
      this._behaviorInterval = null;
    }
  }

  _clearIntervals() {
    this._clearBehaviorIntervals();
    if (this._pingInterval) {
      clearInterval(this._pingInterval);
      this._pingInterval = null;
    }
    if (this._reconnectTimeout) {
      clearTimeout(this._reconnectTimeout);
      this._reconnectTimeout = null;
    }
    if (this._respawnTimeout) {
      clearTimeout(this._respawnTimeout);
      this._respawnTimeout = null;
    }
  }

  /**
   * Get the current status of this bot.
   * @returns {object}
   */
  getStatus() {
    return {
      id: this.id,
      name: this.name,
      state: this.state,
      mode: this.mode,
      cells: this.ownCells.size,
      mass: this._getTotalMass(),
      position: this._getCenter(),
    };
  }
}

module.exports = BotClient;
module.exports.BOT_STATES = BOT_STATES;
