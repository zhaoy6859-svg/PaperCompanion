// Pinned Windows engine. Verified archive; no download occurs at application startup.
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
(async()=>{
 if(process.platform!=='win32')throw new Error('This script prepares the Windows release; run on Windows. macOS development can use an installed XeLaTeX.');
 const dir=path.resolve(__dirname,'../tools');await fs.mkdir(dir,{recursive:true});
 const url='https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%400.15.0/tectonic-0.15.0-x86_64-pc-windows-msvc.zip';
 const response=await fetch(url);if(!response.ok)throw new Error('Engine download failed: '+response.status);const data=Buffer.from(await response.arrayBuffer());
 if(crypto.createHash('sha256').update(data).digest('hex')!=='1d6bb76f049c8a3774f6e9d66e4b04e1a8c3dcb37527b6b41b7e894328e7bf29')throw new Error('Tectonic checksum mismatch');
 const archive=path.join(dir,'engine.zip');await fs.writeFile(archive,data);
 const quote=s=>"'"+s.replaceAll("'","''")+"'";
 execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',`Expand-Archive -LiteralPath ${quote(archive)} -DestinationPath ${quote(dir)} -Force`],{stdio:'inherit'});
 await fs.unlink(archive);
 const license=await fetch('https://raw.githubusercontent.com/tectonic-typesetting/tectonic/tectonic%400.15.0/LICENSE');if(!license.ok)throw new Error('Unable to fetch engine license');await fs.writeFile(path.join(dir,'TECTONIC-LICENSE.txt'),await license.text());
 execFileSync(path.join(dir,'tectonic.exe'),['--version'],{stdio:'inherit'});
})().catch(e=>{console.error(e.message);process.exit(1)});
