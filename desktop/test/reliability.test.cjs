const {test} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {streamCompletion, keyForOrigin, originOf} = require('../src/core.cjs');

function listen(handler) {
  return new Promise(resolve => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => resolve({server, port: server.address().port}));
  });
}
function sse(res, text) {
  res.writeHead(200, {'Content-Type': 'text/event-stream'});
  res.write('data: ' + JSON.stringify({choices: [{delta: {content: text}}]}) + '\n\n');
  res.end('data: [DONE]\n\n');
}
async function body(req) {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  return raw;
}

test('credentials are bound to an origin and never follow the URL to another service', async () => {
  const seen = {a: [], b: []};
  const a = await listen(async (req, res) => { await body(req); seen.a.push(req.headers.authorization); sse(res, 'from A'); });
  const b = await listen(async (req, res) => { await body(req); seen.b.push(req.headers.authorization); sse(res, 'from B'); });
  try {
    const aURL = `http://127.0.0.1:${a.port}`;
    const bURL = `http://127.0.0.1:${b.port}`;
    const keys = {[originOf(aURL)]: 'key-from-A'};

    const first = await streamCompletion({baseURL: aURL, model: 'mock', apiKey: keyForOrigin(keys, aURL)}, [{role: 'user', content: 'hi'}], undefined, () => {});
    assert.equal(first.text, 'from A');
    assert.equal(seen.a[0], 'Bearer key-from-A');

    // Switch the address to B: the A credential must not be selected any more.
    assert.equal(keyForOrigin(keys, bURL), '');
    const second = await streamCompletion({baseURL: bURL, model: 'mock', apiKey: keyForOrigin(keys, bURL)}, [{role: 'user', content: 'hi'}], undefined, () => {});
    assert.equal(second.text, 'from B');
    assert.equal(seen.b[0], undefined);
    assert.notEqual(seen.b[0], 'Bearer key-from-A');

    // A public address without a key fails before any request is sent.
    await assert.rejects(
      streamCompletion({baseURL: 'https://api.example.com', model: 'mock', apiKey: ''}, [], undefined, () => {}),
      error => error.code === 'NO_KEY'
    );
  } finally {
    a.server.close(); b.server.close();
  }
});

test('429 is retried with Retry-After honoured, 401 is not retried', async () => {
  let attempts = 0;
  const limited = await listen(async (req, res) => {
    await body(req);
    attempts++;
    if (attempts === 1) { res.writeHead(429, {'Retry-After': '1'}); res.end('slow down'); return; }
    sse(res, 'recovered');
  });
  try {
    const started = Date.now();
    const result = await streamCompletion({baseURL: `http://127.0.0.1:${limited.port}`, model: 'mock', retries: 2}, [{role: 'user', content: 'hi'}], undefined, () => {});
    assert.equal(result.text, 'recovered');
    assert.equal(attempts, 2);
    assert.ok(Date.now() - started >= 900, 'Retry-After should be respected');
  } finally { limited.server.close(); }

  let authAttempts = 0;
  const unauthorized = await listen(async (req, res) => { await body(req); authAttempts++; res.writeHead(401); res.end('bad key'); });
  try {
    await assert.rejects(
      streamCompletion({baseURL: `http://127.0.0.1:${unauthorized.port}`, model: 'mock', retries: 3}, [{role: 'user', content: 'hi'}], undefined, () => {}),
      error => error.code === 'AUTH'
    );
    assert.equal(authAttempts, 1);
  } finally { unauthorized.server.close(); }
});

test('a stream that already showed text is not replayed and keeps the partial answer', async () => {
  let attempts = 0;
  const broken = await listen(async (req, res) => {
    await body(req);
    attempts++;
    res.writeHead(200, {'Content-Type': 'text/event-stream'});
    res.write('data: ' + JSON.stringify({choices: [{delta: {content: '已经显示的内容'}}]}) + '\n\n');
    setTimeout(() => res.destroy(), 30);
  });
  try {
    await assert.rejects(
      streamCompletion({baseURL: `http://127.0.0.1:${broken.port}`, model: 'mock', retries: 3}, [{role: 'user', content: 'hi'}], undefined, () => {}),
      error => error.code === 'STREAM' && error.partial === '已经显示的内容'
    );
    assert.equal(attempts, 1, 'a partial stream must not be retried automatically');
  } finally { broken.server.close(); }
});

test('cancelling during a retry wait stops immediately', async () => {
  let attempts = 0;
  const limited = await listen(async (req, res) => {
    await body(req); attempts++;
    res.writeHead(429, {'Retry-After': '5'}); res.end('later');
  });
  const controller = new AbortController();
  try {
    const started = Date.now();
    const pending = streamCompletion({baseURL: `http://127.0.0.1:${limited.port}`, model: 'mock', retries: 3}, [], controller.signal, () => {});
    setTimeout(() => controller.abort(), 120);
    await assert.rejects(pending, error => error.code === 'ABORTED');
    assert.ok(Date.now() - started < 2000);
    assert.equal(attempts, 1);
  } finally { limited.server.close(); }
});
