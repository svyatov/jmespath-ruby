# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InteractiveLineEditor < Reline::LineEditor
      # Dialogs registered by another Reline consumer do not belong to this session.
      def add_dialog_proc(_name, _callback, _context = nil); end
    end
  end
end
