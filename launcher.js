const http = require('http');
const path = require('path');
const portfinder = require('portfinder');
const { exec } = require('child_process');

// Load the Express app
// When packaged with pkg, this will resolve to the internal snapshot
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
