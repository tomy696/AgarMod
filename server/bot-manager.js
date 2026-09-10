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
  async _scanForPlayer(region, partyCode, nickname) {
    const servers = new Set();
    console.log(`[Scanner] Discovering servers in ${region} (party + ffa pools)...`);

    for (let i = 0; i < 15; i++) {
      try {
        const { server } = await proto.findServer(region, ':party');
        servers.add(server);
      } catch (_) {}
      if (i < 14) await new Promise(r => setTimeout(r, 250));
    }
    const partyCount = servers.size;

    for (let i = 0; i < 10; i++) {
      try {
        const { server } = await proto.findServer(region, ':ffa');
        servers.add(server);
      } catch (_) {}
      if (i < 9) await new Promise(r => setTimeout(r, 250));
    }

    const unique = [...servers];
    console.log(`[Scanner] Found ${unique.length} unique servers (${partyCount} party + ${unique.length - partyCount} ffa), scanning for "${nickname}"...`);

    if (unique.length === 0) throw new Error('No servers found in region');

    return new Promise((resolve) => {
      const scouts = [];
      let resolved = false;
      const checkIntervals = [];

      const cleanup = () => {
        for (const iv of checkIntervals) clearInterval(iv);
        for (const s of scouts) {
          try { s.disconnect(); } catch (_) {}
        }
      };

      for (let i = 0; i < unique.length; i++) {
        const serverUrl = unique[i];
        const scoutUrl = `wss://${serverUrl}?party_id=${encodeURIComponent(partyCode)}`;
        const shortName = serverUrl.split('/').pop() || serverUrl;

        const scout = new BotClient({
          id: 90000 + i,
          name: `Scout`,
          partyCode,
          gameMode: 'ffa',
        });
        scouts.push(scout);

        const startCheck = () => {
          const iv = setInterval(() => {
            if (resolved) { clearInterval(iv); return; }
            if (scout.hasPlayerNamed(nickname)) {
              console.log(`[Scanner] FOUND "${nickname}" on ${shortName}!`);
              resolved = true;
              cleanup();
              resolve(serverUrl);
            }
          }, 300);
          checkIntervals.push(iv);
        };

        scout.on('connected', () => {
          console.log(`[Scanner] Scout ${i} connected to ${shortName}`);
          startCheck();
        });

        scout.on('gameJoined', () => {
          console.log(`[Scanner] Scout ${i} spawned on ${shortName}, leaderboard: [${scout.leaderboardNames.join(', ')}]`);
        });

        scout.on('error', () => {});

        const delay = i * 300;
        setTimeout(() => {
          if (!resolved) scout.connect(scoutUrl, null);
        }, delay);
      }

      const totalTimeout = 15000 + unique.length * 300;
      setTimeout(() => {
        if (!resolved) {
          console.log(`[Scanner] Timeout — "${nickname}" not found on ${unique.length} servers`);

          for (let i = 0; i < scouts.length; i++) {
            const s = scouts[i];
            const names = s.getVisiblePlayerNames();
            const lb = s.leaderboardNames;
            if (names.size > 0 || lb.length > 0) {
              const shortName = unique[i].split('/').pop() || unique[i];
              console.log(`[Scanner] Server ${shortName}: leaderboard=[${lb.join(',')}] entities=[${[...names].slice(0,10).join(',')}]`);
            }
          }

          resolved = true;
          cleanup();
          resolve(null);
        }
      }, totalTimeout);
    });
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
          const nickname = config.nickname;
          console.log(`[BotManager] Joining party: code=${partyCode}, region=${targetIP}, nickname=${nickname || 'none'}`);

          if (nickname) {
            const foundServer = await this._scanForPlayer(targetIP, partyCode, nickname);
            if (foundServer) {
              config._playerFound = true;
              console.log(`[BotManager] Player found! All ${count} bots → ${foundServer}`);
              resolvedUrl = `wss://${foundServer}?party_id=${encodeURIComponent(partyCode)}`;
            } else {
              console.log(`[BotManager] Player not found, falling back to scatter across all servers`);
              const servers = new Set();
              for (let i = 0; i < 15; i++) {
                try { const { server } = await proto.findServer(targetIP, ':party'); servers.add(server); } catch (_) {}
                if (i < 14) await new Promise(r => setTimeout(r, 250));
              }
              const unique = [...servers];
              if (unique.length === 0) throw new Error('No servers found');
              config._partyServers = unique;
              config._partyCode = partyCode;
              resolvedUrl = `wss://${unique[0]}?party_id=${encodeURIComponent(partyCode)}`;
            }
          } else {
            const servers = new Set();
            for (let i = 0; i < 15; i++) {
              try { const { server } = await proto.findServer(targetIP, ':party'); servers.add(server); } catch (_) {}
              if (i < 14) await new Promise(r => setTimeout(r, 250));
            }
            const unique = [...servers];
            if (unique.length === 0) throw new Error('No servers found');
            config._partyServers = unique;
            config._partyCode = partyCode;
            console.log(`[BotManager] No nickname provided, scattering bots across ${unique.length} servers`);
            resolvedUrl = `wss://${unique[0]}?party_id=${encodeURIComponent(partyCode)}`;
          }
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

    return { botsStarted: count, playerFound: !!config._playerFound };
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
