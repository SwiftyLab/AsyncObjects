#!/usr/bin/env node
const { exec } = require('node:child_process');
const open = require('open');

const process = exec(
  'swift package \
    --disable-sandbox preview-documentation \
    --product AsyncObjects \
    --fallback-display-name AsyncObjects \
    --fallback-bundle-identifier com.SwiftyLab.AsyncObjects \
    --fallback-bundle-version 1 \
    --additional-symbol-graph-dir .build', {
    encoding: 'utf-8'
  }
);

process.stdout.on('data', function (data) {
  const url = /https?:\/\/\S+/i.exec(data);
  if (url) { open(`${url}`); }
  console.log(data);
});
