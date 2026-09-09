'use strict';

const express = require('express');
const cors = require('cors');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const BotManager = require('./bot-manager');

// =============================================================================
// index.js — Agar.io bot server (BiteYt-compatible API)
//
// Reconstructed from BiteYt v1.3.0 binary reverse engineering.
// Provides the exact same endpoint shape so the iOS tweak works unchanged.
//
// Endpoints (from binary base64 strings):
//   POST /api?&           — Main API (versioncheck, tokver, login, buy_bots)
//   POST /botter2.php     — Bot control (start/stop/pause/resume/update)
//   POST /getsecretkey.php — Secret key validation
// =============================================================================

const app = express();
const PORT = parseInt(process.env.PORT, 10) || 3000;
const botManager = new BotManager();

// Load proxies from env var (for Railway/cloud) or file (for local)
// PROXY_LIST env: comma-separated proxy URLs
// PROXY_FILE env or proxies.txt: one proxy per line
if (process.env.PROXY_LIST) {
  const urls = process.env.PROXY_LIST.split(',').map(s => s.trim()).filter(Boolean);
  botManager.proxyPool.addProxies(urls);
  console.log(`[Server] Loaded ${urls.length} proxies from PROXY_LIST env`);
} else {
  const proxyFile = process.env.PROXY_FILE || path.join(__dirname, 'proxies.txt');
  const loaded = botManager.proxyPool.loadFromFile(proxyFile);
  if (loaded === 0) {
    console.log('[Server] No proxies loaded — bots will connect directly (likely to get rate-limited)');
    console.log('[Server] Set PROXY_LIST env or add proxies to server/proxies.txt');
  }
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

app.use(cors());
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Serve dashboard
app.use(express.static(path.join(__dirname, 'public')));

app.use((req, res, next) => {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${req.method} ${req.path}`);
  next();
});

// ---------------------------------------------------------------------------
// POST /api?&  —  Main API (matches BiteYt binary: aHR0cHM6Ly9iaXRleXQuY29tL2FwaT8m)
// ---------------------------------------------------------------------------

app.post('/api', (req, res) => {
  const body = typeof req.body === 'string' ? req.body : '';
  const action = req.body.action || req.query.action || '';

  // BiteYt sends form data as "action&param=value" format
  const rawAction = body.split('&')[0] || action;

  switch (rawAction) {
    case 'versioncheck': {
      return res.json({
        api_response: true,
        versionstatus: 'ok',
        version: '1.3.0',
        latest: true,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'tokver': {
      const sessionId = uuidv4();
      return res.json({
        api_response: true,
        uid: sessionId,
        uidstat: 'active',
        enabled: true,
        skinstat: 'unlocked',
        Verified: true,
        ts: Date.now(),
        verid: uuidv4().slice(0, 8),
        servuid: 'self-hosted',
        shash: Buffer.from(sessionId).toString('base64').slice(0, 16),
        skins: 'all',
        skinmodes: 'all',
        skinte: '',
        session_id: sessionId,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'login': {
      const sessionId = uuidv4();
      return res.json({
        api_response: true,
        session_id: sessionId,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'buy_bots': {
      return res.json({
        api_response: true,
        bots_available: 100,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'get_status': {
      const sessionId = req.body.session_id || '';
      if (sessionId) {
        const status = botManager.getStatus(sessionId);
        return res.json({ api_response: true, ...status });
      }
      const globalStatus = botManager.getGlobalStatus();
      return res.json({ api_response: true, ...globalStatus });
    }

    default: {
      return res.json({
        api_response: true,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }
  }
});

// ---------------------------------------------------------------------------
// POST /botter2.php  —  Bot control (matches: aHR0cHM6Ly9iaXRleXQuY29tL2JvdHRlcjIucGhw)
//
// Parameters (from binary NSUserDefaults keys + string analysis):
//   session_id  — user session
//   targetip    — Agar.io game server IP:port
//   mode        — move|feed|farm|makevirus|breakvirus|teamer
//   state       — start|stop|pause  (BiteYt uses 'state' not 'action')
//   bot_name    — name prefix
//   party       — party code
//   bot_count   — number of bots
//   player_state — idle|active (player alive status)
//   target_x/target_y — player position for bot targeting
// ---------------------------------------------------------------------------

app.post('/botter2.php', (req, res) => {
  const {
    action,
    state: stateParam,
    session_id: sessionId,
    targetip: targetIP,
    mode = 'move',
    bot_name: botName = 'Bot',
    bot_count: botCountRaw = '1',
    party_code: partyCode,
    party,
    player_state: playerState,
    target_x: targetXRaw = '0',
    target_y: targetYRaw = '0',
  } = req.body;

  // BiteYt uses 'state' parameter, our tweak sends 'action' — support both
  const cmd = stateParam || action || '';
  const botCount = parseInt(botCountRaw, 10) || 1;
  const targetX = parseFloat(targetXRaw) || 0;
  const targetY = parseFloat(targetYRaw) || 0;
  const code = partyCode || party || undefined;

  if (!sessionId) {
    return res.json({
      api_response: false,
      status: 'error',
      title: 'Error',
      text: 'Missing session_id',
      image_b64: '',
      buttons: [],
      btn_url: '',
    });
  }

  switch (cmd) {
    case 'start': {
      if (!targetIP) {
        return res.json({
          api_response: false,
          status: 'error',
          title: 'Error',
          text: 'Missing targetip',
        });
      }

      const result = botManager.startBots({
        sessionId,
        targetIP,
        mode,
        botName,
        botCount,
        partyCode: code,
        targetX,
        targetY,
      });

      const status = botManager.getStatus(sessionId);
      const proxyStats = botManager.proxyPool.getStats();
      return res.json({
        api_response: true,
        status: 'ok',
        session_id: sessionId,
        bots_running: status.bots_running,
        bots_connected: status.bots_connected,
        bots_started: result.botsStarted,
        proxies_alive: proxyStats.alive,
        proxies_total: proxyStats.total,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'stop': {
      const result = botManager.stopBots(sessionId);
      return res.json({
        api_response: true,
        status: 'ok',
        session_id: sessionId,
        bots_running: 0,
        bots_connected: 0,
        bots_stopped: result.botsStopped,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'pause': {
      const result = botManager.pauseBots(sessionId);
      const status = botManager.getStatus(sessionId);
      return res.json({
        api_response: true,
        status: 'paused',
        session_id: sessionId,
        bots_running: status.bots_running,
        bots_paused: result.botsPaused,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'resume': {
      const result = botManager.resumeBots(sessionId);
      const status = botManager.getStatus(sessionId);
      return res.json({
        api_response: true,
        status: 'ok',
        session_id: sessionId,
        bots_running: status.bots_running,
        bots_resumed: result.botsResumed,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    case 'update': {
      const result = botManager.updateBots(sessionId, {
        mode: mode || undefined,
        targetX,
        targetY,
        botName: botName || undefined,
      });

      const status = botManager.getStatus(sessionId);
      return res.json({
        api_response: true,
        status: 'ok',
        session_id: sessionId,
        bots_running: status.bots_running,
        bots_connected: status.bots_connected,
        bots_updated: result.botsUpdated,
        title: '',
        text: '',
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }

    default: {
      return res.json({
        api_response: false,
        status: 'error',
        title: 'Error',
        text: `Unknown state: ${cmd}`,
        image_b64: '',
        buttons: [],
        btn_url: '',
      });
    }
  }
});

// ---------------------------------------------------------------------------
// POST /getsecretkey.php  —  Key validation
// ---------------------------------------------------------------------------

app.post('/getsecretkey.php', (req, res) => {
  const sk = req.body.sk || '';

  if (!sk) {
    return res.json({ success: false, data: 'Missing sk parameter' });
  }

  // Self-hosted: accept any key
  const expiresAt = Date.now() + 365 * 24 * 60 * 60 * 1000;
  return res.json({
    success: true,
    data: JSON.stringify({
      valid: true,
      expires: expiresAt,
      key: sk,
      bots_allowed: 100,
    }),
  });
});

// ---------------------------------------------------------------------------
// Health / proxy status
// ---------------------------------------------------------------------------

app.get('/health', (_req, res) => {
  const status = botManager.getGlobalStatus();
  const proxyStats = botManager.proxyPool.getStats();
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    proxies: proxyStats,
    ...status,
  });
});

// Reload proxies at runtime
app.post('/admin/reload-proxies', (req, res) => {
  const file = req.body.file || proxyFile;
  const count = botManager.proxyPool.loadFromFile(file);
  res.json({ status: 'ok', proxies_loaded: count, ...botManager.proxyPool.getStats() });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const server = app.listen(PORT, () => {
  const proxyStats = botManager.proxyPool.getStats();
  console.log('='.repeat(60));
  console.log('  Agar.io Bot Server (BiteYt-compatible)');
  console.log(`  Port:        ${PORT}`);
  console.log(`  Proxies:     ${proxyStats.alive}/${proxyStats.total} alive`);
  console.log(`  API:         http://localhost:${PORT}/api`);
  console.log(`  Bot control: http://localhost:${PORT}/botter2.php`);
  console.log(`  Secret key:  http://localhost:${PORT}/getsecretkey.php`);
  console.log(`  Health:      http://localhost:${PORT}/health`);
  console.log('='.repeat(60));
});

// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------

function shutdown(signal) {
  console.log(`\n[Server] Received ${signal}, shutting down...`);
  botManager.stopAll();
  server.close(() => {
    console.log('[Server] HTTP server closed');
    process.exit(0);
  });
  setTimeout(() => {
    console.error('[Server] Forced exit after timeout');
    process.exit(1);
  }, 5000);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('uncaughtException', (err) => {
  console.error('[Server] Uncaught exception:', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[Server] Unhandled rejection:', reason);
});
