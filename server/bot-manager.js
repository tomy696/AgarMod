'use strict';

const BotClient = require('./bot-client');
const { BOT_STATES } = require('./bot-client');
const ProxyPool = require('./proxy-pool');
const proto = require('./protocol');

// =============================================================================
// bot-manager.js — Manages multiple bot instances per session
//
// Deduced from BiteYt binary: the server assigns one proxy per bot,
// staggers connections (200-500ms apart), tracks per-session state,
// supports start/stop/pause, and auto-reconnects with proxy rotation.
// =============================================================================

class BotManager {
  constructor() {
    // sessionId -> { bots, config, paused, proxiesUsed }
    this.sessions = new Map();
    this.proxyPool = new ProxyPool();
    this._nextBotId = 1;
  }

  /**
   * Start bots for a session.
   * @param {object} config
   * @param {string} config.sessionId
   * @param {string} config.targetIP - Server IP:port
   * @param {string} config.mode - Bot behavior mode
   * @param {string} config.botName - Display name prefix
   * @param {number} config.botCount - Number of bots to spawn (1-100)
   * @param {string} [config.partyCode]
   * @param {number} [config.targetX]
   * @param {number} [config.targetY]
   * @returns {{ botsStarted: number }}
   */
  async _scanForPartyServer(region, partyCode) {
    const servers = new Set();
    const scanCount = 15;
    console.log(`[Scanner] Collecting servers in ${region} (${scanCount} queries)...`);

    for (let i = 0; i < scanCount; i++) {
      try {
        const { server } = await proto.findServer(region, ':ffa');
        servers.add(server);
      } catch (_) {}
      if (i < scanCount - 1) await new Promise(r => setTimeout(r, 300));
    }

    const unique = [...servers];
    console.log(`[Scanner] Found ${unique.length} unique servers, probing with party_id=${partyCode}...`);

    const WebSocket = require('ws');
    const results = [];

    const probeServer = (serverUrl) => {
      return new Promise((resolve) => {
        const url = `wss://${serverUrl}?party_id=${encodeURIComponent(partyCode)}`;
        const timeout = setTimeout(() => { try { ws.close(); } catch(_){} resolve({ serverUrl, ok: false, reason: 'timeout' }); }, 8000);
        let ws;
        try {
          ws = new WebSocket(url, {
            headers: { 'Origin': 'https://agar.io', 'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15' },
            rejectUnauthorized: false, handshakeTimeout: 8000,
          });
          ws.binaryType = 'nodebuffer';
          let gotEncryption = false;
          ws.on('open', () => {
            ws.send(proto.buildProtocolVersion());
            ws.send(proto.buildClientVersion());
          });
          ws.on('message', (data) => {
            const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
            if (buf.length > 0) {
              const op = buf.readUInt8(0);
              if (op === 241) gotEncryption = true;
            }
          });
          ws.on('close', (code) => {
            clearTimeout(timeout);
            if (code === 14 || code === 15) {
              resolve({ serverUrl, ok: false, reason: `disconnect:${code}` });
            } else if (gotEncryption) {
              resolve({ serverUrl, ok: true, reason: 'connected+encrypted' });
            } else {
              resolve({ serverUrl, ok: false, reason: `close:${code}` });
            }
          });
          ws.on('error', () => {
            clearTimeout(timeout);
            resolve({ serverUrl, ok: false, reason: 'error' });
          });
          setTimeout(() => {
            if (gotEncryption) {
              clearTimeout(timeout);
              try { ws.close(); } catch(_){}
              resolve({ serverUrl, ok: true, reason: 'connected+encrypted' });
            }
          }, 4000);
        } catch (e) {
          clearTimeout(timeout);
          resolve({ serverUrl, ok: false, reason: 'exception' });
        }
      });
    };

    // Probe servers in batches of 5
    for (let i = 0; i < unique.length; i += 5) {
      const batch = unique.slice(i, i + 5);
      const batchResults = await Promise.all(batch.map(s => probeServer(s)));
      results.push(...batchResults);
      console.log(`[Scanner] Batch ${Math.floor(i/5)+1}: ${batchResults.map(r => r.serverUrl.split('/').pop() + '=' + r.reason).join(', ')}`);
    }

    // All servers that connected successfully are candidates
    // Servers that disconnect with code 14/15 are definitely wrong (invalid/expired token)
    const good = results.filter(r => r.ok);
    const bad = results.filter(r => !r.ok && r.reason.startsWith('disconnect:'));

    console.log(`[Scanner] Results: ${good.length} connected, ${bad.length} rejected token, ${results.length - good.length - bad.length} other`);

    if (good.length > 0) {
      // Can't distinguish the right one from the probe alone — all accept connections
      // Return the first one; the party_id param should route us inside the right server
      return good[0].serverUrl;
    }

    // If all failed, just return a random server
    if (unique.length > 0) return unique[0];
    throw new Error('No servers found in region');
  }

