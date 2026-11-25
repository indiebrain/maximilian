# frozen_string_literal: true

require_relative "lib/maximilian/version"

Gem::Specification.new do |s|
  s.name        = "maximilian"
  s.version      = Maximilian::VERSION
  s.summary       = "A single-file coding agent with tool use and a REPL loop."
  s.description   = "Maximilian is a CLI coding assistant that streams replies from a model " \
                    "API, parses tool calls from the reply, executes them, and feeds results " \
                    "back into the conversation."
  s.authors      = ["Aaron Kuehler"]
  s.email        = ["aaron.kuehler@gmail.com"]
  s.license       = "MIT"

  s.files         = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE"]
  s.bindir        = "bin"
  s.executables   = ["maximilian"]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 3.0"

  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "rake",     "~> 13.0"
  s.add_development_dependency "rubocop",  "~> 1.0"
end
