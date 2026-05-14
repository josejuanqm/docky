#!/usr/bin/env ruby
#
# add-zip-foundation.rb
#
# Adds the ZIPFoundation Swift package as a dependency for both the
# main `Docky` target and the `Docky (App Store)` target.
# ZIPFoundation is pure Swift, MIT-licensed, sandbox-safe — replaces
# the `/usr/bin/ditto` subprocess calls in ThemeManager + FeedbackBundle
# so theme import/export and feedback bundling work in MAS.
#
# Idempotent. Run with `ruby scripts/add-zip-foundation.rb`.
#

require 'xcodeproj'

PROJECT_PATH = 'Docky.xcodeproj'
PACKAGE_URL = 'https://github.com/weichsel/ZIPFoundation'
# Latest stable at time of writing; bump as needed.
PACKAGE_REQUIREMENT = { kind: 'upToNextMajorVersion', minimumVersion: '0.9.19' }
PRODUCT_NAME = 'ZIPFoundation'

project = Xcodeproj::Project.open(PROJECT_PATH)

# Find or create the remote package reference.
ref = project.root_object.package_references.find do |r|
  r.respond_to?(:repositoryURL) && r.repositoryURL == PACKAGE_URL
end

if ref.nil?
  puts "==> Adding remote package: #{PACKAGE_URL}"
  ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  ref.repositoryURL = PACKAGE_URL
  ref.requirement = PACKAGE_REQUIREMENT
  project.root_object.package_references << ref
else
  puts "==> Package already present: #{PACKAGE_URL}"
end

# Attach the package product to each target that needs it.
['Docky', 'Docky (App Store)'].each do |target_name|
  target = project.targets.find { |t| t.name == target_name }
  next unless target

  already = target.package_product_dependencies.find { |dep| dep.product_name == PRODUCT_NAME }
  if already
    puts "    [skip] #{target_name} already depends on #{PRODUCT_NAME}"
    next
  end

  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = ref
  dep.product_name = PRODUCT_NAME
  target.package_product_dependencies << dep

  # Add to the target's frameworks build phase so the linker sees it.
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file

  puts "    [added] #{target_name} now depends on #{PRODUCT_NAME}"
end

project.save
puts "==> Saved #{PROJECT_PATH}"
