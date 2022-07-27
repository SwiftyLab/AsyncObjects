#!/usr/bin/env node
const fs = require('fs');
const { execSync } = require('child_process');
const readdirGlob = require('readdir-glob');
const core = require('@actions/core');
const plist = require('plist');

core.startGroup(`Generating Xcode project for swift package`);
execSync(
  `swift package --verbose generate-xcodeproj \
    --xcconfig-overrides Helpers/AsyncObjects.xcconfig \
    --skip-extra-files`, {
    stdio: ['inherit', 'inherit', 'inherit'],
    encoding: 'utf-8'
  }
);
core.endGroup();

core.startGroup(`Adding documentation catalogue to Xcode project`);
const rubyCommand = `"require 'xcodeproj'
project = Xcodeproj::Project.open('AsyncObjects.xcodeproj')
project_changed = false
['AsyncObjects'].each do |p_target|
  target = project.native_targets.find { |target| target.display_name == p_target }
  group = project[\\"Sources/#{p_target}\\"]

  docc_file = \\"#{p_target}.docc\\"
  file_create = lambda { project_changed = true; group.new_reference(\\"#{p_target}.docc\\") }
  file = group.files.find { |file| File.basename(file.path) == docc_file } || file_create.call
  build_file_create = lambda { project_changed = true; target.add_file_references([file]) }
  build_file = target.source_build_phase.files.find { |build_file| build_file.file_ref == file } || build_file_create.call
end
project.save() if project_changed"`;
execSync(`ruby -e ${rubyCommand}`, {
  stdio: ['inherit', 'inherit', 'inherit'],
  encoding: 'utf-8'
}
);
core.endGroup();

const package = JSON.parse(fs.readFileSync('package.json', 'utf8'));
core.startGroup(`Updating version to ${package.version} in plist`);
const plistGlobberer = readdirGlob('.', { pattern: 'AsyncObjects.xcodeproj/*.plist' });
plistGlobberer.on(
  'match',
  m => {
    const buffer = plist.parse(fs.readFileSync(m.absolute, 'utf8'));
    const props = JSON.parse(JSON.stringify(buffer));
    // props.CFBundleVersion = package.version;
    props.CFBundleShortVersionString = package.version;
    fs.writeFileSync(m.absolute, plist.build(props));
    core.endGroup();
  }
);

plistGlobberer.on('error', err => { core.error(err); });
