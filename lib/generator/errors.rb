# frozen_string_literal: true

module Generator
  class Error < StandardError; end
  class MissingArgumentError < Error; end
  class SpecFileNotFoundError < Error; end
  class InvalidYamlError < Error; end
  class UnsupportedSpecVersionError < Error; end
end