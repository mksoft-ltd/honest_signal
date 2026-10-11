# Add the HonestSignalWidget WidgetKit extension target to ios/Runner.xcodeproj
# and embed it in Runner. Idempotent: exits without changes if the target exists.
#
# Uses the xcodeproj gem bundled with Homebrew fastlane:
#   GEM_HOME=/opt/homebrew/opt/fastlane/libexec GEM_PATH=/opt/homebrew/opt/fastlane/libexec \
#     ruby scripts/add_ios_widget_target.rb
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../ios/Runner.xcodeproj', __dir__)
TARGET_NAME = 'HonestSignalWidget'
BUNDLE_ID = 'com.froggyeye.honestsignal.widget'
TEAM_ID = '696939LPWV'
# WidgetKit lock-screen (accessory) families need iOS 16; Runner is on 15, so
# iOS 15 users keep the app and simply do not get the widget.
DEPLOYMENT_TARGET = '16.0'

project = Xcodeproj::Project.open(PROJECT_PATH)
if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "#{TARGET_NAME} already exists; nothing to do"
  exit
end
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

widget = project.new_target(:app_extension, TARGET_NAME, :ios, DEPLOYMENT_TARGET, nil, :swift)

# new_target links Foundation by a hard-coded SDK path (iPhoneOS18.0.sdk) that
# breaks on other Xcodes. Swift links system frameworks automatically.
widget.frameworks_build_phase.files.dup.each do |build_file|
  ref = build_file.file_ref
  build_file.remove_from_project
  if ref
    parent = ref.parent
    ref.remove_from_project
    parent.remove_from_project if parent.is_a?(Xcodeproj::Project::Object::PBXGroup) && parent.children.empty? && parent.name == 'iOS'
  end
end

group = project.main_group.new_group(TARGET_NAME, TARGET_NAME)
sources = %w[HonestSignalWidget.swift WidgetProbe.swift WidgetScoring.swift].map { |f| group.new_reference(f) }
privacy = group.new_reference('PrivacyInfo.xcprivacy')
group.new_reference('Info.plist')
xcconfig = group.new_reference('HonestSignalWidget.xcconfig')
widget.add_file_references(sources)
widget.resources_build_phase.add_file_reference(privacy)

widget.build_configurations.each do |config|
  config.base_configuration_reference = xcconfig
  s = config.build_settings
  s.delete('MARKETING_VERSION')
  s.merge!(
    'INFOPLIST_FILE' => "#{TARGET_NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'VERSIONING_SYSTEM' => 'apple-generic',
    'DEVELOPMENT_TEAM' => TEAM_ID,
    'CODE_SIGN_STYLE' => 'Automatic',
    'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'TARGETED_DEVICE_FAMILY' => '1',
    'SWIFT_VERSION' => '5.0',
    'SKIP_INSTALL' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks',
                                  '@executable_path/../../Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS' => 'YES'
  )
  if config.name == 'Debug'
    s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
  else
    s['SWIFT_COMPILATION_MODE'] = 'wholemodule'
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
  end
end

runner.add_dependency(widget)

# Embed the .appex in Runner.app/PlugIns. The phase must run before Flutter's
# "Thin Binary" script, otherwise Xcode reports a build-phase dependency cycle.
embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed.name = 'Embed Foundation Extensions'
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
thin = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' } or abort('Thin Binary phase not found')
runner.build_phases.insert(thin, embed)

project.root_object.attributes['TargetAttributes'][widget.uuid] = {'CreatedOnToolsVersion' => '16.0'}

project.save
puts "Added #{TARGET_NAME} (#{widget.uuid}) and embedded it in Runner"
puts 'Runner build phases: ' + runner.build_phases.map(&:display_name).join(' -> ')
