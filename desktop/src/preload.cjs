const {contextBridge,ipcRenderer} = require('electron');
contextBridge.exposeInMainWorld('companion',{
  settings:()=>ipcRenderer.invoke('settings:get'),
  saveSettings:value=>ipcRenderer.invoke('settings:save',value),
  open:resume=>ipcRenderer.invoke('paper:open',resume),
  save:(id,state)=>ipcRenderer.invoke('paper:save',id,state),
  ask:(id,messages)=>ipcRenderer.invoke('ai:request',id,messages),
  cancel:id=>ipcRenderer.invoke('ai:cancel',id),
  onDelta:callback=>{const listener=(_event,value)=>callback(value);ipcRenderer.on('ai:delta',listener);return()=>ipcRenderer.removeListener('ai:delta',listener);},
  compile:(id,markdown,layout)=>ipcRenderer.invoke('tex:compile',id,markdown,layout),
  export:(id,kind)=>ipcRenderer.invoke('file:export',id,kind)
});
