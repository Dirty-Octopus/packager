const { contextBridge, ipcRenderer, webUtils } = require("electron");
contextBridge.exposeInMainWorld("packager", {
  info: () => ipcRenderer.invoke("app:info"),
  open: () => ipcRenderer.invoke("packages:open"),
  drop: (files) => ipcRenderer.invoke("packages:open", Array.from(files, (file) => webUtils.getPathForFile(file))),
  run: (id, operation, options, language) => ipcRenderer.invoke("packages:run", { id, operation, options, language }),
  cancel: (id) => ipcRenderer.invoke("packages:cancel", id),
  remove: (id) => ipcRenderer.invoke("packages:remove", id),
  directory: () => ipcRenderer.invoke("output:directory"),
  reveal: (id, target) => ipcRenderer.invoke("packages:reveal", { id, target }),
  preview: (id, path) => ipcRenderer.invoke("packages:preview", { id, path }),
  authorize: (id) => ipcRenderer.invoke("packages:authorize", id),
  onEvent: (callback) => { const listener = (_, event) => callback(event); ipcRenderer.on("job:event", listener); return () => ipcRenderer.removeListener("job:event", listener); },
  onOpen: (callback) => { const listener = (_, files) => callback(files); ipcRenderer.on("packages:opened", listener); return () => ipcRenderer.removeListener("packages:opened", listener); },
  onMenu: (callback) => { const listener = (_, action) => callback(action); ipcRenderer.on("app:menu", listener); return () => ipcRenderer.removeListener("app:menu", listener); },
});
