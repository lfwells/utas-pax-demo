const { app, BrowserWindow } = require('electron');
const path = require('path');
const { fork } = require('child_process');

let apiProcess;
const API_PORT = 5999; // You can use a dynamic port if preferred

function startBackend() {
  // Path to your Node.js entry point
  // We use fork to run it as a separate process
  const scriptPath = path.join(__dirname, 'utas_pax_demo_api/bin/www');
  
  apiProcess = fork(scriptPath, [], {
    env: { 
      ...process.env, 
      PORT: API_PORT,
      NODE_ENV: 'production'
    }
  });

  apiProcess.on('error', (err) => {
    console.error('Failed to start backend:', err);
  });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    backgroundColor: '#000000',
    webPreferences: {
      // Security: Disable node integration in the frontend
      nodeIntegration: false,
      contextIsolation: true,
    }
  });

  // Load the Flutter web build
  const flutterIndex = path.join(__dirname, 'utas_pax_demo_flutter/build/web/index.html');
  win.loadFile(flutterIndex);

  // Optional: Open dev tools during development
  // win.webContents.openDevTools();
}

app.whenReady().then(() => {
  startBackend();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// Ensure the Node process dies when Electron exits
app.on('window-all-closed', () => {
  if (apiProcess) apiProcess.kill();
  if (process.platform !== 'darwin') app.quit();
});

app.on('quit', () => {
  if (apiProcess) apiProcess.kill();
});