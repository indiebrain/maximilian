# frozen_string_literal: true

module Maximilian
  # Parses tool-call protocols from the tail of an assistant reply.
  module Parser
    module_function

    # Find a tool call on the last line of the assistant's reply.
    # Returns [tool_name, params], or nil when the reply has no tool call.
    def parse_tool_call(text)
      stripped = text.to_s.strip

      return ["PWD", {}] if stripped.match?(/^PWD:?\z/)

      if (m = stripped.match(/^LISTFILES:[ \t]*(?<pattern>.*)\z/))
        pattern = m[:pattern].strip
        return ["LISTFILES", { pattern: pattern.empty? ? "*" : pattern }]
      end

      if (m = stripped.match(/^READFILE:[ \t]*(?<path>.+)\z/))
        return ["READFILE", { path: m[:path].strip }]
      end

      if (m = stripped.match(/^RUNCOMMAND:[ \t]*(?<command>.+)\z/))
        return ["RUNCOMMAND", { command: m[:command].strip }]
      end

      if (m = stripped.match(/^WRITEFILE:[ \t]*(?<path>[^\n]+)\n(?<content>.*)\z/m))
        content = m[:content]
        content += "\n" unless content.end_with?("\n")
        return ["WRITEFILE", { path: m[:path].strip, content: content }]
      end

      nil
    end
  end
end
