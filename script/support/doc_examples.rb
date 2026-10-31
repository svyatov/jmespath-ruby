# frozen_string_literal: true

# Executes examples from trusted repository documentation.
module DocExamples
  def self.markdown(root)
    files = Dir[File.join(root, "docs/guides/**/*.md")]
    readme = File.join(root, "README.md")
    files.unshift(readme) if File.file?(readme)
    files.flat_map { |path| markdown_file(path) }
  end

  def self.markdown_file(path)
    fence = Regexp.escape(96.chr * 3)
    File.read(path).scan(/#{fence}ruby[^\n]*\n(.*?)^#{fence}/m).filter_map.with_index do |(code), index|
      { label: "#{path}:#{index}", code: code } if code.include?("#=>") || code.include?("# raises ")
    end
  end

  def self.yard
    YARD::Registry.all(:method).flat_map do |object|
      object.tags(:example).map { |tag| { label: object.path, code: tag.text } }
    end
  end

  def self.verify(example)
    Runner.new(example.fetch(:label)).verify(example.fetch(:code))
  end

  # Keeps setup statements and assertions in one example-local binding.
  class Runner
    def initialize(label)
      @label = label
      @context = Object.new.instance_eval { binding }
      @pending = +""
    end

    def verify(code)
      code.each_line(chomp: true) { |line| process(line) }
      @context.eval(@pending, @label) unless @pending.strip.empty?
    end

    private

    def process(line)
      if (match = line.match(/\A(.*?)#=>\s*(.+)\z/))
        verify_result(@pending + match[1], match[2])
      elsif (match = line.match(/\A(.*?)# raises\s+(\S+)/))
        verify_error(@pending + match[1], match[2])
      else
        @pending << line << "\n"
        return
      end
      @pending.clear
    end

    def verify_result(code, expectation)
      actual = @context.eval(code, @label)
      expected = @context.eval(expectation, @label)
      return if actual == expected

      raise "Example mismatch: #{@label}: #{actual.inspect} != #{expected.inspect}"
    end

    def verify_error(code, name)
      expected = Object.const_get(name)
      begin
        @context.eval(code, @label)
      rescue expected
        return
      end
      raise "Example mismatch: #{@label}: expected #{name}"
    end
  end
end
