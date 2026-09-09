'use strict';

const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const BotManager = require('./bot-manager');

// =============================================================================
// index.js - HTTP API server for Agar.io bot control
//
// Provides the same endpoint shape as the BiteYt tweak backend so the iOS
// client can point at this server instead.
// =============================================================================

const app = express();
const PORT = parseInt(process.env.PORT, 10) || 3000;
const botManager = new BotManager();

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

app.use(cors());
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${req.method} ${req.path}`);
  next();
});

// ---------------------------------------------------------------------------
// POST /api  -  Main API endpoint
// ---------------------------------------------------------------------------

app.post('/api', (req, res) => {
  const action = req.body.action || req.query.action || '';

  switch (action) {
    case 'versioncheck': {
      return res.json({
        api_response: 'ok',
        version: '1.0.0',
        latest: true,
      });
    }

    case 'tokver': {
      return res.json({
        api_response: 'ok',
        verified: true,
      });
    }

    case 'login': {
      const sessionId = uuidv4();
      return res.json({
        api_response: 'ok',
        session_id: sessionId,
      });
    }

    case 'buy_bots': {
      return res.json({
        api_response: 'ok',
        bots_available: 100,
      });
    }

    case 'get_status': {
      const sessionId = req.body.session_id || '';
      if (sessionId) {
        const status = botManager.getStatus(sessionId);
        return res.json({
          api_response: 'ok',
          ...status,
        });
      }
      const globalStatus = botManager.getGlobalStatus();
      return res.json({
        api_response: 'ok',
        ...globalStatus,
      });
    }

    default: {
      return res.json({
        api_response: 'error',
        message: `Unknown action: ${action}`,
      });
    }
  }
});

// ---------------------------------------------------------------------------
// POST /botter2.php  -  Bot control endpoint
// ---------------------------------------------------------------------------

app.post('/botter2.php', (req, res) => {
  const {
    action,
    session_id: sessionId,
    targetip: targetIP,
    mode = 'move',
    bot_name: botName = 'Bot',
    bot_count: botCountRaw = '1',
    party_code: partyCode,
    target_x: targetXRaw = '0',
    target_y: targetYRaw = '0',
  } = req.body;

  const botCount = parseInt(botCountRaw, 10) || 1;
  const targetX = parseFloat(targetXRaw) || 0;
  const targetY = parseFloat(targetYRaw) || 0;

  if (!sessionId) {
    return res.json({ status: 'error', message: 'Missing session_id' });
  }

  switch (action) {
    case 'start': {
      if (!targetIP) {
        return res.json({ status: 'error', message: 'Missing targetip' });
      }

      const result = botManager.startBots({
        sessionId,
        targetIP,
        mode,
        botName,
        botCount,
        partyCode: partyCode || undefined,
        targetX,
        targetY,
      });

      const status = botManager.getStatus(sessionId);
      return res.json({
        status: 'ok',
        bots_running: status.bots_running,
        bots_connected: status.bots_connected,
        bots_started: result.botsStarted,
      });
    }

    case 'stop': {
      const result = botManager.stopBots(sessionId);
      return res.json({
        status: 'ok',
        bots_running: 0,
        bots_connected: 0,
        bots_stopped: result.botsStopped,
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
        status: 'ok',
        bots_running: status.bots_running,
        bots_connected: status.bots_connected,
        bots_updated: result.botsUpdated,
      });
    }

    default: {
      return res.json({
        status: 'error',
        message: `Unknown action: ${action}`,
      });
    }
  }
});

// ---------------------------------------------------------------------------
// POST /getsecretkey.php  -  Key validation endpoint
// ---------------------------------------------------------------------------

app.post('/getsecretkey.php', (req, res) => {
  const sk = req.body.sk || '';

  if (!sk) {
    return res.json({ valid: false, message: 'Missing sk parameter' });
  }

  // Accept any key -- this is a self-hosted server
  const expiresAt = Date.now() + 365 * 24 * 60 * 60 * 1000; // 1 year from now
  return res.json({
    valid: true,
    expires: expiresAt,
    key: sk,
  });
});

// ---------------------------------------------------------------------------
// Health / info
// ---------------------------------------------------------------------------

app.get('/health', (_req, res) => {
  const status = botManager.getGlobalStatus();
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    ...status,
  });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------

const server = app.listen(PORT, () => {
  console.log('='.repeat(60));
  console.log('  Agar.io Bot Server');
  console.log(`  Listening on port ${PORT}`);
  console.log(`  API:        http://localhost:${PORT}/api`);
  console.log(`  Bot control: http://localhost:${PORT}/botter2.php`);
  console.log(`  Secret key: http://localhost:${PORT}/getsecretkey.php`);
  console.log(`  Health:     http://localhost:${PORT}/health`);
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
  // Force exit after 5 seconds if graceful shutdown hangs
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
