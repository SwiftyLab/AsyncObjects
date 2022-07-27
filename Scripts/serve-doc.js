#!/usr/bin/env node
const fs = require('fs');
const { execSync } = require('child_process');
const core = require('@actions/core');

const hostingDocGenCommandFormat = (basePath, outPath) =>
 `swift package --verbose \
   --allow-writing-to-directory .docc-build \
   generate-documentation \
   --product AsyncObjects \
   --disable-indexing \
   --transform-for-static-hosting \
   --hosting-base-path ${basePath} \
   --output-path ${outPath}`;

const hostingDocGenCommand = hostingDocGenCommandFormat(
  'AsyncObjects',
  '.docc-build'
);

core.startGroup(`Generating Documentation for Hosting Online`);
execSync(hostingDocGenCommand, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();

const package = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const hostingVersionedDocGenCommand = hostingDocGenCommandFormat(
  `AsyncObjects/${package.version}`,
  `.docc-build/${package.version}`
);

core.startGroup(`Generating ${package.version} Specific Documentation for Hosting Online`);
execSync(hostingVersionedDocGenCommand, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();
