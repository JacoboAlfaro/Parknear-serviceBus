#!/usr/bin/env node

const http = require('http');
const { randomUUID } = require('crypto');

const HOST = process.env.AUTH_HOST || '0.0.0.0';
const PORT = Number(process.env.AUTH_PORT || 3000);

function sendJson(res, statusCode, body, correlationId) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'X-Correlation-ID': correlationId,
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const correlationId = req.headers['x-correlation-id'] || randomUUID();

  try {
    if (req.url === '/health' && req.method === 'GET') {
      return sendJson(res, 200, { status: 'ok', service: 'auth-mock' }, correlationId);
    }

    if (req.url.startsWith('/api/auth/login') && req.method === 'POST') {
      const raw = await readBody(req);
      let parsed = {};

      if (raw.length > 0) {
        try {
          parsed = JSON.parse(raw.toString('utf8'));
        } catch (_) {
          return sendJson(
            res,
            400,
            { error: 'invalid_json', message: 'Body must be valid JSON' },
            correlationId,
          );
        }
      }

      const user = parsed.email || 'demo@parknear.local';
      return sendJson(
        res,
        200,
        {
          ok: true,
          service: 'auth-mock',
          route: '/api/auth/login',
          user,
          token: 'mock-jwt-token',
          receivedCorrelationId: correlationId,
        },
        correlationId,
      );
    }

    if (req.url.startsWith('/api/users/me') && req.method === 'GET') {
      return sendJson(
        res,
        200,
        {
          ok: true,
          service: 'auth-mock',
          route: '/api/users/me',
          user: { id: 1, name: 'Test User', role: 'driver' },
          receivedCorrelationId: correlationId,
        },
        correlationId,
      );
    }

    if ((req.url.startsWith('/api/auth') || req.url.startsWith('/api/users')) && req.method === 'POST') {
      const raw = await readBody(req);
      return sendJson(
        res,
        200,
        {
          ok: true,
          service: 'auth-mock',
          route: req.url,
          method: req.method,
          bytesReceived: raw.length,
          receivedCorrelationId: correlationId,
        },
        correlationId,
      );
    }

    return sendJson(
      res,
      404,
      {
        error: 'not_found',
        message: 'Route not mocked in auth server',
        route: req.url,
        method: req.method,
      },
      correlationId,
    );
  } catch (error) {
    return sendJson(
      res,
      500,
      {
        error: 'internal_error',
        message: error.message,
      },
      correlationId,
    );
  }
});

server.listen(PORT, HOST, () => {
  console.log(`auth-mock listening on http://${HOST}:${PORT}`);
  console.log('Try: curl -i -X POST http://localhost:3000/api/auth/login -H "content-type: application/json" -d "{\"email\":\"demo@parknear.local\"}"');
});
