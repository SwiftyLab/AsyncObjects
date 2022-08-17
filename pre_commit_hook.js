const { execSync } = require('child_process');
const core = require('@actions/core');

exports.preCommit = (props) => {
  core.startGroup(`Running \`npm install\``);
  execSync(
    'npm install', {
      stdio: ['inherit', 'inherit', 'inherit'],
      encoding: 'utf-8'
    }
  );
  core.endGroup();

  execSync(
    'npm run generate', {
      stdio: ['inherit', 'inherit', 'inherit'],
      encoding: 'utf-8'
    }
  );
};
