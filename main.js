const { app, BrowserWindow } = require('electron');
const path = require('path');
const { fork } = require('child_process');
const http = require('http');
const portfinder = require('portfinder');

let apiProcess;

async function startBackend() {
  // Find an available port starting from 5000
  const port = await portfinder.getPortPromise({ port: 5000 });

  const scriptPath = path.join(__dirname, 'utas_pax_demo_api/bin/www');
  apiProcess = fork(scriptPath, [], {
    env: { ...process.env, PORT: port, NODE_ENV: 'production' },
    cwd: path.join(__dirname, 'utas_pax_demo_api')
  });

  console.log(`Backend starting on port: ${port}`);
  return port;
}

function createWindow(port) {
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    backgroundColor: '#000000',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  const apiUrl = `http://localhost:${port}`;

  // Poll the server until it's ready, then load the URL
  // Flutter will automatically detect this URL via Uri.base
  const checkServer = () => {
    http.get(apiUrl, (res) => {
      win.loadURL(apiUrl);
    }).on('error', () => {
      setTimeout(checkServer, 200); 
    });
  };

  checkServer();
}

app.whenReady().then(async () => {
  try {
    const port = await startBackend();
    createWindow(port);
  } catch (err) {
    console.error('Failed to start app:', err);
  }
});

app.on('window-all-closed', () => {
  if (apiProcess) apiProcess.kill();
  if (process.platform !== 'darwin') app.quit();
});

app.on('quit', () => {
  if (apiProcess) apiProcess.kill();
});
