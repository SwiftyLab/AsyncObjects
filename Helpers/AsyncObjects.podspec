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
  s.documentation_url = "https://swiftylab.github.io/AsyncObject/#{s.version}/documentation/#{s.name.downcase}/"

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

  s.vendored_frameworks = "#{s.name}.xcframework"
  s.dependency 'OrderedCollections', '~> 1.0.0'
  # @todo: Enable when CocoaPods starts supporting docc
  # s.source_files = "#{s.name}.docc"
  # s.pod_target_xcconfig = {
  #   'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'YES',
  #   'RUN_DOCUMENTATION_COMPILER' => 'YES'
  # }
end
