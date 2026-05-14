#!/usr/bin/env ruby
#
# add-helper-target.rb
#
# Adds the "Docky Helper" application target to Docky.xcodeproj.
# Helper is Developer ID-signed (NOT App Store), un-sandboxed, and
# pulls its sources from DockyHelper/Sources/.
#
# Idempotent. Run with `ruby scripts/add-helper-target.rb` from
# the repo root.
#

require 'xcodeproj'

PROJECT_PATH = 'Docky.xcodeproj'
TARGET_NAME = 'Docky Helper'
BUNDLE_ID = 'gt.quintero.Docky.Helper'
SOURCES_DIR = 'DockyHelper/Sources'
RESOURCES_DIR = 'DockyHelper/Sources/Resources'

project = Xcodeproj::Project.open(PROJECT_PATH)

helper_target = project.targets.find { |t| t.name == TARGET_NAME }

if helper_target.nil?
  puts "==> Creating target '#{TARGET_NAME}'"
  helper_target = project.new_target(
    :application,
    TARGET_NAME,
    :osx,
    '13.0',
    nil,
    :swift
  )

  # Add the Swift sources at DockyHelper/Sources/*.swift
  dockyhelper_group = project.main_group['DockyHelper'] ||
                      project.main_group.new_group('DockyHelper', 'DockyHelper')
  sources_group = dockyhelper_group['Sources'] ||
                  dockyhelper_group.new_group('Sources', 'Sources')

  Dir.glob("#{SOURCES_DIR}/*.swift").sort.each do |path|
    relative = File.basename(path)
    file_ref = sources_group.files.find { |f| f.path == relative } ||
               sources_group.new_file(relative)
    helper_target.add_file_references([file_ref])
  end

  # Bundle the LaunchAgent plist as a resource.
  resources_group = sources_group['Resources'] ||
                    sources_group.new_group('Resources', 'Resources')
  Dir.glob("#{RESOURCES_DIR}/*.plist").sort.each do |path|
    relative = File.basename(path)
    file_ref = resources_group.files.find { |f| f.path == relative } ||
               resources_group.new_file(relative)
    helper_target.resources_build_phase.add_file_reference(file_ref, true)
  end
else
  puts "==> Target '#{TARGET_NAME}' already exists, updating settings"
end

helper_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['PRODUCT_NAME'] = 'Docky Helper'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Docky Helper'

  # Developer ID signing, NOT App Store. The helper is distributed
  # via getdocky.com, never through Apple's store.
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = '2KC3797KP9'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Developer ID Application'

  # Un-sandboxed: the whole point is to do the things the MAS app
  # can't. Hardened runtime is still required for notarization.
  config.build_settings['ENABLE_APP_SANDBOX'] = 'NO'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'

  # Faceless agent. The Info.plist gets LSUIElement = true so the
  # helper doesn't show a dock tile or menu bar.
  config.build_settings['INFOPLIST_KEY_LSUIElement'] = 'YES'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'

  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'

  # User-script sandboxing is irrelevant since the helper has no
  # script phases, but explicit OFF mirrors the main target.
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
end

project.save
puts "==> Saved #{PROJECT_PATH}"
puts
puts "Next: open Docky.xcodeproj, optionally add Code Signing"
puts "entitlements (App Group: \$(TeamIdentifierPrefix)gt.quintero.Docky.shared)."
puts "Then build with: xcodebuild -scheme 'Docky Helper' build"
