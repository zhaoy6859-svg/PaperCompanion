const crypto = require('node:crypto');
const LEVELS = {
  beginner: '完全陌生：补充背景，用通俗类比逐步解释术语、公式中每个符号，避免跳步。',
  intermediate: '了解基础：梳理方法、推理和关键证据，补足必要的推导。',
  advanced: '比较熟悉：深入推导、假设、创新、局限和与既有工作的关系。'
};
const TRANSLATION_PROMPT = '精翻，不能机翻。准确、自然、符合学术表达。保留标题、作者、章节层级、段落、列表和公式编号。数学必须用 LaTeX（$...$ 或 $$...$$），下标用 _{...}、上标用 ^{...}，不要输出 β10 这类纯文本或 Unicode 公式。所有表格必须输出为 Markdown 管道表：每行以 | 开头和结尾，第二行是 | --- | --- |；不得用空格对齐、制表符或逐行罗列；合并单元格用重复表头或留空。图表只翻译图注和表题，不要转写图内坐标轴刻度或图例数字。只输出译文，不添加原文页码标题和页眉页脚。无法可靠识别的公式标注【公式识别待核对】，不得猜测。';
function cacheKey(language, prompt) { return crypto.createHash('sha256').update(JSON.stringify([language.trim(), prompt, 'windows-v2'])).digest('hex'); }
function recentStart(threads) {
  let count = 0, start = threads.length;
  while (start > 0 && threads.length - start < 24) {
    const t = threads[start - 1]; const size = t.question.length + t.answer.length;
    if (count + size > 24000) break;
    count += size; start--;
  }
  return start;
}
function memoryBatch(threads, start, target) {
  let end = start, size = 0;
  while (end < target && end - start < 12) {
    const t = threads[end]; const next = t.question.length + t.answer.length;
    if (end > start && size + next > 24000) break;
    size += next; end++;
  }
  return end;
}
function escapeTex(text) {
  const map = {'\\':'\\textbackslash{}','{':'\\{','}':'\\}','$':'\\$','&':'\\&','#':'\\#','%':'\\%','_':'\\_','~':'\\textasciitilde{}','^':'\\textasciicircum{}'};
  return text.replace(/[\\{}$&#%_~^]/g, c => map[c]);
}
const MATH_DENY = new Set('input include includeonly write read openin openout closein closeout csname endcsname catcode def gdef edef xdef let futurelet newcommand renewcommand providecommand usepackage documentclass begin end directlua luaexec special shipout output everypar newif newcount newdimen newskip newbox setbox hbox vbox vtop halign valign noalign span omit par hskip vskip kern penalty raise lower moveleft moveright unhbox unvbox hss vss mark toks count dimen skip muskip advance multiply divide afterassignment aftergroup chardef mathchardef countdef dimendef skipdef muskipdef long outer global immediate protected expandafter noexpand detokenize scantokens errhelp message errmessage show showthe batchmode nonstopmode scrollmode errorstopmode openin closein'.split(' '));
function mathTex(text) {
  if (text.length > 16000 || /[%#\u0000-\u0008]/.test(text)) throw new Error('公式含不支持的字符，请核对原文');
  for (const m of text.matchAll(/\\([A-Za-z]+|.)/g)) {
    if (MATH_DENY.has(m[1])) throw new Error('公式含不支持的 LaTeX 命令：' + m[1]);
  }
  for (const m of text.matchAll(/\\(?:begin|end)\s*\{([^}]+)\}/g)) {
    if (!['aligned','cases','matrix','pmatrix','bmatrix','vmatrix','Vmatrix','smallmatrix'].includes(m[1])) throw new Error('公式环境不受支持');
  }
  return text;
}
function inline(text) {
  let out = '', end = 0;
  const pattern = /\$([^$\n]+)\$|\\\((.*?)\\\)/g;
  for (const m of text.matchAll(pattern)) {
    out += escapeTex(text.slice(end, m.index));
    out += '$' + mathTex(m[1] ?? m[2]) + '$'; end = m.index + m[0].length;
  }
  return out + escapeTex(text.slice(end)).replace(/\*\*(.+?)\*\*/g, '\\textbf{$1}');
}
function bodyTex(markdown) {
  const lines = markdown.replace(/\r/g, '').split('\n'); const out = []; let code = false;
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i].trim();
    if (line.startsWith('```')) { code = !code; continue; }
    if (code) { out.push('{\\ttfamily ' + escapeTex(lines[i]) + '}\\par'); continue; }
    if (line.startsWith('$$') || line.startsWith('\\[')) {
      const closing = line.startsWith('$$') ? '$$' : '\\]'; let math = line.slice(2);
      while (!math.includes(closing) && i + 1 < lines.length) math += '\n' + lines[++i];
      if (!math.includes(closing)) throw new Error('独立公式未闭合，请重试该页翻译');
      const end = math.indexOf(closing); out.push('\\[' + mathTex(math.slice(0, end)) + '\\]');
      if (math.slice(end + 2).trim()) out.push(inline(math.slice(end + 2)));
    } else if (/^#{1,6}\s/.test(line)) {
      const m = line.match(/^(#+)\s+(.*)$/); out.push('\\' + (m[1].length === 1 ? 'section' : m[1].length === 2 ? 'subsection' : 'subsubsection') + '*{' + inline(m[2]) + '}');
    } else if (line.startsWith('|') && i + 1 < lines.length && /^\s*\|?[\s:|-]+\|/.test(lines[i + 1])) {
      const rows = []; rows.push(line); i++;
      while (i + 1 < lines.length && lines[i + 1].trim().startsWith('|')) rows.push(lines[++i].trim());
      const cells = rows.map(r => r.replace(/^\||\|$/g, '').split('|').map(c => inline(c.trim())));
      const n = cells[0].length;
      out.push('\\begin{longtable}{' + Array(n).fill('p{\\dimexpr(\\linewidth-' + (2 * n) + '\\tabcolsep)/' + n + '\\relax}').join('') + '}\\toprule');
      out.push(cells.map(r => Array.from({length:n}, (_,j) => r[j] || '').join(' & ') + ' \\\\').join('\n'));
      out.push('\\bottomrule\\end{longtable}');
    } else if (/^[-*]\s|^\d+\.\s/.test(line)) out.push('\\noindent ' + inline(line) + '\\par');
    else out.push(line ? inline(line.replace(/^>\s?/, '')) : '\\par\n');
  }
  return out.join('\n') + '\n';
}
function needsTableRepair(text) {
  if (typeof text !== 'string' || !text.trim()) return false;
  if (/(^|\n)\s*\|[^\n]*\|/.test(text)) return false;
  const caption = /(^|\n)\s*(表|Table)\s*[0-9一二三四五六七八九十]+/i;
  const numericRows = /(^|\n)[^\n]*\d+\.\d+[^\n]*\s+[^\n]*\d+\.\d+/;
  return caption.test(text) && numericRows.test(text);
}

function latexDocument(markdown, layout = {}, platform = process.platform) {
  const clamp = (v, fallback, low, high) => Number.isFinite(v) ? Math.min(high, Math.max(low, v)) : fallback;
  const width = clamp(layout.width, 595.28, 250, 1500), height = clamp(layout.height, 841.89, 250, 1800);
  const cjk = platform === 'win32' ? 'Microsoft YaHei' : platform === 'darwin' ? 'PingFang SC' : 'Noto Sans CJK SC';
  let body = bodyTex(markdown);
  if (layout.columns === 2) body = '\\begin{multicols}{2}\n' + body.replaceAll('{longtable}', '{tabular}') + '\\end{multicols}\n';
  return String.raw`\documentclass[11pt]{article}
\usepackage{fontspec,xeCJK,amsmath,amssymb,mathtools,booktabs,longtable,array,multicol}
\setmainfont{Times New Roman}
\setCJKmainfont{${cjk}}
\usepackage[paperwidth=${width}bp,paperheight=${height}bp,margin=48bp]{geometry}
\usepackage[hidelinks]{hyperref}
\setlength{\parindent}{0pt}
\setlength{\parskip}{6pt}
\emergencystretch=3em
\begin{document}
${body}\end{document}
`;
}
function endpoint(base) {
  const url = new URL(base);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname))) throw new Error('接口地址必须是 HTTPS，或本机 HTTP 服务');
  if (url.username || url.password || url.search || url.hash) throw new Error('接口地址不能包含凭证、查询参数或片段');
  url.pathname = url.pathname.replace(/\/$/, '').replace(/\/chat\/completions$/, '') + '/chat/completions';
  return url.toString();
}
function apiError(code, message, extra = {}) {
  const error = new Error(message);
  error.code = code;
  Object.assign(error, extra);
  return error;
}
function originOf(baseURL) {
  try { return new URL(baseURL).origin; } catch { return ''; }
}
function isLocalOrigin(baseURL) {
  try { return ['localhost', '127.0.0.1', '[::1]'].includes(new URL(baseURL).hostname); } catch { return false; }
}
function keyForOrigin(keys, baseURL) {
  return (keys && keys[originOf(baseURL)]) || '';
}
function retryAfterMs(value) {
  if (!value) return 0;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, Math.min(30000, seconds * 1000));
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, Math.min(30000, date - Date.now())) : 0;
}
function sleep(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(apiError('ABORTED', '已取消'));
    const timer = setTimeout(() => { cleanup(); resolve(); }, ms);
    const onAbort = () => { clearTimeout(timer); cleanup(); reject(apiError('ABORTED', '已取消')); };
    function cleanup() { signal?.removeEventListener('abort', onAbort); }
    signal?.addEventListener('abort', onAbort, {once: true});
  });
}

