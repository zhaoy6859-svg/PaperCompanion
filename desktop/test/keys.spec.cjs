const {test,expect,_electron:electron}=require('@playwright/test');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),http=require('node:http');

function fixturePDF(){
  const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  const stream='BT /F1 20 Tf 48 730 Td (Research Paper) Tj /F1 12 Tf 0 -40 Td (A short abstract.) Tj ET';
  objects.push('<< /Length '+Buffer.byteLength(stream)+' >>\nstream\n'+stream+'\nendstream');
  let output='%PDF-1.4\n',offsets=[0];
  for(let i=0;i<objects.length;i++){offsets.push(Buffer.byteLength(output));output+=`${i+1} 0 obj\n${objects[i]}\nendobj\n`;}
  const xref=Buffer.byteLength(output);
  output+='xref\n0 6\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF';
  return Buffer.from(output);
}
function sse(res,text){
  res.writeHead(200,{'Content-Type':'text/event-stream'});
  res.write('data: '+JSON.stringify({choices:[{delta:{content:text}}]})+'\n\n');
  res.end('data: [DONE]\n\n');
}
async function listen(seen,name){
  const server=http.createServer(async(req,res)=>{let body='';for await(const c of req)body+=c;seen[name].push(req.headers.authorization);sse(res,'来自 '+name+' 的回答。');});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  return {server,url:'http://127.0.0.1:'+server.address().port};
}

test('switching the service URL never sends the previous service its key', async ({}, testInfo)=>{
  const home=await fs.mkdtemp(path.join(os.tmpdir(),'pc-keys-')),file=path.join(home,'paper.pdf');
  await fs.writeFile(file,fixturePDF());
  const seen={a:[],b:[]};
  const a=await listen(seen,'a'), b=await listen(seen,'b');
  let app;
  try{
    app=await electron.launch({args:[path.resolve(__dirname,'..')],env:{...process.env,PC_E2E:'1',PC_TEST_HOME:home,PC_TEST_PDF:file}});
    const page=await app.firstWindow();
    await expect(page.locator('#welcome')).toBeVisible();
    await page.waitForFunction(()=>window.__pcReady===true);
    await page.locator('#settings').click();
    await page.locator('#base-url').fill(a.url);
    await page.locator('#model').fill('mock');
    await page.locator('#api-key').fill('key-for-service-a');
    await page.getByRole('button',{name:'保存设置',exact:true}).click();
    await page.locator('#welcome-open').click();
    await page.locator('[data-level="beginner"]').click();
    await page.locator('#start-reading').click();
    await page.locator('#question').fill('服务 A 测试');
    await page.locator('#send').click();
    await expect(page.locator('#send')).toBeEnabled({timeout:20000});
    expect(seen.a[0]).toBe('Bearer key-for-service-a');

    // Change only the URL: the key field stays empty, and A's key must not follow.
    await page.locator('#settings').click();
    await page.locator('#base-url').fill(b.url);
    await expect(page.locator('#api-key')).toHaveValue('');
    await expect(page.locator('#key-hint')).toContainText('不会复用');
    await page.getByRole('button',{name:'保存设置',exact:true}).click();
    await page.locator('#question').fill('服务 B 测试');
    await page.locator('#send').click();
    await expect(page.locator('#send')).toBeEnabled({timeout:20000});
    expect(seen.b.length).toBeGreaterThan(0);
    expect(seen.b.every(value=>value===undefined)).toBeTruthy();
    expect(seen.b.includes('Bearer key-for-service-a')).toBeFalsy();
    await page.screenshot({path:testInfo.outputPath('key-isolation.png')});
  }finally{if(app)await app.close();a.server.close();b.server.close();}
});
