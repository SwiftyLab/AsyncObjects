#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const process = require('process');
const archiver = require('archiver');
const readdirGlob = require('readdir-glob');
const { execSync } = require('child_process');
const core = require('@actions/core');

const package = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const command = `swift package --verbose generate-documentation \
  --product AsyncObjects \
  --fallback-display-name AsyncObjects \
  --fallback-bundle-identifier com.SwiftyLab.AsyncObjects \
  --fallback-bundle-version ${package.version} \
  --additional-symbol-graph-dir .build`;

core.startGroup(`Building documentation archive`);
execSync(command, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();

const doccGlobberer = readdirGlob('.', { pattern: '.build/plugins/Swift-DocC/outputs/*.doccarchive' });
doccGlobberer.on(
  'match',
  m => {
    core.startGroup(`Zipping documentation archive`);
    const docc = path.basename(m.relative);
    const name = path.basename(docc, path.extname(docc));
    const archiveName = [name, package.version].join('-');
    const output = fs.createWriteStream(`${archiveName}.doccarchive.zip`);
    const archive = archiver('zip');
    archive.directory(m.absolute, docc);
    archive.pipe(output);
    archive.finalize();
    const archivePath = path.normalize(path.join(process.cwd(), output.path));
    core.info(`Created archive '${archivePath}'`);
    core.endGroup();
  }
);

doccGlobberer.on('error', err => { core.error(err); });
