# lib/generator/cli.rb
# frozen_string_literal: true

require 'optparse'
require 'yaml'

module Generator
  class CLI
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv
      @options = {
        lang: 'ruby',
        output: 'output'
      }
    end

    def run
      parse_options!
      validate_options!

      spec_hash = load_spec(@options[:spec])
      parser = Parser.new(spec_hash)
      parser.validate!

      output_summary(parser)

      model = Model.new(@options[:provider], parser)
      writer = Writer.new(model, output_dir: @options[:output])

      puts 'Generating service...'
      puts 'Generating integration guide...'
      puts 'Generating test fixtures...'
      generated_files = writer.generate_all!

      puts 'Output:'
      generated_files.each { |f| puts "  #{f}" }
      0
    rescue OptionParser::ParseError => e
      warn "Error: #{e.message}"
      1
    rescue Psych::SyntaxError => e
      warn "Error: Failed to parse YAML file: #{e.message}"
      1
    rescue Generator::Error => e
      warn "Error: #{e.message}"
      1
    rescue StandardError => e
      warn "Unexpected error: #{e.message}"
      1
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: integrate --spec <path> --provider <name> [--lang <ruby>] [--output <dir>]'

        opts.on('-s', '--spec PATH', 'Path to OpenAPI specification') do |v|
          @options[:spec] = v
        end

        opts.on('-p', '--provider NAME', 'Provider name') do |v|
          @options[:provider] = v
        end

        opts.on('-l', '--lang LANG', 'Target language (default: ruby)') do |v|
          @options[:lang] = v
        end

        opts.on('-o', '--output DIR', 'Output directory (default: output)') do |v|
          @options[:output] = v
        end

        opts.on('-h', '--help', 'Show this help message') do
          puts opts
          exit 0
        end
      end

      parser.parse!(@argv)
    end

    def validate_options!
      raise Generator::ValidationError, 'Missing required argument: --spec' unless @options[:spec]
      raise Generator::ValidationError, 'Missing required argument: --provider' unless @options[:provider]
      raise Generator::ValidationError, "Spec file not found: #{@options[:spec]}" unless File.exist?(@options[:spec])
    end

    def load_spec(path)
      YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: true)
    end

    def output_summary(parser)
      puts 'Parsing spec...'
      endpoints = parser.endpoints_summary
      puts "Found #{endpoints.size} endpoints: #{endpoints.join(', ')}"
      puts "Auth: #{parser.auth_summary}"
      puts "Webhook signature: #{parser.webhook_summary}"

      if parser.warnings.any?
        puts 'Warnings:'
        parser.warnings.each { |warning| puts "  - [WARN] #{warning}" }
      end
    end
  end
end