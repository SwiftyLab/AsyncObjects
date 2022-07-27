#!/usr/bin/env node
const { execSync } = require('child_process');
const core = require('@actions/core');

const command = 'pod lib lint --no-clean --allow-warnings --verbose';
core.startGroup(`Linting podspec`);
execSync(command, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();
