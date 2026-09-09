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

    // Resolve server URL ONCE via bouncer (instead of each bot calling individually)
    let resolvedUrl = targetIP;
    const isRegion = !targetIP.startsWith('ws') && !targetIP.includes('/') && !targetIP.includes('.');
    if (isRegion) {
      try {
        console.log(`[BotManager] Resolving server for region=${targetIP}, party=${partyCode || 'none'}, mode=${config.gameMode || 'ffa'}`);
        const { server } = await proto.findServer(targetIP, config.gameMode || 'ffa', partyCode);
        resolvedUrl = `wss://${server}`;
        if (partyCode) {
          resolvedUrl += (resolvedUrl.includes('?') ? '&' : '?') + `party_id=${partyCode}`;
        }
        console.log(`[BotManager] Resolved: ${resolvedUrl}`);
      } catch (err) {
        console.error(`[BotManager] Bouncer failed:`, err.message);
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

      // Stagger 200-400ms apart, pass resolved URL directly
      const delay = i * (200 + Math.random() * 200);
      setTimeout(() => {
        if (this.sessions.has(sessionId) && bots.has(botId) && !session.paused) {
          bot.connect(resolvedUrl, proxy);
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

    return {
      active: true,
      bots_running: session.bots.size,
      bots_connected: connected,
      bots_in_game: inGame,
      mode: session.config.mode,
      target_ip: session.config.targetIP,
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
        // Use cached resolved URL so we don't hit the bouncer again
        b.connect(sess.config.resolvedUrl || sess.config.targetIP, proxy);
      }
    }, delay);
  }
}

module.exports = BotManager;
