const {test}=require('node:test');const assert=require('node:assert/strict');const http=require('node:http');
const {latexDocument,mathTex,endpoint,recentStart,memoryBatch,cacheKey,streamCompletion,needsTableRepair,TRANSLATION_PROMPT}=require('../src/core.cjs');
test('TeX escapes model prose and rejects file/process commands in formulas',()=>{
  const tex=latexDocument('# Title\n\nText 50% & $\\frac{1}{n}$\n\n$$\\sum_{i=1}^n x_i$$\n\n| A | B |\n| --- | --- |\n| a | b |',{width:612,height:792});
  assert.match(tex,/paperwidth=612bp/);assert.match(tex,/50\\% \\&/);assert.match(tex,/\\begin\{longtable\}/);assert.doesNotMatch(tex,/clearpage|原文第/);
  for(const bad of ['\\input{secret}','\\write18{cmd}','\\csname input\\endcsname','\\begin{document}']) assert.throws(()=>mathTex(bad));
});
test('bounded recent history, memory batches, language-separated caches',()=>{
  const threads=Array.from({length:100},()=>({question:'q',answer:'a'.repeat(1500)}));const start=recentStart(threads);
  assert.ok(start>75);assert.ok(memoryBatch(threads,0,start)<=12);assert.notEqual(cacheKey('中文','精翻'),cacheKey('English','精翻'));
  assert.equal(recentStart([{question:'q',answer:'x'.repeat(30000)}]),1);
});
test('endpoint validates HTTPS and localhost and avoids duplicate completion path',()=>{
  assert.equal(endpoint('https://api.example.com/v1/'),'https://api.example.com/v1/chat/completions');
  assert.equal(endpoint('http://localhost:11434/v1/chat/completions'),'http://localhost:11434/v1/chat/completions');
  assert.throws(()=>endpoint('http://example.com'));assert.throws(()=>endpoint('https://user:pass@example.com'));
});
test('stream parser handles fragmented UTF-8, rejects truncation and interrupted streams',async()=>{
  let mode='normal';const server=http.createServer((_req,res)=>{res.writeHead(200,{'Content-Type':'text/event-stream'});const s='data: '+JSON.stringify({choices:[{delta:{content:'公式 θ'}}]})+'\n\n';const b=Buffer.from(s);res.write(b.subarray(0,54));res.write(b.subarray(54));if(mode==='normal')res.write('data: [DONE]\n\n');if(mode==='length')res.write('data: {"choices":[{"finish_reason":"length"}]}\n\n');res.end();});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));const config={baseURL:'http://127.0.0.1:'+server.address().port,model:'mock'};
  try{let received='';assert.equal(await streamCompletion(config,[],undefined,s=>received+=s),'公式 θ');assert.equal(received,'公式 θ');mode='length';await assert.rejects(streamCompletion(config,[],undefined,()=>{}),/截断/);mode='broken';await assert.rejects(streamCompletion(config,[],undefined,()=>{}),/中断/);}finally{server.close();}
});

test('flattened tables are detected and the prompt demands pipe tables',()=>{
  assert.equal(needsTableRepair('表 3. ZIP 和 ZIGP 模型的贝叶斯比较。\n模型 DIC B\nZIP 1343.6443 - 679.3078\nZIGP 1050.6254 - 526.3694'),true);
  assert.equal(needsTableRepair('| 模型 | DIC | B |\n| --- | --- | --- |\n| ZIP | 1343.6443 | -679.3078 |'),false);
  assert.equal(needsTableRepair('表 1. 无数据的说明。\n这里没有数字。'),false);
  assert.equal(needsTableRepair('普通段落 1.23 这个词不是表格'),false);
  assert.match(TRANSLATION_PROMPT,/Markdown 管道表/);
  assert.match(TRANSLATION_PROMPT,/下标用 _\{\.\.\.\}/);
});
