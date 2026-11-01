# frozen_string_literal: true

require "digest"
require "json"
require "rubygems/package"

artifact = File.expand_path(ARGV.fetch(0))
package = Gem::Package.new(artifact)
package.verify
specification = package.spec
version = specification.version.to_s
tag = ENV.fetch("RELEASE_TAG", "")
abort "Tag does not match gem version" unless tag.empty? || tag == "v#{version}"

section = File.read("CHANGELOG.md").split(/^## /).find { |entry| entry.start_with?("[#{version}] ") }
abort "Missing release notes for #{version}" unless section

notes = section.lines.drop(1).take_while { |line| !line.match?(/^\[[^\]]+\]:/) }.join.strip
abort "Missing release notes for #{version}" if notes.empty?

components = specification.runtime_dependencies.map do |dependency|
  { type: "library", name: dependency.name, "bom-ref": "pkg:gem/#{dependency.name}",
    purl: "pkg:gem/#{dependency.name}",
    properties: [{ name: "gem:version-requirement", value: dependency.requirement.to_s }] }
end
components << { type: "platform", name: "Ruby", "bom-ref": "runtime:ruby",
                properties: [{ name: "gem:version-requirement", value: specification.required_ruby_version.to_s }] }
reference = "pkg:gem/#{specification.name}@#{version}"
sbom = {
  bomFormat: "CycloneDX", specVersion: "1.6", version: 1,
  metadata: {
    component: { type: "library", name: specification.name, version: version, "bom-ref": reference, purl: reference,
                 hashes: [{ alg: "SHA-256", content: Digest::SHA256.file(artifact).hexdigest }] },
    tools: { components: [{ type: "application", name: "Ruby", version: RUBY_VERSION },
                          { type: "application", name: "RubyGems", version: Gem::VERSION }] }
  },
  components: components,
  dependencies: [{ ref: reference, dependsOn: components.map { |component| component.fetch(:"bom-ref") } }]
}

directory = File.dirname(artifact)
inventory = File.join(directory, "sbom.cdx.json")
File.write(inventory, "#{JSON.pretty_generate(sbom)}\n")
File.write(File.join(directory, "release-notes.md"), "#{notes}\n")
checksums = [artifact, inventory].map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}\n" }
File.write(File.join(directory, "SHA256SUMS"), checksums.join)