  async startBots(config) {
    const {
      sessionId,
      targetIP,
      mode = 'move',
      botName = 'Bot',
      botCount = 1,
      partyCode,
      targetX = 0,
      targetY = 0,
    } = config;

    if (this.sessions.has(sessionId)) {
      this.stopBots(sessionId);
    }

    const count = Math.max(1, Math.min(100, botCount));

    let resolvedUrl = targetIP;
    const isDirectUrl = targetIP.startsWith('ws://') || targetIP.startsWith('wss://');
    const isRegion = !isDirectUrl && !targetIP.includes('/') && !targetIP.includes('.');

    // Direct URL with party code: append ?party_id=CODE
    if (isDirectUrl && partyCode) {
      resolvedUrl = targetIP + (targetIP.includes('?') ? '&' : '?') + `party_id=${encodeURIComponent(partyCode)}`;
      console.log(`[BotManager] Direct server + party: ${resolvedUrl}`);
    } else if (isRegion) {
      try {
        if (partyCode) {
          console.log(`[BotManager] Joining party: code=${partyCode}, region=${targetIP}`);
          // Scan all servers in the region, distribute bots across them
          // since we can't resolve party codes (v4/getToken is dead)
          const servers = new Set();
          const scanCount = 20;
          for (let i = 0; i < scanCount; i++) {
            try {
              const { server } = await proto.findServer(targetIP, ':ffa');
              servers.add(server);
            } catch (_) {}
            if (i < scanCount - 1) await new Promise(r => setTimeout(r, 200));
          }
          const unique = [...servers];
          console.log(`[BotManager] Found ${unique.length} servers in region, sending bots to ALL with party_id=${partyCode}`);

          if (unique.length === 0) throw new Error('No servers found');

          // Store all servers — bots will be distributed across them
          config._partyServers = unique;
          config._partyCode = partyCode;
          resolvedUrl = `wss://${unique[0]}?party_id=${encodeURIComponent(partyCode)}`;
        } else {
          console.log(`[BotManager] Finding server: region=${targetIP}, mode=${config.gameMode || 'ffa'}`);
          const { server } = await proto.findServer(targetIP, config.gameMode || 'ffa');
          resolvedUrl = `wss://${server}`;
        }
        console.log(`[BotManager] Resolved: ${resolvedUrl}`);
      } catch (err) {
        console.error(`[BotManager] Server resolution failed:`, err.message);
        return { botsStarted: 0, error: err.message };
      }
    }

    const bots = new Map();
    const proxiesUsed = new Map();
    const session = { bots, config: { ...config, botCount: count, resolvedUrl }, paused: false, proxiesUsed };
    this.sessions.set(sessionId, session);

    const proxyStats = this.proxyPool.getStats();
    const proxies = proxyStats.total > 0
      ? this.proxyPool.getBatch(count)
      : [];

    const hasProxies = proxies.length > 0;
    console.log(`[BotManager] Starting ${count} bots for session ${sessionId} -> ${resolvedUrl} (${hasProxies ? proxies.length + ' proxies' : 'direct'})`);

    for (let i = 0; i < count; i++) {
      const botId = this._nextBotId++;
      const proxy = hasProxies ? proxies[i % proxies.length] : null;
      const bot = new BotClient({
        id: botId,
        name: count > 1 ? `${botName}_${i + 1}` : botName,
        partyCode,
        gameMode: config.gameMode || 'ffa',
      });

      bot.setMode(mode);
      bot.updateTarget(targetX, targetY);
      if (proxy) proxiesUsed.set(botId, proxy);

      bot.on('connected', () => {
        if (proxy) this.proxyPool.markSuccess(proxy.url);
      });

      bot.on('disconnected', (info) => {
        this._onBotDisconnected(sessionId, botId, info);
      });

      bot.on('error', (err) => {
        console.error(`[BotManager] Bot ${botId} error:`, err.message);
        if (proxy) this.proxyPool.markFailed(proxy.url);
      });

      bot.on('gameJoined', () => {
        console.log(`[BotManager] Bot ${botId} joined game`);
      });

      bot.on('gameOver', () => {
        console.log(`[BotManager] Bot ${botId} died, will respawn`);
      });

      bots.set(botId, bot);

      // Assign each bot a server URL — distribute across party servers if scanning
      const partyServers = config._partyServers;
      let botUrl;
      if (partyServers && partyServers.length > 0) {
        const srv = partyServers[i % partyServers.length];
        botUrl = `wss://${srv}?party_id=${encodeURIComponent(config._partyCode)}`;
      } else {
        botUrl = resolvedUrl;
      }
      bot._assignedUrl = botUrl;

      const delay = i * (200 + Math.random() * 200);
      setTimeout(() => {
        if (this.sessions.has(sessionId) && bots.has(botId) && !session.paused) {
          bot.connect(botUrl, proxy);
        }
      }, delay);
    }

    return { botsStarted: count };
  }

