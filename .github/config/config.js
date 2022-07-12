'use strict'
const config = require('conventional-changelog-conventionalcommits');

module.exports = config({
    "types": [
        { type: 'feat', section: '🚀 Features' },
        { type: 'fix', section: '🐛 Fixes' },
        { type: 'perf', section: '🐎 Performance Improvements' },
        { type: 'revert', section: '⏪ Reverts' },
        { type: 'build', section: '🛠 Build System' },
        { type: 'deps', section: '🛠 Dependency' },
        { type: 'refactor', section: '🔥 Refactorings' },
        { type: 'doc', section: '📚 Documentation' },
        { type: 'docs', section: '📚 Documentation' },
        { type: 'style', section: '💄 Styles' },
        { type: 'test', section: '✅ Tests' },
        { type: 'ci', section: '💡 Continuous Integration', hidden: true },
        { type: 'wip', hidden: true },
        { type: 'chore', hidden: true },
    ]
});
