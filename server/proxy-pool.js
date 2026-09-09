'use strict';

const fs = require('fs');
const path = require('path');

// =============================================================================
// proxy-pool.js — Rotating proxy pool for bot connections
//
// BiteYt server architecture (deduced from binary reverse engineering):
// - Each bot WebSocket connection is routed through a different proxy
// - SOCKS5 residential proxies to avoid IP-based detection
// - Round-robin rotation with health tracking
// =============================================================================

class ProxyPool {
  constructor() {
    // Array of { url, type, alive, lastUsed, failures, inUse }
    this.proxies = [];
    this._roundRobinIndex = 0;
  }

  /**
   * Load proxies from a file.
   * Supports formats:
   *   socks5://user:pass@host:port
   *   http://user:pass@host:port
   *   host:port (defaults to socks5)
   *   host:port:user:pass (defaults to socks5)
   * @param {string} filePath
   */
  loadFromFile(filePath) {
    const resolved = path.resolve(filePath);
    if (!fs.existsSync(resolved)) {
      console.log(`[ProxyPool] File not found: ${resolved}`);
      return 0;
    }

    const lines = fs.readFileSync(resolved, 'utf8')
      .split('\n')
      .map(l => l.trim())
      .filter(l => l && !l.startsWith('#'));

    let added = 0;
    for (const line of lines) {
      const proxy = this._parseLine(line);
      if (proxy) {
        this.proxies.push(proxy);
        added++;
      }
    }

    console.log(`[ProxyPool] Loaded ${added} proxies from ${resolved}`);
    return added;
  }

  /**
   * Add proxies from an array of URL strings.
   * @param {string[]} urls
   */
  addProxies(urls) {
    for (const url of urls) {
      const proxy = this._parseLine(url);
      if (proxy) this.proxies.push(proxy);
    }
  }

  /**
   * Get the next available proxy (round-robin).
   * Skips dead proxies. Returns null if no proxies or all dead.
   * @returns {{ url: string, type: string }|null}
   */
  getNext() {
    if (this.proxies.length === 0) return null;

    const total = this.proxies.length;
    for (let i = 0; i < total; i++) {
      const idx = (this._roundRobinIndex + i) % total;
      const proxy = this.proxies[idx];
      if (proxy.alive) {
        this._roundRobinIndex = (idx + 1) % total;
        proxy.lastUsed = Date.now();
        return { url: proxy.url, type: proxy.type };
      }
    }
    return null;
  }

  /**
   * Get a specific number of unique proxies for a batch of bots.
   * @param {number} count
   * @returns {Array<{ url: string, type: string }>}
   */
  getBatch(count) {
    const result = [];
    const alive = this.proxies.filter(p => p.alive);
    if (alive.length === 0) return result;

    for (let i = 0; i < count; i++) {
      const idx = (this._roundRobinIndex + i) % alive.length;
      result.push({ url: alive[idx].url, type: alive[idx].type });
      alive[idx].lastUsed = Date.now();
    }
    this._roundRobinIndex = (this._roundRobinIndex + count) % alive.length;
    return result;
  }

  /**
   * Mark a proxy as failed (will be temporarily disabled after too many failures).
   * @param {string} url
   */
  markFailed(url) {
    const proxy = this.proxies.find(p => p.url === url);
    if (!proxy) return;

    proxy.failures++;
    if (proxy.failures >= 5) {
      proxy.alive = false;
      console.log(`[ProxyPool] Proxy disabled (5 failures): ${url}`);
      // Auto-revive after 5 minutes
      setTimeout(() => {
        proxy.alive = true;
        proxy.failures = 0;
        console.log(`[ProxyPool] Proxy revived: ${url}`);
      }, 5 * 60 * 1000);
    }
  }

  /**
   * Mark a proxy as successful (resets failure count).
   * @param {string} url
   */
  markSuccess(url) {
    const proxy = this.proxies.find(p => p.url === url);
    if (proxy) proxy.failures = 0;
  }

  /**
   * @returns {{ total: number, alive: number, dead: number }}
   */
  getStats() {
    const alive = this.proxies.filter(p => p.alive).length;
    return {
      total: this.proxies.length,
      alive,
      dead: this.proxies.length - alive,
    };
  }

  _parseLine(line) {
    let url = line;
    let type = 'socks5';

    if (line.startsWith('socks5://') || line.startsWith('socks4://')) {
      type = line.startsWith('socks5') ? 'socks5' : 'socks4';
      url = line;
    } else if (line.startsWith('http://') || line.startsWith('https://')) {
      type = 'http';
      url = line;
    } else {
      // host:port or host:port:user:pass
      const parts = line.split(':');
      if (parts.length === 2) {
        url = `socks5://${parts[0]}:${parts[1]}`;
      } else if (parts.length === 4) {
        url = `socks5://${parts[2]}:${parts[3]}@${parts[0]}:${parts[1]}`;
      } else {
        return null;
      }
    }

    return {
      url,
      type,
      alive: true,
      lastUsed: 0,
      failures: 0,
    };
  }
}

module.exports = ProxyPool;