async function attemptStream(settings, messages, signal, onDelta, tools) {
  const headers = {'Content-Type': 'application/json'};
  if (settings.apiKey) headers.Authorization = 'Bearer ' + settings.apiKey;
  const body = {model: settings.model, messages, stream: true, temperature: 0.2, max_tokens: 8192};
  if (Array.isArray(tools) && tools.length) { body.tools = tools; body.tool_choice = 'auto'; }
  let response;
  try {
    response = await fetch(endpoint(settings.baseURL), {method: 'POST', redirect: 'error', signal, headers, body: JSON.stringify(body)});
  } catch (error) {
    if (signal?.aborted || error?.name === 'AbortError') throw apiError('ABORTED', '已取消');
    throw apiError('NETWORK', '网络连接失败，请检查网络或接口地址', {cause: error});
  }
  if (!response.ok) {
    const retryAfter = retryAfterMs(response.headers.get('retry-after'));
    if (response.status === 401 || response.status === 403) {
      throw apiError('AUTH', 'API Key 无效或与该服务地址不匹配（HTTP ' + response.status + '），请在设置中检查');
    }
    if (response.status === 429 || response.status >= 500) {
      throw apiError('RETRYABLE', '服务暂时不可用（HTTP ' + response.status + '）', {retryAfterMs: retryAfter, status: response.status});
    }
    throw apiError('HTTP', '模型接口返回 HTTP ' + response.status + '，请检查模型、Key 和额度', {status: response.status});
  }
  let buffer = '', result = '', finished = false, emitted = false;
  const toolCalls = [];
  const decoder = new TextDecoder();
  function parse(line) {
    if (!line.startsWith('data:')) return;
    const raw = line.slice(5).trim();
    if (!raw || raw === '[DONE]') { if (raw) finished = true; return; }
    let data;
    try { data = JSON.parse(raw); } catch { throw apiError('STREAM', '模型返回了无法解析的数据'); }
    if (data.error) throw apiError('STREAM', '模型接口返回错误，请检查服务设置');
    const choice = data.choices?.[0];
    if (!choice) return;
    if (choice.finish_reason === 'length') throw apiError('LENGTH', '模型输出被截断，请使用更大输出额度的模型重试');
    const delta = choice.delta;
    if (typeof delta?.content === 'string' && delta.content) {
      result += delta.content; emitted = true; onDelta(delta.content);
    }
    if (Array.isArray(delta?.tool_calls)) {
      for (const part of delta.tool_calls) {
        const index = Number.isInteger(part.index) ? part.index : toolCalls.length;
        if (!toolCalls[index]) toolCalls[index] = {id: '', type: 'function', function: {name: '', arguments: ''}};
        const call = toolCalls[index];
        if (part.id) call.id = part.id;
        if (part.function?.name) call.function.name += part.function.name;
        if (part.function?.arguments) call.function.arguments += part.function.arguments;
      }
    }
    if (choice.finish_reason === 'stop' || choice.finish_reason === 'tool_calls') finished = true;
  }
  try {
    for await (const chunk of response.body) {
      buffer += decoder.decode(chunk, {stream: true});
      let end;
      while ((end = buffer.indexOf('\n')) !== -1) { parse(buffer.slice(0, end).trimEnd()); buffer = buffer.slice(end + 1); }
    }
    buffer += decoder.decode();
    if (buffer.trim()) parse(buffer.trim());
  } catch (error) {
    if (error?.code) throw Object.assign(error, {partial: result});
    if (signal?.aborted) throw apiError('ABORTED', '已取消', {partial: result});
    throw apiError('STREAM', '模型连接意外中断', {partial: result, cause: error});
  }
  if (!finished) throw apiError('STREAM', '模型连接意外中断，回答可能不完整', {partial: result});
  const calls = toolCalls.filter(Boolean).map(call => ({...call, function: {...call.function, arguments: call.function.arguments || '{}'}}));
  if (!result.trim() && !calls.length) throw apiError('EMPTY', '模型未返回内容');
  return {text: result, toolCalls: calls, finishReason: finished ? 'stop' : ''};
}

