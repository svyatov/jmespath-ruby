# frozen_string_literal: true

require "bundler"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"

# Verifies production use from an installed artifact outside the source tree.
class PackageCheck
  SMOKE = <<~'RUBY'
    require "json"
    require "jmespath"
    source = $LOADED_FEATURES.find { |path| path.end_with?("/jmespath.rb") }
    installed = Gem.loaded_specs.fetch("jmespath-ruby").full_gem_path
    raise "Wrong provider: #{source}" unless source == File.join(installed, "lib/jmespath.rb")
    raise "Missing public signatures" unless File.file?(File.join(installed, "sig/jmespath.rbs"))
    puts JSON.generate(version: JMESPath::VERSION,
                       search: JMESPath.search("people[*].name", {"people" => [{"name" => "Ada"}]}),
                       validation: JMESPath.validate("people[*].name"),
                       syntax_failure: JMESPath.validate("items[?active").fetch(0).reason,
                       source: source, dependencies: Bundler.load.specs.map(&:name))
  RUBY

  def initialize(root)
    @root = File.expand_path(root)
  end

  def build(destination)
    FileUtils.mkdir_p(destination)
    specification = Gem::Specification.load(File.join(@root, "jmespath-ruby.gemspec"))
    artifact = File.join(File.expand_path(destination), "#{specification.full_name}.gem")
    Dir.chdir(@root) { Gem::Package.build(specification, false, false, artifact) }
    artifact
  end

  def verify(artifact)
    Dir.mktmpdir("jmespath-installed") do |directory|
      prepare(directory, artifact)
      environment = environment_for(directory)
      command(environment, directory, "install", "--local", "--quiet")
      result = JSON.parse(command(environment, directory, "exec", RbConfig.ruby, "-e", SMOKE))
      verify_executables(environment, directory)
      result
    end
  end

  private

  def prepare(directory, artifact)
    cache = File.join(directory, "vendor/cache")
    FileUtils.mkdir_p(cache)
    FileUtils.cp(artifact, cache)
    %w[json stringio].each do |name|
      archive = Gem.loaded_specs.fetch(name).cache_file
      raise "Missing cached runtime gem: #{archive}" unless File.file?(archive)

      FileUtils.cp(archive, cache)
    end
    specification = Gem::Package.new(artifact).spec
    File.write(File.join(directory, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "jmespath-ruby", "= #{specification.version}"
    GEMFILE
    prepare_lock(directory, artifact, specification)
  end

  def prepare_lock(directory, artifact, specification)
    environment = environment_for(directory).merge("BUNDLE_FROZEN" => "false")
    command(environment, directory, "lock", "--local", "--add-checksums")
    path = File.join(directory, "Gemfile.lock")
    checksum = "  #{specification.name} (#{specification.version}) sha256=#{Digest::SHA256.file(artifact).hexdigest}"
    identity = Regexp.escape("#{specification.name} (#{specification.version})")
    File.write(path, File.read(path).sub(/^  #{identity}(?: sha256=.+)?$/, checksum))
  end

  def environment_for(directory)
    Bundler.original_env.merge(
      "BUNDLE_GEMFILE" => File.join(directory, "Gemfile"),
      "BUNDLE_PATH" => File.join(directory, "installed"),
      "BUNDLE_APP_CONFIG" => File.join(directory, ".bundle"),
      "BUNDLE_FROZEN" => "true", "BUNDLE_DEPLOYMENT" => "false",
      "BUNDLE_WITHOUT" => "", "RUBYOPT" => nil, "RUBYLIB" => nil
    )
  end

  def command(environment, directory, *arguments, input: "")
    output, error, status = Open3.capture3(
      environment, RbConfig.ruby, Gem.bin_path("bundler", "bundle"), *arguments,
      chdir: directory, stdin_data: input, unsetenv_others: true
    )
    raise "Package command failed: #{arguments.join(' ')}\n#{output}\n#{error}" unless status.success?

    output
  end

  def verify_executables(environment, directory)
    %w[jmespath jmespath.rb].each do |executable|
      result = command(environment, directory, "exec", executable, "foo.bar",
                       input: '{"foo":{"bar":2}}')
      raise "Incorrect installed executable: #{executable}" unless result == "2\n"
    end
  end
end
