#!/usr/bin/env ruby
# Adds the PacketTunnel (Network Extension) target to ios/Runner.xcodeproj,
# links Libbox.xcframework, embeds the extension into Runner and sets the
# Network Extension entitlement. Idempotent. Run on macOS (CI does it).
#
#   ruby tools/ios/add_tunnel.rb
require 'xcodeproj'

root = File.expand_path('../..', __dir__)
project_path = File.join(root, 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

EXT = 'PacketTunnel'.freeze
if project.targets.any? { |t| t.name == EXT }
  puts "#{EXT} target already present, nothing to do"
  exit 0
end

runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
base_id = runner.build_configurations.first.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] || 'com.wokok.wokokVpn'

pubspec = File.read(File.join(root, 'pubspec.yaml'))
version = pubspec[/^version:\s*([\d.]+)/, 1] || '1.0.0'
build = pubspec[/^version:\s*[\d.]+\+(\d+)/, 1] || '1'

xcfw_path = File.join(root, 'ios', 'Frameworks', 'Libbox.xcframework')
abort("Libbox.xcframework is missing: run tools/build_libbox_apple.sh first") unless Dir.exist?(xcfw_path)

# --- the extension target ----------------------------------------------------
ext = project.new_target(:app_extension, EXT, :ios, '15.6')

group = project.main_group.new_group(EXT, EXT)
sources = %w[PacketTunnelProvider.swift WokokPlatform.swift].map { |f| group.new_file(f) }
group.new_file('Info.plist')
group.new_file('PacketTunnel.entitlements')
ext.add_file_references(sources)

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{base_id}.#{EXT}"
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{EXT}/Info.plist"
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT}/#{EXT}.entitlements"
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.6'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = build
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '$(PROJECT_DIR)/Frameworks']
  s['ENABLE_BITCODE'] = 'NO'
  s['CLANG_ENABLE_MODULES'] = 'YES'
  s['SWIFT_OPTIMIZATION_LEVEL'] = c.name == 'Debug' ? '-Onone' : '-O'
end

# Libbox (static xcframework from gomobile) + system libs
xcfw = project.main_group.new_reference('Frameworks/Libbox.xcframework')
xcfw.last_known_file_type = 'wrapper.xcframework'
ext.frameworks_build_phase.add_file_reference(xcfw)
ext.add_system_framework('NetworkExtension')
ext.add_system_library('resolv')

# --- Runner: dependency, embed phase, entitlements ----------------------------
runner.add_dependency(ext)

embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Flutter's "Thin Binary" script creates a build cycle if the embed phase comes after it.
first_script = runner.build_phases.index { |p| p.isa == 'PBXShellScriptBuildPhase' }
if first_script
  runner.build_phases.delete(embed)
  runner.build_phases.insert(first_script, embed)
end

runner_group = project.main_group.find_subpath('Runner', false)
runner_group&.new_file('Runner.entitlements')
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

project.save
puts "Added #{EXT} (#{base_id}.#{EXT}), version #{version}+#{build}"