/**
 * Calls the model, retrying only recoverable failures that happened before any
 * text was streamed. Auth errors are never retried; a stream that already showed
 * text is never replayed, so the caller can keep the partial answer on screen.
 */
async function streamCompletion(settings, messages, signal, onDelta, tools = null) {
  if (!settings.apiKey && !isLocalOrigin(settings.baseURL)) {
    throw apiError('NO_KEY', '这个服务地址还没有保存 API Key，请在设置中填写');
  }
  const retries = Number.isInteger(settings.retries) ? Math.max(0, Math.min(5, settings.retries)) : 2;
  let emitted = false;
  for (let attempt = 1; ; attempt++) {
    try {
      return await attemptStream(settings, messages, signal, delta => { emitted = true; onDelta(delta); }, tools);
    } catch (error) {
      if (signal?.aborted || error.code === 'ABORTED') throw error;
      const retryable = error.code === 'RETRYABLE' || error.code === 'NETWORK' || (error.code === 'STREAM' && !emitted);
      if (!retryable || emitted || attempt > retries) throw error;
      const backoff = Math.min(8000, 500 * Math.pow(2, attempt - 1));
      const jittered = Math.round(backoff * (0.8 + Math.random() * 0.4));
      const delay = Math.max(error.retryAfterMs || 0, jittered);
      await sleep(delay, signal);
    }
  }
}

