# frozen_string_literal: true

module JMESPath
  module CLI
    USAGE = "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
            "(EXPRESSION | --query-file PATH)\n       " \
            "jmespath --validate (EXPRESSION | --query-file PATH)\n       jmespath --functions\n       " \
            "jmespath --interactive --file PATH"

    # @api private
    module Help
      GUIDE = "Reference: docs/guides/command-line.md (included in the gem).\n" \
              "https://github.com/svyatov/jmespath-ruby/blob/main/docs/guides/command-line.md\n"
      TOPICS = {
        "input" => <<~TEXT,
          Input: jmespath --file document.json 'user.name'
                 jmespath --query-file query.jmespath < document.json
          Read one UTF-8 JSON document from --file PATH, or stdin when omitted.
          Supply exactly one query: EXPRESSION or --query-file PATH, read as UTF-8 without trimming.
          Query text retains newlines and Unicode coordinates; an empty query file is a syntax failure.
          Query files close before document input; missing or unreadable queries leave documents untouched.
          In single-document mode, JSON is parsed before query compilation.
          Document files close after parsing, before evaluation. Caller-owned streams remain open.
          Options may precede or follow EXPRESSION; -- ends option parsing. Option names match exactly.
          Quote spaces: --file 'my document.json'. Use --file=--document.json or ./--document.json.
          Paths are literal: --file - and --query-file - read files named -.
          Repeated options, unknown options, missing values, and conflicting or absent queries fail before input.
          CLI.run document input needs read; line modes need gets; output needs puts.
          Query failures include source locations when available. Unknown functions suggest similar registered names.
          Malformed JSON reports Invalid JSON input without document fragments.
          Results use stdout; diagnostics use stderr. Success returns status 0, input/query/stream failures 1,
          and usage failures 2 with empty stdout. Information modes never access document or query input.
          Version and function listing flags must stand alone; help accepts only one optional topic.
        TEXT
        "output" => <<~TEXT,
          Output: jmespath --pretty 'items' < document.json
                  jmespath --raw-output 'user.name' < document.json
                  jmespath --json-lines --file events.jsonl --query-file query.jmespath
          Output is compact JSON by default; --pretty uses two-space indentation and a final newline.
          Both preserve Unicode and support objects, arrays, strings, numbers, booleans, and null.
          Pretty output supports either query and document source.
          --raw-output prints strings literally; other results remain compact JSON.
          Raw strings retain all embedded and trailing newlines and receive one additional output newline.
          An empty string prints one newline; a string ending in one newline prints two.
          Output flags cannot be repeated or combined with each other or --validate.
          JSON Lines compiles once before opening document input; valid empty input succeeds without output.
          Each physical line must contain one JSON value; blank and whitespace-only records are invalid.
          LF, CRLF, and a final record without a newline are accepted.
          Each result is compact JSON plus a newline, including null and false.
          Processing stops on failure; earlier stdout remains. Check status before treating output as complete.
          Record failures use Input line N: on stderr; compilation and file-open errors have no line prefix.
          Memory follows the current record, evaluation, and result plus the compiled query.
          Output uses normal buffering. Owned files close; caller-owned streams remain open.
          CLI.run line input needs gets and output needs puts.
          Formatting preserves diagnostics and source coordinates; failures before output leave stdout empty.
          Results use stdout; diagnostics use stderr. Success returns status 0, query/input/output failures 1,
          and usage failures 2. See jmespath --help input for query and path rules.
        TEXT
        "validate" => <<~TEXT,
          Validation: jmespath --validate EXPRESSION
                      jmespath --validate 'items[*].name'
                      jmespath --validate --query-file query.jmespath
                      jmespath --query-file query.jmespath --validate
          Check syntax only, without reading stdin. Unknown functions and invalid runtime types remain valid syntax.
          Query files follow input topic rules. --file, output flags, and interactive mode are unavailable.
          Invalid combinations fail before opening files or reading stdin.
          The exact two-argument form --validate EXPRESSION always treats EXPRESSION as query text.
          Thus --validate --help, --validate -h, --validate --pretty, and --validate --raw-output validate literals.
          Validation exits with status 0 for valid syntax, 1 for query failures, and 2 for usage failures.
          Valid syntax produces no stdout or stderr; failures leave stdout empty and print diagnostics to stderr.
          Query failures include source locations when available.
          Ruby callers can use JMESPath.validate(expression, max_depth: 128).
        TEXT
        "functions" => <<~TEXT + FunctionListing::LEGEND,
          Functions: jmespath --functions
          Use standalone --functions to list built-in signatures and descriptions without reading stdin.
          Names are alphabetical and use public function metadata; the listing ends with a notation legend.
          --functions cannot be repeated or combined with queries, paths, modes, information flags, or values.
          The two-argument form --validate --functions validates the literal query.
          Function arguments and expression-reference results are validated; failures exit with status 1.
          Unknown functions suggest similar registered names. Query failures include source locations when available.
          Listing writes to stdout with empty stderr and returns status 0; output failures return 1.
          Usage failures return 2, leave stdout empty, and print usage guidance to stderr before accessing input.
        TEXT
        "interactive" => <<~TEXT
          Interactive: jmespath --interactive --file PATH
                       jmespath --interactive --file document.json
          Enter one UTF-8 query per line; empty lines and lines containing only spaces or tabs are ignored.
          Queries accept LF, CRLF, and a final line without a newline.
          :help shows session help; :quit or EOF exits with status 0, even after query failures.
          Query errors, unknown commands, and invalid UTF-8 lines report diagnostics; the session continues.
          Failed queries print no result. Successful queries print compact JSON and a newline to stdout.
          Prompts, help, and diagnostics use stderr. Prompts appear only when stdin is a terminal.
          Results flush after each query when supported; piped query input produces no prompts.
          The document loads once and its file closes before the first prompt or query read.
          Interactive mode requires --file and rejects query sources, other modes, information flags, and repeats.
          Startup or stream failures exit with status 1; usage failures return 2 before reading input.
          CLI.run input needs gets; tty? is optional and absent detection means no prompts.
          Writers need puts; output flush is optional. Terminal prompts require stderr print and flush.
          Supported terminals provide editing and recall of the last 500 queries for this session only.
          Ctrl-C cancels the current edit. History includes failed queries, excludes commands, and creates no files.
          Editing requires terminal IO on stdin and stderr and a usable TERM; other streams use a plain reader.
          Caller-owned streams remain open; completion, multiline editing, and document reloads are unavailable.
        TEXT
      }.freeze

      def self.render(topic)
        return HELP unless topic

        TOPICS.fetch(topic) { raise OptionParser::InvalidArgument, "unknown help topic" } + GUIDE
      end
    end

    HELP = <<~TEXT.freeze
      #{USAGE}
             jmespath --help [TOPIC]
      Options:
        --file PATH         Read a JSON document (default: stdin)
        --query-file PATH   Read the UTF-8 query instead of EXPRESSION
        --pretty            Print indented JSON
        --raw-output        Print string results literally
        --json-lines        Search each JSON input line
        --validate          Check query syntax without a document
        --interactive       Run successive queries against --file PATH
        --functions         List built-in functions
        --version           Print the gem version
        -h, --help [TOPIC]   Show help
      Examples:
        jmespath --file document.json 'user.name'
        jmespath --pretty 'items' < document.json
        jmespath --validate 'items[*].name'
      Topic help (also accepts -h TOPIC):
        jmespath --help input
        jmespath --help output
        jmespath --help validate
        jmespath --help functions
        jmespath --help interactive
      Manual Bash and Zsh completion: docs/guides/completion.md.
      #{Help::GUIDE}
    TEXT
  end
end
