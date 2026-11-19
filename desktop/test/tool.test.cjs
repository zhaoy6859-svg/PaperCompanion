const {test} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {streamCompletion} = require('../src/core.cjs');
const {runToolLoop, getPaperPage, PAPER_TOOLS} = require('../src/tool-loop.mjs');

function listen(handler) {
  return new Promise(resolve => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => resolve({server, port: server.address().port}));
  });
}
async function body(req) {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  return raw;
}
function toolCallStream(res, argsPart1, argsPart2) {
  res.writeHead(200, {'Content-Type': 'text/event-stream'});
  const send = data => res.write('data: ' + JSON.stringify(data) + '\n\n');
  send({choices: [{delta: {tool_calls: [{index: 0, id: 'call_1', type: 'function', function: {name: 'get_paper_page', arguments: argsPart1}}]}}]});
  send({choices: [{delta: {tool_calls: [{index: 0, function: {arguments: argsPart2}}]}}]});
  send({choices: [{delta: {}, finish_reason: 'tool_calls'}]});
  res.end('data: [DONE]\n\n');
}
function textStream(res, text) {
  res.writeHead(200, {'Content-Type': 'text/event-stream'});
  res.write('data: ' + JSON.stringify({choices: [{delta: {content: text}}]}) + '\n\n');
  res.end('data: [DONE]\n\n');
}
async function modelCall(port) {
  return (messages, tools) => streamCompletion({baseURL: `http://127.0.0.1:${port}`, model: 'mock'}, messages, undefined, () => {}, tools);
}

test('model tool call is executed by the app and the page text is sent back', async () => {
  const requests = [];
  const server = await listen(async (req, res) => {
    const raw = await body(req);
    requests.push(JSON.parse(raw));
    if (requests.length === 1) toolCallStream(res, '{"page_', 'number":2}');
    else textStream(res, '第二页解释了经验风险。');
  });
  try {
    const pages = ['第一页内容', '第二页内容：经验风险是平均损失。'];
    const result = await runToolLoop({
      messages: [{role: 'user', content: '第二页讲了什么？'}],
      tools: PAPER_TOOLS,
      callModel: await modelCall(server.port),
      executeTool: call => getPaperPage(pages, call.function.arguments)
    });
    assert.equal(result.text, '第二页解释了经验风险。');
    assert.equal(result.steps, 1);
    // First request offers the tool; second carries the tool result.
    assert.equal(requests[0].tools[0].function.name, 'get_paper_page');
    const toolMessage = requests[1].messages.find(message => message.role === 'tool');
    assert.ok(toolMessage, 'the second request must include a tool result');
    assert.match(toolMessage.content, /第二页内容/);
    assert.equal(toolMessage.tool_call_id, 'call_1');
  } finally { server.server.close(); }
});

test('out-of-range page is rejected by the app, not by the model', async () => {
  const requests = [];
  const server = await listen(async (req, res) => {
    const raw = await body(req);
    requests.push(JSON.parse(raw));
    if (requests.length === 1) toolCallStream(res, '{"page_', 'number":99}');
    else textStream(res, '没有这一页。');
  });
  try {
    const pages = ['只有一页'];
    const result = await runToolLoop({
      messages: [{role: 'user', content: '第 99 页讲了什么？'}],
      tools: PAPER_TOOLS,
      callModel: await modelCall(server.port),
      executeTool: call => getPaperPage(pages, call.function.arguments)
    });
    assert.equal(result.text, '没有这一页。');
    const toolMessage = requests[1].messages.find(message => message.role === 'tool');
    assert.match(toolMessage.content, /超出范围/);
    assert.match(toolMessage.content, /1-1/);
  } finally { server.server.close(); }
});

test('fragmented tool arguments are assembled before execution', async () => {
  const requests = [];
  const server = await listen(async (req, res) => {
    const raw = await body(req);
    requests.push(JSON.parse(raw));
    if (requests.length === 1) toolCallStream(res, '{"page_', 'number":1}');
    else textStream(res, '第一页。');
  });
  try {
    const pages = ['第一页内容'];
    const result = await runToolLoop({
      messages: [{role: 'user', content: '第一页？'}],
      tools: PAPER_TOOLS,
      callModel: await modelCall(server.port),
      executeTool: call => getPaperPage(pages, call.function.arguments)
    });
    assert.equal(result.text, '第一页。');
    const toolMessage = requests[1].messages.find(message => message.role === 'tool');
    assert.match(toolMessage.content, /第一页内容/);
  } finally { server.server.close(); }
});

test('cancelling stops the tool loop before the next model call', async () => {
  let requests = 0;
  const server = await listen(async (req, res) => {
    await body(req); requests++;
    toolCallStream(res, '{"page_', 'number":1}');
  });
  try {
    let cancelled = false;
    await assert.rejects(
      runToolLoop({
        messages: [{role: 'user', content: '继续'}],
        tools: PAPER_TOOLS,
        callModel: await modelCall(server.port),
        executeTool: call => getPaperPage(['第一页'], call.function.arguments),
        isCancelled: () => cancelled,
        onTool: () => { cancelled = true; }
      }),
      error => error.code === 'ABORTED'
    );
    assert.equal(requests, 1, 'cancel must prevent another model round');
  } finally { server.server.close(); }
});

test('getPaperPage validates JSON, integers and bounds', () => {
  assert.equal(getPaperPage(['a', 'b'], '{"page_number":2}').text, 'b');
  assert.match(getPaperPage(['a'], 'not json').error, /合法 JSON/);
  assert.match(getPaperPage(['a'], '{"page_number":1.5}').error, /整数/);
  assert.match(getPaperPage(['a'], '{"page_number":0}').error, /超出范围/);
});
