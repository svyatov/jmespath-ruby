# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    module InteractiveHelp
      TEXT = <<~TEXT
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
        Tab completes built-in function names outside quoted identifiers and literals, preserving surrounding text.
        Unique matches insert only a name. Ambiguous matches extend a common prefix or list sorted alternatives.
        Empty or unknown prefixes remain unchanged. Caller-owned streams remain open.
        Multiline editing and document reloads are unavailable.
      TEXT
    end
  end
end
