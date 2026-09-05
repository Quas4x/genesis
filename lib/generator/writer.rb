# lib/generator/writer.rb
# frozen_string_literal: true

require 'erb'
require 'json'
require 'fileutils'

module Generator
  class Writer
    TEMPLATES_DIR = File.expand_path('templates', __dir__)

    attr_reader :model, :output_dir

    def initialize(model, output_dir: 'output')
      @model = model
      @output_dir = output_dir
      FileUtils.mkdir_p(@output_dir)
    end

    def generate_all!
      [render_service, render_guide, render_fixtures]
    end

    def render_service
      template = File.read(File.join(TEMPLATES_DIR, 'service.rb.erb'))
      content = ERB.new(template, trim_mode: '-').result_with_hash(model: @model)

      target_file = File.join(@output_dir, "#{@model.provider_name}_service.rb")
      File.write(target_file, content)
      target_file
    end

    def render_guide
      template = File.read(File.join(TEMPLATES_DIR, 'integration.md.erb'))
      content = ERB.new(template, trim_mode: '-').result_with_hash(model: @model)

      target_file = File.join(@output_dir, 'INTEGRATION.md')
      File.write(target_file, content)
      target_file
    end

    def render_fixtures
      target_file = File.join(@output_dir, 'fixtures.json')
      File.write(target_file, JSON.pretty_generate(@model.fixtures_data))
      target_file
    end
  end
end