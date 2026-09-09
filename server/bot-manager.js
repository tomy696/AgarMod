'use strict';

const BotClient = require('./bot-client');
const { BOT_STATES } = require('./bot-client');

// =============================================================================
// bot-manager.js - Manages multiple bot instances per session
// =============================================================================

class BotManager {
  constructor() {
    // sessionId -> { bots: Map<botId, BotClient>, config: object }
    this.sessions = new Map();
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
  startBots(config) {
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

    // Stop existing bots for this session if any
    if (this.sessions.has(sessionId)) {
      this.stopBots(sessionId);
    }

    const count = Math.max(1, Math.min(100, botCount));
    const bots = new Map();
    const session = { bots, config: { ...config, botCount: count } };
    this.sessions.set(sessionId, session);

    console.log(`[BotManager] Starting ${count} bots for session ${sessionId} -> ${targetIP}`);

    // Stagger bot connections to avoid rate limiting
    for (let i = 0; i < count; i++) {
      const botId = this._nextBotId++;
      const bot = new BotClient({
        id: botId,
        name: count > 1 ? `${botName}_${i + 1}` : botName,
        partyCode,
      });

      bot.setMode(mode);
      bot.updateTarget(targetX, targetY);

      // Handle bot events
      bot.on('disconnected', (info) => {
        this._onBotDisconnected(sessionId, botId, info);
      });

      bot.on('error', (err) => {
        console.error(`[BotManager] Bot ${botId} error:`, err.message);
      });

      bot.on('gameJoined', () => {
        console.log(`[BotManager] Bot ${botId} joined game`);
      });

      bot.on('gameOver', () => {
        console.log(`[BotManager] Bot ${botId} died, will respawn`);
      });

      bots.set(botId, bot);

      // Stagger connections: 200ms apart to avoid rate limiting
      setTimeout(() => {
        if (this.sessions.has(sessionId) && bots.has(botId)) {
          bot.connect(targetIP);
        }
      }, i * 200);
    }

    return { botsStarted: count };
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
      if (status.state === BOT_STATES.CONNECTED ||
          status.state === BOT_STATES.LOGGING_IN ||
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
    if (!session) return;

    const bot = session.bots.get(botId);
    if (!bot) return;

    // Attempt reconnection after a delay (with jitter to avoid thundering herd)
    const delay = 3000 + Math.random() * 5000;
    console.log(`[BotManager] Bot ${botId} disconnected, reconnecting in ${Math.round(delay)}ms`);

    setTimeout(() => {
      // Check that the session and bot still exist
      const sess = this.sessions.get(sessionId);
      if (!sess || !sess.bots.has(botId)) return;

      const b = sess.bots.get(botId);
      if (b.state === BOT_STATES.DISCONNECTED) {
        b.connect(sess.config.targetIP);
      }
    }, delay);
  }
}

module.exports = BotManager;
