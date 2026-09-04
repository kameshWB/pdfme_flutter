#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'pdfme_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Local offline PDF generation for Flutter using pdfme.'
  s.description      = <<-DESC
Generates PDFs entirely on-device using a bundled @pdfme/generator engine
running inside an offscreen WebView on Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/pdfme/pdfme'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'pdfme_flutter' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pdfme_flutter/Sources/pdfme_flutter/**/*.swift'
  s.resource_bundles = {
    'pdfme_flutter_resources' => [
      'pdfme_flutter/Sources/pdfme_flutter/Resources/**',
      'pdfme_flutter/Sources/pdfme_flutter/PrivacyInfo.xcprivacy'
    ]
  }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
