# frozen_string_literal: true

require "yard"
require "stringio"
require "optparse"
require_relative "support/doc_examples"

# Checks public YARD contracts, local links, and executable examples.
class DocumentationCheck
  BUILTINS = %w[Array Boolean Class Exception FalseClass Float Hash Integer IO Method Module NilClass
                Numeric Object Proc Regexp StandardError String StringIO Struct Symbol TrueClass TypeError
                ArgumentError Pathname Range].freeze

  def initialize(root)
    @root = File.expand_path(root)
    @messages = []
  end

  def run
    load_registry
    YARD::Registry.all(:class, :module, :method).select { |object| public?(object) }.each { |object| check(object) }
    check_links
    check_examples
    @messages
  ensure
    YARD::Logger.instance.io = $stderr
  end

  private

  def load_registry
    log = StringIO.new
    YARD::Logger.instance.io = log
    YARD::Registry.clear
    YARD.parse(Dir[File.join(@root, "lib/**/*.rb")])
    @messages.concat(log.string.lines.grep(/warn|error/i))
  end

  def public?(object)
    return false if object.respond_to?(:visibility) && object.visibility == :private

    cursor = object
    until cursor.root?
      return false if cursor.tag(:api)&.text == "private" || cursor.has_tag?(:private)

      cursor = cursor.namespace
    end
    true
  end

  def check(object)
    @messages << "Undocumented #{object.path}" if object.docstring.empty? && object.tags.empty?
    check_types(object)
    check_method(object) if object.is_a?(YARD::CodeObjects::MethodObject)
  end

  def check_method(object)
    if object.name != :initialize && !object.has_tag?(:return)
      @messages << "Missing return documentation: #{object.path}"
    end
    object.parameters.each { |parameter| check_parameter(object, parameter.first) }
  end

  def check_parameter(object, name)
    return if name.start_with?("&")

    parameter = name.delete_prefix("**").delete_prefix("*").delete_suffix(":")
    return if object.tags(:param).any? { |tag| tag.name == parameter }

    @messages << "Missing parameter #{parameter}: #{object.path}"
  end

  def check_types(object)
    object.tags.each do |tag|
      Array(tag.types).each do |type|
        type.scan(/[A-Z]\w*(?:::\w+)*/).each do |name|
          next if BUILTINS.include?(name) || YARD::Registry.resolve(object, name, true, false)

          @messages << "Unresolved type #{name}: #{object.path}"
        end
      end
    end
  end

  def check_links
    files = Dir[File.join(@root, "{README.md,CONTRIBUTING.md,docs/guides/**/*.md}")]
    files.each do |path|
      File.read(path).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
        next if target.start_with?("https:", "http:", "mailto:", "#")

        file = target.split("#", 2).first
        @messages << "Missing local link #{target}: #{path}" unless File.exist?(File.expand_path(file,
                                                                                                 File.dirname(path)))
      end
    end
  end

  def check_examples
    $LOAD_PATH.unshift(File.join(@root, "lib"))
    Dir[File.join(@root, "lib/*.rb")].each { |path| require path }
    (DocExamples.markdown(@root) + DocExamples.yard).each do |example|
      DocExamples.verify(example)
    rescue StandardError => e
      @messages << e.message
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  OptionParser.new { |parser| parser.on("--root PATH") { |value| root = value } }.parse!
  messages = DocumentationCheck.new(root).run
  puts(messages.empty? ? "Documentation checks passed" : messages)
  exit(messages.empty? ? 0 : 1)
end
