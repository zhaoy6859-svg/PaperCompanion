const {test,expect,_electron:electron}=require('@playwright/test');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),http=require('node:http');
function fixturePDF(){
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
 const stream='BT /F1 20 Tf 48 730 Td (Research Paper) Tj /F1 12 Tf 0 -40 Td (Empirical risk is the average loss on observed samples.) Tj 0 -24 Td (The parameter theta minimizes this objective.) Tj ET';objects.push('<< /Length '+Buffer.byteLength(stream)+' >>\nstream\n'+stream+'\nendstream');
 let output='%PDF-1.4\n',offsets=[0];for(let i=0;i<objects.length;i++){offsets.push(Buffer.byteLength(output));output+=`${i+1} 0 obj\n${objects[i]}\nendobj\n`;}const xref=Buffer.byteLength(output);output+='xref\n0 6\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF';return Buffer.from(output);
}
test('Windows desktop: welcome, PDF, familiarity, chat, translation, report, persistence',async({ },testInfo)=>{
 const home=await fs.mkdtemp(path.join(os.tmpdir(),'pc-e2e-')),file=path.join(home,'research.pdf');await fs.writeFile(file,fixturePDF());
 const calls=[];let failNext=false;
 const server=http.createServer(async(req,res)=>{let body='';for await(const c of req)body+=c;const request=JSON.parse(body);calls.push(request);if(failNext){failNext=false;res.writeHead(500);res.end();return;}const system=request.messages[0].content;let answer;
  if(system.includes('学习记忆'))answer='早期记忆：用户关注经验风险、参数含义和泛化误差。';
  else if(system.includes('学习报告'))answer='# 学习报告\n\n## 核心概念\n经验风险是平均损失。\n\n$$\\widehat R_n=\\frac{1}{n}\\sum_{i=1}^n\\ell_i$$\n\n## 待追问\n如何评估泛化误差？';
  else if(system.includes('目标语言'))answer='# Research Paper\n\n## Empirical risk\nThe **average loss** is defined by\n\n$$\\widehat R_n=\\frac{1}{n}\\sum_{i=1}^n\\ell_i$$\n\n| Symbol | Meaning |\n| --- | --- |\n| $n$ | sample size |';
  else answer='## 经验风险\n\n**平均损失**衡量训练样本误差。\n\n$$\\widehat R_n=\\frac{1}{n}\\sum_{i=1}^n\\ell_i$$\n\n<script>window.hacked=true</script>';
  if(system.includes('目标语言'))await new Promise(r=>setTimeout(r,700));
  res.writeHead(200,{'Content-Type':'text/event-stream'});for(const delta of [answer.slice(0,12),answer.slice(12)])res.write('data: '+JSON.stringify({choices:[{delta:{content:delta}}]})+'\n\n');res.end('data: [DONE]\n\n');
 });await new Promise(r=>server.listen(0,'127.0.0.1',r));
 let app;const launch=()=>electron.launch({args:[path.resolve(__dirname,'..')],env:{...process.env,PC_E2E:'1',PC_TEST_HOME:home,PC_TEST_PDF:file}});
 try{
  app=await launch();let page=await app.firstWindow();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await expect(page.locator('#welcome')).toBeVisible();await page.screenshot({path:testInfo.outputPath('welcome.png')});
  await page.locator('#settings').click();await page.locator('#base-url').fill('http://127.0.0.1:'+server.address().port+'/v1');await page.locator('#model').fill('mock');await page.locator('#language').fill('English');await page.getByRole('button',{name:'保存设置',exact:true}).click();
  await page.locator('#welcome-open').click();await expect(page.locator('#level-dialog')).toBeVisible();await page.screenshot({path:testInfo.outputPath('familiarity.png')});await page.locator('[data-level="beginner"]').click();await page.locator('#start-reading').click();
  await expect(page.locator('.pdf-page canvas')).toHaveCount(1);await expect(page.locator('.textLayer')).toContainText('Empirical risk');
  await page.locator('#question').fill('请解释经验风险');await page.locator('#send').click();await expect(page.locator('#conversation .katex')).toBeVisible();await expect(page.locator('#send')).toBeEnabled();expect(await page.evaluate(()=>window.hacked)).toBeUndefined();
  expect(calls.at(-1).messages[0].content).toContain('完全陌生');
  await page.locator('#translate').click();await expect(page.locator('#progress')).toBeVisible();
  expect(await page.locator('#progress').evaluate(el=>getComputedStyle(el).pointerEvents)).toBe('none');
  await page.locator('#question').click();await expect(page.locator('#question')).toBeFocused();
  await page.locator('#translate').click();await expect(page.locator('#translate')).toHaveText('精翻全文');
  await page.locator('#translate').click();await expect(page.locator('#view-label')).toHaveText('LaTeX 译文',{timeout:240000});await expect(page.locator('header')).toBeInViewport();await expect(page.locator('#ask-form')).toBeInViewport();await page.screenshot({path:testInfo.outputPath('translation-chat.png')});
  expect(calls.some(c=>c.messages[0].content.includes('目标语言：English'))).toBeTruthy();
  await page.locator('#export').click();await page.locator('#export-pdf').click();await expect(page.locator('#status')).toHaveText('已保存到本地 · PDF');expect((await fs.readFile(path.join(home,'export.pdf'))).subarray(0,5).toString()).toBe('%PDF-');await page.locator('#export-tex').click();await expect(page.locator('#status')).toHaveText('已保存到本地 · TEX');expect(await fs.readFile(path.join(home,'export.tex'),'utf8')).toContain('\\frac{1}{n}');if(process.platform==='win32')await fs.access(path.join(home,'paper-companion-cjk.otf'));await page.locator('#close-export').click();
  await page.locator('#switch').click();await expect(page.locator('#view-label')).toHaveText('原文');await page.locator('#switch').click();await expect(page.locator('#view-label')).toHaveText('LaTeX 译文');
  await page.locator('#report').click();await expect(page.locator('#export-dialog')).toBeVisible({timeout:240000});await expect(page.locator('#export-pdf')).toBeEnabled();await page.locator('#export-tex').click();await expect(page.locator('#status')).toHaveText('已保存到本地 · TEX');expect(await fs.readFile(path.join(home,'export.tex'),'utf8')).toContain('学习报告');await page.locator('#close-export').click();
  failNext=true;await page.locator('#question').fill('重试测试');await page.locator('#send').click();await expect(page.locator('#status')).toContainText('HTTP 500');await expect(page.locator('#question')).toHaveValue('重试测试');
  expect(errors).toEqual([]);await app.close();app=null;
  // Seed a long saved history to exercise summary batching through the actual UI.
  const dir=path.join(home,'papers'),files=await fs.readdir(dir),statePath=path.join(dir,files[0]);const state=JSON.parse(await fs.readFile(statePath,'utf8'));expect(state.level).toBe('beginner');expect(state.threads).toHaveLength(1);state.threads=Array.from({length:35},(_,i)=>({question:'问题'+i,answer:'需要记住的解释。'.repeat(160),page:0}));await fs.writeFile(statePath,JSON.stringify(state));
  app=await launch();page=await app.firstWindow();await page.locator('#resume').click();await expect(page.locator('#level-dialog')).not.toBeVisible();await expect(page.locator('#conversation .turn')).toHaveCount(35);await page.locator('#question').fill('继续解释');await page.locator('#send').click();await expect(page.locator('#send')).toBeEnabled({timeout:30000});
  expect(calls.some(c=>c.messages[0].content.includes('学习记忆'))).toBeTruthy();const latest=calls.at(-1);expect(latest.messages.length).toBeLessThanOrEqual(51);expect(latest.messages.some(m=>m.content.includes('此前交流摘要'))).toBeTruthy();
 }finally{if(app)await app.close();server.close();}
});