async function runToolLoop({messages, tools, callModel, executeTool, maxSteps = 4, isCancelled = () => false, onTool = () => {}}) {
  const conversation = messages.slice();
  for (let step = 0; step <= maxSteps; step++) {
    if (isCancelled()) throw apiError('ABORTED', '已取消');
    const reply = await callModel(conversation, tools);
    if (isCancelled()) throw apiError('ABORTED', '已取消');
    const calls = (reply.toolCalls || []).filter(call => call?.function?.name);
    if (!calls.length) return {text: reply.text || '', messages: conversation, steps: step};
    if (step === maxSteps) return {text: reply.text || '', messages: conversation, steps: step, truncated: true};
    conversation.push({
      role: 'assistant',
      content: reply.text || '',
      tool_calls: calls.map(call => ({id: call.id, type: 'function', function: {name: call.function.name, arguments: call.function.arguments || '{}'}}))
    });
    for (const call of calls) {
      if (isCancelled()) throw apiError('ABORTED', '已取消');
      const result = await executeTool(call);
      onTool(call, result);
      conversation.push({role: 'tool', tool_call_id: call.id, content: JSON.stringify(result)});
    }
  }
  return {text: '', messages: conversation, steps: maxSteps};
}

module.exports = {LEVELS, TRANSLATION_PROMPT, cacheKey, recentStart, memoryBatch, escapeTex, mathTex, bodyTex, latexDocument, needsTableRepair, endpoint, originOf, keyForOrigin, isLocalOrigin, streamCompletion, runToolLoop, apiError};
