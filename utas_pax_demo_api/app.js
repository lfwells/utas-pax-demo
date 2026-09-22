var createError = require('http-errors');
var express = require('express');
var path = require('path');
var logger = require('morgan');
var cors = require('cors');
var fs = require('fs');

var app = express();

app.use(cors());
app.use(logger('dev'));

// Enable SharedArrayBuffer for Unity 6 Multi-threading
app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
});

app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Helper getter to dynamically retrieve gamesPath set in launcher.js
function getGamesPath() {
  return app.get('gamesPath') || path.join(__dirname, 'games');
}

// Serve static files with correct MIME types
app.use("/games",(req, res, next) => {
  const gamesPath = getGamesPath();
  express.static(gamesPath, {
    setHeaders: (res, filePath) => {
      if (filePath.endsWith('.wasm')) {
        res.setHeader('Content-Type', 'application/wasm');
      }
    }, fallthrough: false
  })(req, res, next);
});

// Fallthrough handling for missing individual files within game folders
app.use("/games", (req, res, next) => {
  const gamesPath = getGamesPath();
  try {
    if (fs.existsSync(gamesPath)) {
      const gamesFolders = fs.readdirSync(gamesPath).filter(file => {
        const fullPath = path.join(gamesPath, file);
        return fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory();
      });

      const requestPath = req.path.split('/')[1]; // get first segment of request path
      if (gamesFolders.includes(requestPath)) {
        const filePath = path.join(gamesPath, req.path);
        if (!fs.existsSync(filePath)) {
          return res.status(404).send('File not found: ' + filePath);
        }
      }
    }
  } catch (e) {
    console.error('Error verifying game path files:', e.message);
  }
  next();
});
/*
const thumbsPath = path.join(__dirname, 'thumbs');
console.log('Thumbs path:', thumbsPath);
if (!fs.existsSync(thumbsPath)) {
    console.warn('WARNING: Thumbs path does not exist:', thumbsPath);
}

app.use("/thumbs", express.static(thumbsPath, {
  fallthrough: false,
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.jpg') || filePath.endsWith('.png')) {
      res.setHeader('Content-Type', 'image/jpeg');
    }
  }
}));*/

app.post("/execute", (req, res) => {
  const command = req.body.command;
  if (!command) {
    return res.status(400).send('Missing command parameter');
  }
  // Execute command and return stdout/stderr
  const exec = require('child_process').exec;
  exec(command, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error executing command: ${error}`);
      return res.status(500).send(`Error executing command: ${error.message}`);
    }
    res.send(stdout || stderr);
  });
});

const flutterPath = path.join(__dirname, '..', 'utas_pax_demo_flutter', 'build', 'web');
console.log('Flutter path:', flutterPath);
if (!fs.existsSync(flutterPath)) {
    console.warn('WARNING: Flutter path does not exist:', flutterPath);
}

app.use(express.static(flutterPath));

// Catch-all to handle Flutter routing
app.get('*', (req, res) => {
  const indexPath = path.join(flutterPath, 'index.html');
  if (fs.existsSync(indexPath)) {
    res.sendFile(indexPath);
  } else {
    res.status(404).send('Flutter build not found at ' + indexPath);
  }
});

module.exports = app;