# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rubygems/package"
require "tmpdir"

RSpec.describe "Release artifacts" do
  around do |example|
    Dir.mktmpdir("release-artifacts") do |directory|
      @directory = directory
      File.write(File.join(directory, "fixture.rb"), "# fixture\n")
      File.write(File.join(directory, "CHANGELOG.md"), "# Changelog\n\n## [1.2.3] - 2026-11-01\n\nRelease evidence.\n")
      specification = Gem::Specification.new do |spec|
        spec.name = "fixture"
        spec.version = "1.2.3"
        spec.summary = "Release fixture"
        spec.authors = ["Test"]
        spec.files = ["fixture.rb"]
        spec.required_ruby_version = ">= 3.3"
        spec.add_dependency "json", ">= 2.7", "< 4"
      end
      Dir.chdir(directory) { Gem::Package.build(specification, true) }
      example.run
    end
  end

  def generate(tag)
    script = File.expand_path("../../script/release_artifacts.rb", __dir__)
    Open3.capture3({ "RELEASE_TAG" => tag }, RbConfig.ruby, script, "fixture-1.2.3.gem", chdir: @directory)
  end

  it "describes the exact gem and its runtime requirements" do
    _output, error, status = generate("v1.2.3")
    expect(status.success?).to be(true), error
    sbom = JSON.parse(File.read(File.join(@directory, "sbom.cdx.json")))
    expect(sbom.fetch("metadata").fetch("component").fetch("hashes")).to eq(
      [{ "alg" => "SHA-256", "content" => Digest::SHA256.file(File.join(@directory, "fixture-1.2.3.gem")).hexdigest }]
    )
    expect(sbom.fetch("components").map { |component| component.fetch("name") }).to eq(%w[json Ruby])
    expect(sbom.fetch("components").first.fetch("properties")).to include(
      { "name" => "gem:version-requirement", "value" => ">= 2.7, < 4" }
    )
    expect(File.read(File.join(@directory, "release-notes.md"))).to eq("Release evidence.\n")
    expect(File.read(File.join(@directory, "SHA256SUMS"))).to include("  fixture-1.2.3.gem\n", "  sbom.cdx.json\n")
  end

  it "rejects a tag that differs from the packaged version" do
    _output, error, status = generate("v9.9.9")
    expect(status.success?).to be(false)
    expect(error).to include("Tag does not match gem version")
    expect(File.exist?(File.join(@directory, "sbom.cdx.json"))).to be(false)
  end

  it "rejects missing release notes" do
    File.write(File.join(@directory, "CHANGELOG.md"), "# Changelog\n")
    _output, error, status = generate("")
    expect(status.success?).to be(false)
    expect(error).to include("Missing release notes")
  end
end
