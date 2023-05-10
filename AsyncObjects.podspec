require 'json'

Pod::Spec.new do |s|
  package = JSON.parse(File.read('package.json'), {object_class: OpenStruct})

  s.name              = 'AsyncObjects'
  s.version           = package.version.to_s
  s.homepage          = package.homepage
  s.summary           = package.summary
  s.description       = package.description
  s.license           = { :type => package.license, :file => 'LICENSE' }
  s.social_media_url  = package.author.url
  s.readme            = "#{s.homepage}/blob/main/README.md"
  s.changelog         = "#{s.homepage}/blob/main/CHANGELOG.md"
  s.documentation_url = "https://swiftylab.github.io/AsyncObjects/#{s.version}/documentation/#{s.name.downcase}/"

  s.source            = {
    package.repository.type.to_sym => package.repository.url,
    :tag => "v#{s.version}"
  }

  s.authors           = {
    package.author.name => package.author.email
  }

  s.swift_version             = '5.6'
  s.ios.deployment_target     = '13.0'
  s.macos.deployment_target   = '10.15'
  s.tvos.deployment_target    = '13.0'
  s.watchos.deployment_target = '6.0'
  s.osx.deployment_target     = '10.15'

  s.source_files = "Sources/#{s.name}/**/*.*"
  s.preserve_paths = "{Sources,Tests}/#{s.name}*/**/*", "*.md"
  s.pod_target_xcconfig = {
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'YES',
    'RUN_DOCUMENTATION_COMPILER' => 'YES'
  }

  s.dependency 'OrderedCollections', '~> 1.0.0'
  s.dependency 'AsyncAlgorithms', '~> 0.1.0'
  s.default_subspecs = :none

  s.subspec 'Checked' do |ss|
    ss.pod_target_xcconfig = {
      'OTHER_SWIFT_FLAGS' => '-D ASYNCOBJECTS_USE_CHECKEDCONTINUATION'
    }
  end

  s.subspec 'Logging' do |ss|
    ss.dependency 'Logging', '~> 1.0.0'
    # ss.default_subspec = 'Info'

    for level in ['Debug', 'Info', 'Trace'] do
      ss.subspec level do |sss|
        sss.pod_target_xcconfig = {
          'OTHER_SWIFT_FLAGS' => "-D ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_#{level.upcase}"
        }
      end
    end
  end

  s.test_spec do |ts|
    ts.source_files = "Tests/#{s.name}Tests/**/*.swift"
    ts.dependency "#{s.name}/Checked"
    ts.dependency "#{s.name}/Logging"
    ts.scheme = { :parallelizable => true, :code_coverage => true }
  end
end
