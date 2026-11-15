const {app, BrowserWindow, ipcMain, dialog, safeStorage, shell, protocol, net} = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {pathToFileURL} = require('node:url');
const {TRANSLATION_PROMPT, endpoint, streamCompletion, latexDocument, needsTableRepair} = require('./core.cjs');
const testing = !app.isPackaged && process.env.PC_E2E === '1';
if (testing && process.env.PC_TEST_HOME) app.setPath('userData', process.env.PC_TEST_HOME);
const shared = app.isPackaged ? path.join(process.resourcesPath,'shared') : path.resolve(__dirname,'../../Resources');
let win, active, settings, outputs = new Map(); const requests = new Map();
const defaults = {baseURL:'https://api.deepseek.com', model:'deepseek-chat', language:'简体中文', prompt:TRANSLATION_PROMPT, vision:false};
protocol.registerSchemesAsPrivileged([{scheme:'companion',privileges:{standard:true,secure:true,supportFetchAPI:true}}]);
const root = () => app.getPath('userData');
async function atomic(file, data) { await fs.mkdir(path.dirname(file),{recursive:true}); const tmp = file + '.' + crypto.randomUUID() + '.tmp'; await fs.writeFile(tmp,data,{mode:0o600}); await fs.rename(tmp,file); }
async function readJSON(file, fallback) { try { return JSON.parse(await fs.readFile(file,'utf8')); } catch(e) { if (e.code === 'ENOENT') return fallback; throw new Error('本地数据读取失败，请备份后检查：' + path.basename(file)); } }
function publicSettings() { const {encryptedKey, ...rest} = settings; return {...rest,hasKey:!!encryptedKey}; }
function key() { if (!settings.encryptedKey) return ''; try { return safeStorage.decryptString(Buffer.from(settings.encryptedKey,'base64')); } catch { throw new Error('无法解密 API Key，请在设置中重新输入'); } }
function stop() { for (const r of requests.values()) r.abort(); requests.clear(); }
function requireDoc(id) { if (!active || id !== active.id) throw new Error('论文已切换，请重试'); return active; }
async function openPDF(file) {
  stop();
  const bytes = await fs.readFile(file);
  if (bytes.length > 150 * 1024 * 1024) throw new Error('请打开小于 150 MB 的 PDF');
  if (!bytes.subarray(0,1024).includes(Buffer.from('%PDF-'))) throw new Error('文件不是有效的 PDF');
  const id = crypto.createHash('sha256').update(bytes).digest('hex');
  const saved = await readJSON(path.join(root(),'papers',id + '.json'), null);
  active = {id,file};
  settings.lastFile = file; await atomic(path.join(root(),'settings.json'), JSON.stringify(settings));
  return {id,title:path.basename(file,'.pdf'),bytes:new Uint8Array(bytes),state:saved || {level:null,threads:[],memory:null,caches:{},page:1}};
}
function spawnCompile(command,args,cwd) {
  return new Promise((resolve,reject) => {
    const child = spawn(command,args,{cwd,windowsHide:true,shell:false}); let log = '';
    child.stdout.on('data', b => { log = (log + b).slice(-12000); }); child.stderr.on('data', b => { log = (log + b).slice(-12000); });
    const timer = setTimeout(() => {
      if (process.platform === 'win32' && child.pid) spawn('taskkill',['/pid',String(child.pid),'/T','/F'],{windowsHide:true}); else child.kill('SIGKILL');
      reject(new Error('LaTeX 编译超时；首次运行需联网下载排版资源，请稍后重试。'));
    },240000);
    child.on('error',e => { clearTimeout(timer); reject(e); });
    child.on('close',code => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error('LaTeX 排版失败。可导出源码检查公式。\n' + log.slice(-2000))); });
  });
}
async function compile(markdown, layout) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(),'paper-companion-')); let tex = latexDocument(markdown,layout);
  const toolsDir = app.isPackaged ? path.join(process.resourcesPath,'tex') : path.resolve(__dirname,'../tools');
  try { await fs.copyFile(path.join(toolsDir,'cjk.otf'),path.join(dir,'cjk.otf')); tex = tex.replace(/\\setCJKmainfont\{[^}]+\}/, '\\setCJKmainfont{cjk.otf}'); } catch(e) { if(e.code !== 'ENOENT') throw e; }
  const id = crypto.randomUUID(); outputs.set(id,{dir,tex,pdf:null});
  await fs.writeFile(path.join(dir,'paper.tex'),tex);
  const bundled = path.join(app.isPackaged ? path.join(process.resourcesPath,'tex') : path.resolve(__dirname,'../tools'),'tectonic' + (process.platform === 'win32' ? '.exe' : ''));
  try {
    try { await fs.access(bundled); await spawnCompile(bundled,['--untrusted','--outdir',dir,'paper.tex'],dir); }
    catch(e) {
      if (e.code !== 'ENOENT') throw e;
      const engine = process.platform === 'darwin' ? '/Library/TeX/texbin/xelatex' : 'xelatex';
      for (let i=0;i<2;i++) await spawnCompile(engine,['-no-shell-escape','-interaction=nonstopmode','-halt-on-error','paper.tex'],dir);
    }
    const pdf = await fs.readFile(path.join(dir,'paper.pdf')); outputs.get(id).pdf = pdf;
    return {id,bytes:new Uint8Array(pdf)};
  } catch(e) { return {id,error:e.code === 'ENOENT' ? '未找到排版引擎。请使用包含 Tectonic 的 Windows 安装包，或安装 TeX Live 并将 xelatex 加入 PATH。' : e.message}; }
}
function handle(channel, callback) {
  ipcMain.handle(channel,async(event,...args) => {
    if (event.sender !== win?.webContents || !event.senderFrame.url.startsWith('file://')) throw new Error('无效的窗口请求');
    return callback(...args);
  });
}
const LEGACY_PROMPT = '精翻，不能机翻。准确、自然、符合学术表达。保留标题、作者、章节层级、段落、表格及公式编号。只输出译文，不添加原文页码标题和页眉页脚。数学必须用 $...$ 或 $$...$$ 的 LaTeX 表达。无法可靠识别的公式标注【公式识别待核对】，不得猜测。';
app.whenReady().then(async() => {
  settings = {...defaults,...await readJSON(path.join(root(),'settings.json'),{})};
  if (settings.prompt === LEGACY_PROMPT) settings.prompt = TRANSLATION_PROMPT;
  protocol.handle('companion',request => {
    const url = new URL(request.url); const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    const file = path.resolve(shared,rel);
    if (url.host !== 'assets' || !file.startsWith(shared + path.sep)) return new Response('Not found',{status:404});
    return net.fetch(pathToFileURL(file).toString());
  });
  win = new BrowserWindow({width:1440,height:960,minWidth:1000,minHeight:700,title:'论文伴侣',backgroundColor:'#faf9f6',
    webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true}});
  win.setMenuBarVisibility(false);
  win.webContents.setWindowOpenHandler(() => ({action:'deny'}));
  win.webContents.on('will-navigate',(event,url) => { event.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); });
  win.webContents.session.setPermissionRequestHandler((_wc,_permission,callback) => callback(false));
  handle('settings:get',() => publicSettings());
  handle('settings:save',async(value) => {
    endpoint(String(value.baseURL)); if (!String(value.model).trim()) throw new Error('请输入模型名称');
    const next = {...settings,baseURL:String(value.baseURL).trim(),model:String(value.model).trim(),language:String(value.language).trim() || '简体中文',prompt:String(value.prompt).trim() || TRANSLATION_PROMPT,vision:!!value.vision};
    if (value.apiKey) { if(!safeStorage.isEncryptionAvailable()) throw new Error('系统凭证加密不可用，无法安全保存 Key'); next.encryptedKey = safeStorage.encryptString(String(value.apiKey)).toString('base64'); }
    if (value.clearKey) delete next.encryptedKey;
    await atomic(path.join(root(),'settings.json'),JSON.stringify(next)); settings=next; return publicSettings();
  });
  handle('paper:open',async(resume=false) => {
    let file;
    if (testing && process.env.PC_TEST_PDF) file = process.env.PC_TEST_PDF;
    else if (resume && settings.lastFile) file=settings.lastFile;
    else { const result=await dialog.showOpenDialog(win,{properties:['openFile'],filters:[{name:'PDF 文献',extensions:['pdf']}]}); if(result.canceled) return null; file=result.filePaths[0]; }
    return openPDF(file);
  });
  handle('paper:save',async(id,state) => { requireDoc(id); const data=JSON.stringify(state); if(data.length>40*1024*1024) throw new Error('文献记录过大，请先导出报告'); await atomic(path.join(root(),'papers',id+'.json'),data); });
  handle('ai:cancel',(_id) => { if (_id) requests.get(_id)?.abort(); else stop(); });
  handle('ai:request',async(id,messages) => {
    if (typeof id !== 'string' || requests.has(id)) throw new Error('重复请求');
    const controller=new AbortController(); requests.set(id,controller); const timeout=setTimeout(()=>controller.abort(),300000);
    try { return await streamCompletion({...settings,apiKey:key()},messages,controller.signal,delta=>win?.webContents.send('ai:delta',{id,delta})); }
    finally {clearTimeout(timeout);requests.delete(id);}
  });
  handle('text:needs-table-repair',(text) => typeof text === 'string' && text.length < 2000000 && needsTableRepair(text));
  handle('tex:compile',async(id,markdown,layout) => { requireDoc(id); if(typeof markdown !== 'string'||markdown.length>2000000) throw new Error('文档内容过长'); return compile(markdown,layout); });
  handle('file:export',async(id,kind) => {
    const out=outputs.get(id); if(!out) throw new Error('请先生成文档');
    const ext=kind==='tex'?'tex':'pdf'; let data=ext==='tex'?out.tex:out.pdf; if(!data) throw new Error('PDF 尚未生成，可导出 LaTeX 源码');
    const result=testing?{filePath:path.join(root(),'export.'+ext)}:await dialog.showSaveDialog(win,{defaultPath:'论文伴侣.'+ext,filters:[{name:ext.toUpperCase(),extensions:[ext]}]});
    if(result.canceled||!result.filePath) return false;
    if (ext === 'tex' && data.includes('\\setCJKmainfont{cjk.otf}')) {
      const destination = path.dirname(result.filePath);
      await fs.copyFile(path.join(out.dir,'cjk.otf'),path.join(destination,'paper-companion-cjk.otf'));
      const fontLicense = path.join(app.isPackaged ? path.join(process.resourcesPath,'tex') : path.resolve(__dirname,'../tools'),'NOTO-LICENSE.txt');
      await fs.copyFile(fontLicense,path.join(destination,'paper-companion-font-license.txt'));
      data = data.replace('\\setCJKmainfont{cjk.otf}','\\setCJKmainfont{paper-companion-cjk.otf}');
    }
    await fs.writeFile(result.filePath,data); return true;
  });
  await win.loadFile(path.join(__dirname,'index.html'));
});
app.on('window-all-closed',() => app.quit());
app.on('before-quit',() => {stop(); for(const out of outputs.values()) fs.rm(out.dir,{recursive:true,force:true}).catch(()=>{});});
