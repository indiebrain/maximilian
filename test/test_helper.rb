# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "stringio"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "maximilian"
