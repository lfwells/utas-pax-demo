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

// Serve static files with correct MIME types
const gamesPath = path.join(__dirname, 'games');
console.log('Games path:', gamesPath);
if (!fs.existsSync(gamesPath)) {
    console.warn('WARNING: Games path does not exist:', gamesPath);
}

app.use(express.static(gamesPath, {
  setHeaders: (res, path) => {
    if (path.endsWith('.wasm')) {
      res.setHeader('Content-Type', 'application/wasm');
    }
  }
}));

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
