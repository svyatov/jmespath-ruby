# frozen_string_literal: true

module JMESPath
  module CLI
    USAGE = "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
            "(EXPRESSION | --query-file PATH)\n       " \
            "jmespath --validate (EXPRESSION | --query-file PATH)\n       jmespath --functions\n       " \
            "jmespath --interactive --file PATH"
    HELP = "#{USAGE}\n" \
           "Read one UTF-8 JSON document from --file PATH, or stdin when omitted.\n" \
           "Supply one query as EXPRESSION or --query-file PATH, read as UTF-8 without trimming.\n" \
           "Options may precede or follow EXPRESSION; -- ends option parsing.\n" \
           "Quote spaces: --file 'my document.json'. Use --file=--document.json for option-like names.\n" \
           "Paths are literal: --file - reads the file named -.\n" \
           "Query paths follow the same rules: --query-file - reads the query file named -.\n" \
           "Output is compact JSON by default; --pretty uses two-space indentation and a final newline.\n" \
           "Use --raw-output for literal string results; other results remain compact JSON.\n" \
           "Raw strings retain all their newlines and receive one additional output newline.\n" \
           "Output flags cannot be repeated or combined with each other or --validate.\n" \
           "Use --json-lines for one JSON record per physical input line and one compact result per record.\n" \
           "JSON Lines compiles once before input; empty input succeeds with a valid query.\n" \
           "Blank records are invalid; failures report the input line, retain earlier output, and exit 1.\n" \
           "Memory follows the current record and result; output uses normal buffering.\n" \
           "The --json-lines flag cannot be repeated or combined with --pretty, --raw-output, or --validate.\n" \
           "Function arguments and expression-reference results are validated; failures exit with status 1.\n" \
           "Unknown functions suggest similar registered names.\n" \
           "Query failures include source locations when available.\n" \
           "Use --interactive --file PATH for successive queries against one loaded document.\n" \
           "Enter one query per line; blank lines are ignored. :help shows help; :quit or EOF exits successfully.\n" \
           "Query errors are reported and the session continues; startup or stream failures exit 1.\n" \
           "Results are compact JSON on stdout; prompts and diagnostics use stderr.\n" \
           "Prompts appear only when stdin is a terminal; results are flushed after each query.\n" \
           "Interactive mode requires --file and rejects query sources, other modes, and information flags.\n" \
           "Use --validate to check syntax only, without reading stdin; unknown functions remain valid.\n" \
           "Validate saved queries with --validate --query-file PATH; --file is unavailable during validation.\n" \
           "The two-argument form --validate EXPRESSION always treats EXPRESSION as query text.\n" \
           "Validation exits with status 0 for valid syntax, 1 for query failures, and 2 for usage failures.\n" \
           "Use standalone --functions to list built-in signatures and descriptions without reading stdin.\n" \
           "The --functions flag cannot be repeated or combined with queries, paths, modes, or information flags.\n" \
           "Listing exits with status 0 on success, 1 for output failures, and 2 for usage failures.\n" \
           "#{FunctionListing::LEGEND}".freeze
  end
end
