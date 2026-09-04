var createError = require('http-errors');
var express = require('express');
var path = require('path');
var logger = require('morgan');
var cors = require('cors');

var app = express();

app.use(cors());
app.use(logger('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(express.static(path.join(__dirname, 'games')));
app.use(express.static(path.join(__dirname, '../utas_pax_demo_flutter/build/web')));


module.exports = app;
