#!/usr/bin/env node
const process = require('process');
const { execSync } = require('child_process');
const core = require('@actions/core');

const args = process.argv.slice(2).join(' ');
const command = `swift build ${args} --verbose \
  -Xswiftc \
  -emit-symbol-graph \
  -Xswiftc \
  -emit-symbol-graph-dir \
  -Xswiftc .build`;

const buildMsg = 'Building package'
core.startGroup(args ? `${buildMsg} with arguments \`${args}\`` : buildMsg);
execSync(command, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();
