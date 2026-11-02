# frozen_string_literal: true

require "tmpdir"
require "rubygems/package"
require_relative "../../script/support/package_check"

RSpec.describe "Installed gem artifact" do
  before(:context) do
    @directory = Dir.mktmpdir("jmespath-package-spec")
    @checker = PackageCheck.new(File.expand_path("../..", __dir__))
    @artifact = @checker.build(@directory)
  end

  after(:context) { FileUtils.remove_entry(@directory) }

  it "ships the documented public surface without development files" do
    specification = Gem::Package.new(@artifact).spec
    expect(specification.version.to_s).to eq(JMESPath::VERSION)
    expect(specification.required_ruby_version).to eq(Gem::Requirement.new(">= 3.3"))
    expect(specification.executables.sort).to eq(%w[jmespath jmespath.rb])
    expect(specification.files).to include(
      "lib/jmespath.rb", "lib/jmespath/syntax_diagnostic.rb", "sig/jmespath.rbs", "README.md", "CONTRIBUTING.md",
      "CHANGELOG.md",
      "VERSIONING.md", "SECURITY.md",
      "LICENSE", "LICENSES/python-MIT.txt", "LICENSES/ruby-Apache-2.0.txt", "docs/guides/compatibility.md"
    )
    expect(specification.files.grep(%r{\A(?:spec/|coverage/|doc/|sig/internal/|\.git|\.superpowers/)})).to be_empty
    expect(specification.files).not_to include("Gemfile", "Gemfile.lock")
    expect(specification.dependencies.map(&:name).sort).to eq(%w[json stringio])
  end

  it "installs offline and resolves API and both executables from the artifact" do
    result = @checker.verify(@artifact)
    expect(result.fetch("version")).to eq(JMESPath::VERSION)
    expect(result.fetch("search")).to eq(["Ada"])
    expect(result.fetch("validation")).to eq([])
    expect(result.fetch("syntax_failure")).to eq("Expected rbracket, received eof")
    expect(result.fetch("source")).to include("/jmespath-ruby-#{JMESPath::VERSION}/lib/jmespath.rb")
    expect(result.fetch("dependencies").sort).to eq(%w[bundler jmespath-ruby json stringio])
  end

  it "rejects dependency changes after preparing the installation lock" do
    allow(@checker).to receive(:prepare).and_wrap_original do |prepare, directory, artifact|
      prepare.call(directory, artifact)
      File.open(File.join(directory, "Gemfile"), "a") { |file| file.puts('gem "rake"') }
    end

    expect { @checker.verify(@artifact) }.to raise_error(RuntimeError, /frozen/)
  end

  it "fills an empty build checksum before the frozen installation" do
    allow(@checker).to receive(:command).and_wrap_original do |command, environment, directory, *arguments, **options|
      output = command.call(environment, directory, *arguments, **options)
      if arguments.first == "lock"
        path = File.join(directory, "Gemfile.lock")
        File.write(path, File.read(path).sub(/(  jmespath-ruby \([^\n]+\)) sha256=.+$/, '\1'))
      end
      output
    end

    expect(@checker.verify(@artifact).fetch("version")).to eq(JMESPath::VERSION)
  end
end
