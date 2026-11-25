# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = false
end

# rubocop is optional; only wire it into `default` when it's actually installed.
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new

  task default: %i[test rubocop]
rescue LoadError
  task default: :test
end
