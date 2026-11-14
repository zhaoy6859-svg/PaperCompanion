const crypto = require('node:crypto');
const LEVELS = {
  beginner: '完全陌生：补充背景，用通俗类比逐步解释术语、公式中每个符号，避免跳步。',
  intermediate: '了解基础：梳理方法、推理和关键证据，补足必要的推导。',
  advanced: '比较熟悉：深入推导、假设、创新、局限和与既有工作的关系。'
};
const TRANSLATION_PROMPT = '精翻，不能机翻。准确、自然、符合学术表达。保留标题、作者、章节层级、段落、表格及公式编号。只输出译文，不添加原文页码标题和页眉页脚。数学必须用 $...$ 或 $$...$$ 的 LaTeX 表达。无法可靠识别的公式标注【公式识别待核对】，不得猜测。';
function cacheKey(language, prompt) { return crypto.createHash('sha256').update(JSON.stringify([language.trim(), prompt, 'windows-v1'])).digest('hex'); }
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
const MATH_COMMANDS = new Set(('frac dfrac tfrac sqrt sum prod int iint iiint oint lim min max arg log ln exp sin cos tan cot sec csc sinh cosh tanh arcsin arccos arctan inf sup det dim gcd Pr E mathbb mathcal mathrm mathbf mathit mathsf mathtt boldsymbol operatorname text textrm textbf hat widehat bar overline underline vec tilde widetilde dot ddot left right middle big Big bigg Bigg bigl bigr Bigl Bigr biggl biggr Biggl Biggr alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega in notin ni subset subseteq supset supseteq cup cap emptyset varnothing forall exists nexists neg land lor implies iff to mapsto rightarrow leftarrow leftrightarrow Rightarrow Leftarrow Leftrightarrow uparrow downarrow le leq ge geq ne neq approx sim simeq equiv propto ll gg pm mp times cdot div circ bullet ast star otimes oplus partial nabla infty ell hbar Re Im angle perp parallel mid vert Vert lvert rvert lVert rVert langle rangle lceil rceil lfloor rfloor ldots cdots vdots ddots quad qquad space tag label nonumber notag begin end substack overset underset underbrace overbrace limits nolimits binom dbinom tbinom cases aligned align matrix pmatrix bmatrix vmatrix Vmatrix smallmatrix').split(' '));
function mathTex(text) {
  if (text.length > 16000 || /[%#\u0000-\u0008]/.test(text)) throw new Error('公式含不支持的字符，请核对原文');
  for (const m of text.matchAll(/\\([A-Za-z]+|.)/g)) {
    if (!MATH_COMMANDS.has(m[1]) && !['{','}','_','%','$','#','&',',',';',':','!',' ','|','\\'].includes(m[1])) throw new Error('公式含不支持的 LaTeX 命令：' + m[1]);
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
async function streamCompletion(settings, messages, signal, onDelta) {
  const response = await fetch(endpoint(settings.baseURL), {method:'POST', redirect:'error', signal,
    headers:{'Content-Type':'application/json', ...(settings.apiKey ? {Authorization:'Bearer ' + settings.apiKey} : {})},
    body:JSON.stringify({model:settings.model, messages, stream:true, temperature:0.2, max_tokens:8192})});
  if (!response.ok) throw new Error('模型接口返回 HTTP ' + response.status + '，请检查模型、Key 和额度');
  let buffer = '', result = '', finished = false; const decoder = new TextDecoder();
  function parse(line) {
    if (!line.startsWith('data:')) return;
    const raw = line.slice(5).trim(); if (!raw || raw === '[DONE]') { if(raw) finished = true; return; }
    const data = JSON.parse(raw); if (data.error) throw new Error('模型接口返回错误，请检查服务设置');
    const choice = data.choices?.[0];
    if (choice?.finish_reason === 'length') throw new Error('模型输出被截断，请使用更大输出额度的模型重试');
    const delta = choice?.delta?.content;
    if (typeof delta === 'string') { result += delta; onDelta(delta); }
    if (choice?.finish_reason === 'stop') finished = true;
  }
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, {stream:true}); let end;
    while ((end = buffer.indexOf('\n')) !== -1) { parse(buffer.slice(0,end).trimEnd()); buffer = buffer.slice(end+1); }
  }
  buffer += decoder.decode(); if (buffer.trim()) parse(buffer.trim());
  if (!finished) throw new Error('模型连接意外中断，未保存不完整回答；请重试');
  if (!result.trim()) throw new Error('模型未返回内容');
  return result;
}
module.exports = {LEVELS, TRANSLATION_PROMPT, cacheKey, recentStart, memoryBatch, escapeTex, mathTex, bodyTex, latexDocument, endpoint, streamCompletion};