  /**
   * Pause all bots for a session (disconnect but keep session alive).
   * Matches BiteYt's state=pause parameter.
   * @param {string} sessionId
   * @returns {{ botsPaused: number }}
   */
  pauseBots(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return { botsPaused: 0 };

    session.paused = true;
    let paused = 0;
    for (const [, bot] of session.bots) {
      if (bot.state !== BOT_STATES.DISCONNECTED) {
        bot.disconnect();
        paused++;
      }
    }
    console.log(`[BotManager] Paused ${paused} bots for session ${sessionId}`);
    return { botsPaused: paused };
  }

  /**
   * Resume paused bots (reconnect with their assigned proxies).
   * @param {string} sessionId
   * @returns {{ botsResumed: number }}
   */
  resumeBots(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return { botsResumed: 0 };

    session.paused = false;
    let resumed = 0;
    let i = 0;
    for (const [botId, bot] of session.bots) {
      if (bot.state === BOT_STATES.DISCONNECTED) {
        const proxy = session.proxiesUsed.get(botId) || null;
        const delay = i * (300 + Math.random() * 200);
        setTimeout(() => {
          if (this.sessions.has(sessionId) && session.bots.has(botId) && !session.paused) {
            bot.connect(session.config.targetIP, proxy);
          }
        }, delay);
        resumed++;
        i++;
      }
    }
    console.log(`[BotManager] Resuming ${resumed} bots for session ${sessionId}`);
    return { botsResumed: resumed };
  }

  /**
   * Stop all bots for a session.
   * @param {string} sessionId
   * @returns {{ botsStopped: number }}
   */
  stopBots(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { botsStopped: 0 };
    }

    let stopped = 0;
    for (const [, bot] of session.bots) {
      bot.disconnect();
      stopped++;
    }

    session.bots.clear();
    this.sessions.delete(sessionId);

