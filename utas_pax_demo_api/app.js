var createError = require('http-errors');
var express = require('express');
var path = require('path');
var logger = require('morgan');
var cors = require('cors');

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
app.use(express.static(path.join(__dirname, 'games'), {
  setHeaders: (res, path) => {
    if (path.endsWith('.wasm')) {
      res.setHeader('Content-Type', 'application/wasm');
    }
  }
}));

app.use(express.static(path.join(__dirname, '../utas_pax_demo_flutter/build/web')));

// Catch-all to handle Flutter routing
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../utas_pax_demo_flutter/build/web/index.html'));
});

module.exports = app;
