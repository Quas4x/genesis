# frozen_string_literal: true
# frozen_string_literal: true

require 'date'
require 'yaml'
require 'optparse'

require_relative 'generator/errors'
require_relative 'generator/ref_resolver'
require_relative 'generator/parser'
require_relative 'generator/model'
require_relative 'generator/writer'
require_relative 'generator/cli'

module Generator
  ROOT_DIR = File.expand_path('..', __dir__)
end
