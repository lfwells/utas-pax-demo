const http = require('http');
const path = require('path');
const portfinder = require('portfinder');
const { exec } = require('child_process');
const fs = require('fs');

// Nexe bundles resources into a virtual file system
// We need to check if we are running in nexe to resolve paths correctly
const isNexe = process.hasOwnProperty('__nexe');
const baseDir = isNexe ? process.cwd() : __dirname;

// In nexe, we usually require local files relative to the entry point
const app = require('./utas_pax_demo_api/app');

async function start() {
  try {
    const port = await portfinder.getPortPromise({ port: 5000 });
    app.set('port', port);

    const server = http.createServer(app);

    server.listen(port, () => {
      const url = `http://localhost:${port}`;
      console.log('================================================');
      console.log('   UTAS PAX DEMO SERVER IS RUNNING');
      console.log(`   URL: ${url}`);
      console.log('================================================');
      console.log('Opening your default browser...');

      const startCmd = process.platform === 'darwin' ? 'open' :
                       process.platform === 'win32' ? 'start ""' :
                       'xdg-open';

      exec(`${startCmd} ${url}`);

      console.log('\nNOTE: Keep this terminal window open while using the app.');
      console.log('Press Ctrl+C to shut down the server.');
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();
