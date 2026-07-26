platform :ios, '15.0'

target 'OpenDocumentReader' do
  use_frameworks!

  # Pods for OpenDocumentReader
  pod 'ScrollableSegmentedControl'
  pod 'Google-Mobile-Ads-SDK'

  target 'OpenDocumentReaderTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
