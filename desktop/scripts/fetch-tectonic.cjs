// Pinned Windows engine. Verified archive; no download occurs at application startup.
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
(async()=>{
 if(process.platform!=='win32')throw new Error('This script prepares the Windows release; run on Windows. macOS development can use an installed XeLaTeX.');
 const dir=path.resolve(__dirname,'../tools');await fs.mkdir(dir,{recursive:true});
 const url='https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%400.15.0/tectonic-0.15.0-x86_64-pc-windows-msvc.zip';
 const response=await fetch(url);if(!response.ok)throw new Error('Engine download failed: '+response.status);const data=Buffer.from(await response.arrayBuffer());
 if(crypto.createHash('sha256').update(data).digest('hex')!=='1d6bb76f049c8a3774f6e9d66e4b04e1a8c3dcb37527b6b41b7e894328e7bf29')throw new Error('Tectonic checksum mismatch');
 const archive=path.join(dir,'engine.zip');await fs.writeFile(archive,data);
 execFileSync('tar.exe',['-xf',archive,'-C',dir],{stdio:'inherit'});
 await fs.unlink(archive);
 const license=await fetch('https://raw.githubusercontent.com/tectonic-typesetting/tectonic/tectonic%400.15.0/LICENSE');if(!license.ok)throw new Error('Unable to fetch engine license');await fs.writeFile(path.join(dir,'TECTONIC-LICENSE.txt'),await license.text());
 const font=await fetch('https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf');if(!font.ok)throw new Error('Font download failed');const fontData=Buffer.from(await font.arrayBuffer());
 if(crypto.createHash('sha256').update(fontData).digest('hex')!=='2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b')throw new Error('Font checksum mismatch');await fs.writeFile(path.join(dir,'cjk.otf'),fontData);
 const fontLicense=await fetch('https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/LICENSE');if(!fontLicense.ok)throw new Error('Font license download failed');await fs.writeFile(path.join(dir,'NOTO-LICENSE.txt'),await fontLicense.text());
 execFileSync(path.join(dir,'tectonic.exe'),['--version'],{stdio:'inherit'});
})().catch(e=>{console.error(e.message);process.exit(1)});