    console.log(`[BotManager] Stopped ${stopped} bots for session ${sessionId}`);
    return { botsStopped: stopped };
  }

  /**
   * Update all bots for a session.
   * @param {string} sessionId
   * @param {object} config
   * @param {string} [config.mode]
   * @param {number} [config.targetX]
   * @param {number} [config.targetY]
   * @param {string} [config.botName]
   * @returns {{ botsUpdated: number }}
   */
  updateBots(sessionId, config) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { botsUpdated: 0 };
    }

    let updated = 0;
    for (const [, bot] of session.bots) {
      if (config.mode !== undefined) {
        bot.setMode(config.mode);
      }
      if (config.targetX !== undefined && config.targetY !== undefined) {
        bot.updateTarget(config.targetX, config.targetY);
      }
      updated++;
    }

    // Update stored config
    if (config.mode !== undefined) session.config.mode = config.mode;
    if (config.targetX !== undefined) session.config.targetX = config.targetX;
    if (config.targetY !== undefined) session.config.targetY = config.targetY;

    return { botsUpdated: updated };
  }

  /**
   * Get the status of all bots for a session.
   * @param {string} sessionId
   * @returns {object}
   */
  getStatus(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        active: false,
        bots_running: 0,
        bots_connected: 0,
        bots_in_game: 0,
        mode: null,
        bots: [],
      };
    }

    let connected = 0;
    let inGame = 0;
    const botStatuses = [];

    for (const [, bot] of session.bots) {
      const status = bot.getStatus();
      botStatuses.push(status);
      if (status.state === BOT_STATES.HANDSHAKE ||
          status.state === BOT_STATES.ENCRYPTED ||
          status.state === BOT_STATES.SPAWNING ||
          status.state === BOT_STATES.IN_GAME) {
        connected++;
      }
      if (status.state === BOT_STATES.IN_GAME) {
        inGame++;
      }
    }

    const serverCount = session.config._partyServers ? session.config._partyServers.length : 1;

    return {
      active: true,
      bots_running: session.bots.size,
      bots_connected: connected,
      bots_in_game: inGame,
      mode: session.config.mode,
      target_ip: session.config.targetIP,
      servers_scanning: serverCount,
      bots: botStatuses,
    };
  }

  /**
   * Get a summary status across all sessions.
   * @returns {object}
   */
  getGlobalStatus() {
    let totalBots = 0;
    let totalConnected = 0;
    let totalInGame = 0;
    const sessionSummaries = [];

    for (const [sessionId, session] of this.sessions) {
      const status = this.getStatus(sessionId);
      totalBots += status.bots_running;
      totalConnected += status.bots_connected;
      totalInGame += status.bots_in_game;
      sessionSummaries.push({
        session_id: sessionId,
        bots_running: status.bots_running,
        bots_connected: status.bots_connected,
        bots_in_game: status.bots_in_game,
        mode: status.mode,
      });
    }

    return {
      total_sessions: this.sessions.size,
      total_bots: totalBots,
      total_connected: totalConnected,
      total_in_game: totalInGame,
      sessions: sessionSummaries,
    };
  }

  /**
   * Stop all bots across all sessions. Used for graceful shutdown.
   */
  stopAll() {
    for (const [sessionId] of this.sessions) {
      this.stopBots(sessionId);
    }
  }

  /**
   * Handle a bot disconnecting. Attempt reconnection if the session is still active.
   * @param {string} sessionId
   * @param {number} botId
   * @param {object} info
   */
  _onBotDisconnected(sessionId, botId, info) {
    const session = this.sessions.get(sessionId);
    if (!session || session.paused) return;

    const bot = session.bots.get(botId);
    if (!bot) return;

    // Get a fresh proxy for reconnection (rotate away from failed ones)
    let proxy = session.proxiesUsed.get(botId) || null;
    if (this.proxyPool.getStats().alive > 0) {
      const newProxy = this.proxyPool.getNext();
      if (newProxy) {
        proxy = newProxy;
        session.proxiesUsed.set(botId, proxy);
      }
    }

    const delay = 3000 + Math.random() * 5000;
    console.log(`[BotManager] Bot ${botId} disconnected, reconnecting in ${Math.round(delay)}ms`);

    setTimeout(() => {
      const sess = this.sessions.get(sessionId);
      if (!sess || !sess.bots.has(botId) || sess.paused) return;

      const b = sess.bots.get(botId);
      if (b.state === BOT_STATES.DISCONNECTED) {
        b.connect(b._assignedUrl || sess.config.resolvedUrl || sess.config.targetIP, proxy);
      }
    }, delay);
  }
}

module.exports = BotManager;
