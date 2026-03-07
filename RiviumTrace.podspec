Pod::Spec.new do |s|
  s.name             = 'RiviumTrace'
  s.version          = '0.1.0'
  s.summary          = 'Error tracking, logging, and performance monitoring SDK for iOS'
  s.description      = <<-DESC
    RiviumTrace is a comprehensive error tracking, logging, and performance monitoring SDK for iOS applications.
    Features include automatic crash detection, breadcrumb tracking, logging, and APM support.
  DESC

  s.homepage         = 'https://github.com/rivium-trace/rivium-trace-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'RiviumTrace' => 'support@rivium.co' }
  s.source           = { :git => 'https://github.com/Rivium-co/rivium-trace-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.tvos.deployment_target = '12.0'
  s.watchos.deployment_target = '5.0'

  s.swift_versions = ['5.0', '5.5', '5.7', '5.9']

  s.source_files = 'Sources/RiviumTrace/**/*'

  s.frameworks = 'Foundation'
  s.ios.frameworks = 'UIKit'
  s.osx.frameworks = 'AppKit'
end
