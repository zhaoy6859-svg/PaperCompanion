// Validate the shipped executable and bundled assets, not only the development tree.
const { _electron: electron, expect } = require('@playwright/test');
const path = require('node:path');
const fs = require('node:fs/promises');
(async () => {
  const executablePath = path.resolve(__dirname,'../../dist/windows/win-unpacked/PaperCompanion.exe');
  const app = await electron.launch({executablePath,args:[],timeout:60000});
  try {
    const page = await app.firstWindow();
    await expect(page.locator('#welcome')).toBeVisible();
    await expect.poll(() => page.locator('#welcome > img').evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true);
    await page.locator('#settings').click();
    await expect(page.locator('#settings-dialog')).toBeVisible();
    await expect(page.locator('#base-url')).toHaveValue('https://api.deepseek.com');
    await page.locator('#close-settings').click();
    const folder = path.resolve(__dirname,'../test-results/packaged');
    await fs.mkdir(folder,{recursive:true});
    await page.screenshot({path:path.join(folder,'welcome.png')});
    console.log('PASS: packaged executable, resource protocol, companion artwork and settings UI');
  } finally { await app.close(); }
})().catch(error => { console.error(error); process.exit(1); });
