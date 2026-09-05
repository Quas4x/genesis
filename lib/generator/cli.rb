# lib/generator/cli.rb
# frozen_string_literal: true

module Generator
  class CLI
    REQUIRED_OPTIONS = %i[spec provider lang].freeze

    def self.run(argv)
      new(argv).execute
    end

    def initialize(argv)
      @argv = argv
      @options = {}
    end

    def execute
      parse_options!
      validate_options!
      validate_file_existence!

      spec_content = load_yaml_spec!
      parser = Generator::Parser.new(spec_content)
      parser.validate!

      output_summary(parser)

      model = Generator::Model.new(@options[:provider], parser)
      writer = Generator::Writer.new(model, output_dir: 'output')

      puts 'Generating service...'
      writer.render_service

      puts 'Generating integration guide...'
      writer.render_guide

      puts 'Generating test fixtures...'
      writer.render_fixtures

      puts 'Output:'
      puts "  ./output/#{@options[:provider]}_service.rb"
      puts '  ./output/INTEGRATION.md'
      puts '  ./output/fixtures.json'

      0
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
        opts.banner = 'Usage: ./integrate [options]'

        opts.on('--spec FILE', 'Path to OpenAPI spec file (YAML)') do |value|
          @options[:spec] = value
        end

        opts.on('--provider NAME', 'Provider name (e.g., novapay)') do |value|
          @options[:provider] = value
        end

        opts.on('--lang LANGUAGE', 'Target language (e.g., ruby)') do |value|
          @options[:lang] = value
        end
      end

      parser.parse!(@argv)
    end

    def validate_options!
      missing = REQUIRED_OPTIONS.reject { |opt| @options[opt] && !@options[opt].strip.empty? }
      return if missing.empty?

      raise Generator::MissingArgumentError,
            "Missing required options: #{missing.map { |m| "--#{m}" }.join(', ')}. " \
            'Example: ./integrate --spec provider_api.yaml --provider novapay --lang ruby'
    end

    def validate_file_existence!
      path = @options[:spec]
      return if File.exist?(path)

      raise Generator::SpecFileNotFoundError, "Specification file not found at path: #{path}"
    end

    def load_yaml_spec!
      YAML.safe_load_file(@options[:spec], permitted_classes: [Date, Time], aliases: true)
    rescue Psych::SyntaxError => e
      raise Generator::InvalidYamlError, "Failed to parse YAML file: #{e.message}"
    end

    def output_summary(parser)
      puts 'Parsing spec...'
      endpoints = parser.endpoints_summary
      puts "Found #{endpoints.size} endpoints: #{endpoints.join(', ')}"
      puts "Auth: #{parser.auth_summary}"
      puts "Webhook signature: #{parser.webhook_summary}"
    end
  end
end