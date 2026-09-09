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

const { fetchClientVersion } = require('./protocol');

const app = express();
const PORT = parseInt(process.env.PORT, 10) || 3001;
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

// Region codes used by dashboard → passed to bouncer which resolves actual server
const REGION_TO_SERVER = {
  'eu-west-2': 'eu-west-2',
  'eu-west-3': 'eu-west-3',
  'eu-central-1': 'eu-central-1',
  'us-east-1': 'us-east-1',
  'us-east-2': 'us-east-2',
  'us-west-1': 'us-west-1',
  'sa-east-1': 'sa-east-1',
  'ap-northeast-1': 'ap-northeast-1',
  'ap-southeast-1': 'ap-southeast-1',
  'me-south-1': 'me-south-1',
};

app.post('/botter2.php', async (req, res) => {
  const {
    action,
    state: stateParam,
    session_id: sessionId,
    targetip: targetIP,
    region,
    game_mode: gameMode,
    mode = 'follow',
    bot_name: botName = 'Bot',
    bot_count: botCountRaw = '1',
    party_code: partyCode,
    party,
    player_state: playerState,
    target_x: targetXRaw = '0',
    target_y: targetYRaw = '0',
  } = req.body;

  const cmd = stateParam || action || '';
  const botCount = parseInt(botCountRaw, 10) || 1;
  const targetX = parseFloat(targetXRaw) || 0;
  const targetY = parseFloat(targetYRaw) || 0;
  const code = partyCode || party || undefined;
  const resolvedIP = targetIP || REGION_TO_SERVER[region] || '';

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
      if (!resolvedIP) {
        return res.json({
          api_response: false,
          status: 'error',
          title: 'Error',
          text: 'Missing targetip or region',
        });
      }

      console.log(`[Botter] Starting ${botCount} bots on ${resolvedIP} (region: ${region || 'custom'}, mode: ${mode}, gameMode: ${gameMode || 'ffa'}, party: ${code || 'none'})`);

      const result = await botManager.startBots({
        sessionId,
        targetIP: resolvedIP,
        mode,
        gameMode: gameMode || 'ffa',
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
  const file = req.body.file || path.join(__dirname, 'proxies.txt');
  const count = botManager.proxyPool.loadFromFile(file);
  res.json({ status: 'ok', proxies_loaded: count, ...botManager.proxyPool.getStats() });
});

// ---------------------------------------------------------------------------
// Debug endpoints
// ---------------------------------------------------------------------------

const proto2 = require('./protocol');

// Ring buffer for server-side logs
const LOG_BUFFER_SIZE = 200;
const logBuffer = [];
const origLog = console.log;
const origErr = console.error;
console.log = (...args) => {
  origLog(...args);
  const msg = args.map(a => typeof a === 'string' ? a : JSON.stringify(a)).join(' ');
  logBuffer.push({ ts: Date.now(), level: 'info', msg });
  if (logBuffer.length > LOG_BUFFER_SIZE) logBuffer.shift();
};
console.error = (...args) => {
  origErr(...args);
  const msg = args.map(a => typeof a === 'string' ? a : (a instanceof Error ? a.message : JSON.stringify(a))).join(' ');
  logBuffer.push({ ts: Date.now(), level: 'error', msg });
  if (logBuffer.length > LOG_BUFFER_SIZE) logBuffer.shift();
};

app.get('/debug/logs', (req, res) => {
  const since = parseInt(req.query.since) || 0;
  const entries = since ? logBuffer.filter(l => l.ts > since) : logBuffer.slice(-50);
  res.json({ logs: entries });
});

app.get('/debug/bouncer', async (req, res) => {
  const region = req.query.region || 'eu-west-2';
  const mode = req.query.mode || ':ffa';
  const host = req.query.host || null;
  const bouncerRegion = proto2.REGION_MAP[region] || region;

  console.log(`[Debug] Testing bouncer: region=${region} → ${bouncerRegion}, mode=${mode}, host=${host || 'default'}`);

  try {
    const result = await proto2.findServer(region, mode, null, host);
    console.log(`[Debug] Bouncer success: ${JSON.stringify(result)}`);
    res.json({
      status: 'ok',
      region,
      bouncer_region: bouncerRegion,
      bouncer_host: host || proto2.BOUNCER_HOST,
      server: result.server,
      token: result.token,
      ws_url: `wss://${result.server}`,
      client_version: proto2.CLIENT_VERSION,
    });
  } catch (err) {
    console.error(`[Debug] Bouncer failed:`, err.message);
    res.json({
      status: 'error',
      region,
      bouncer_region: bouncerRegion,
      bouncer_host: host || proto2.BOUNCER_HOST,
      error: err.message,
      client_version: proto2.CLIENT_VERSION,
    });
  }
});

app.get('/debug/mobile', async (req, res) => {
  const region = req.query.region || 'eu-west-2';
  const mode = req.query.mode || 'ffa';
  const party = req.query.party || null;

  console.log(`[Debug] Testing Mobile API: region=${region}, mode=${mode}, party=${party || 'none'}`);

  try {
    const result = await proto2.findMobileServer(region, mode, party);
    console.log(`[Debug] Mobile API success: ${JSON.stringify(result)}`);
    res.json({
      status: 'ok',
      api: 'mc-api.agar.io',
      region,
      mode,
      party: party || null,
      server: result.server,
      token: result.token,
      ws_url: result.server.startsWith('wss://') ? result.server : `wss://${result.server}`,
    });
  } catch (err) {
    console.error(`[Debug] Mobile API failed:`, err.message);
    res.json({
      status: 'error',
      api: 'mc-api.agar.io',
      region,
      mode,
      party: party || null,
      error: err.message,
    });
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const server = app.listen(PORT, async () => {
  const proxyStats = botManager.proxyPool.getStats();
  const clientVer = await fetchClientVersion();
  console.log('='.repeat(60));
  console.log('  XRD Bot Server (Protocol 23)');
  console.log(`  Port:           ${PORT}`);
  console.log(`  Client Version: ${clientVer}`);
  console.log(`  Proxies:        ${proxyStats.alive}/${proxyStats.total} alive`);
  console.log(`  Dashboard:      http://localhost:${PORT}/`);
  console.log(`  Health:         http://localhost:${PORT}/health`);
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
