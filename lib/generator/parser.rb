# frozen_string_literal: true

require_relative 'ref_resolver'

module Generator
  class Parser
    SUPPORTED_VERSIONS = %w[3.0.0 3.0.1 3.0.2 3.0.3 3.1.0].freeze

    attr_reader :spec, :resolver

    def initialize(spec_hash)
      @spec = spec_hash || {}
      @resolver = RefResolver.new(@spec)
    end

    def validate!
      version = @spec['openapi']
      raise Generator::UnsupportedSpecVersionError, 'Missing "openapi" version key in spec' unless version

      return if SUPPORTED_VERSIONS.any? { |v| version.start_with?(v[0..2]) }

      raise Generator::UnsupportedSpecVersionError, "Unsupported OpenAPI version: #{version}"
    end

    def endpoints_summary
      paths = @spec['paths'] || {}
      paths.flat_map do |path, methods|
        methods.keys.select { |k| %w[get post put patch delete].include?(k.downcase) }
               .map { |verb| "#{verb.upcase} #{path}" }
      end
    end

    # Извлечение схемы авторизации: тип, заголовок, имя ключа
    def auth_details
      schemes = @spec.dig('components', 'securitySchemes') || {}
      api_key = schemes.find { |_name, meta| meta['type'] == 'apiKey' }

      return nil unless api_key

      name, meta = api_key
      {
        scheme_name: name,
        type: meta['type'],
        in: meta['in'],
        header_name: meta['name']
      }
    end

    def auth_summary
      auth = auth_details
      return 'None or Unknown' unless auth

      "#{auth[:scheme_name]} (header: #{auth[:header_name]})"
    end

    # Поиск операции создания выплаты (POST /payouts или тег Payouts)
    def create_payout_operation
      op = @spec.dig('paths', '/payouts', 'post')
      return nil unless op

      request_schema = @resolver.resolve(op.dig('requestBody', 'content', 'application/json', 'schema'))
      min_amount = request_schema&.dig('properties', 'amount', 'minimum')

      {
        path: '/payouts',
        method: 'post',
        operation_id: op['operationId'],
        min_amount: min_amount,
        request_schema: request_schema,
        examples: op.dig('requestBody', 'content', 'application/json', 'examples')
      }
    end

    # Поиск операции получения статуса (GET /payouts/{id} или {payout_id})
    def fetch_status_operation
      path_entry = @spec['paths']&.find { |p, _| p =~ %r{^/payouts/\{[^/]+\}$} }
      return nil unless path_entry

      path, methods = path_entry
      op = methods['get']
      return nil unless op

      {
        path: path,
        method: 'get',
        operation_id: op['operationId'],
        responses: @resolver.resolve(op['responses'])
      }
    end

    # Извлечение параметров Webhook
    def webhook_details
      webhook_op = @spec.dig('paths', '/webhooks/payout', 'post')
      return nil unless webhook_op

      params = webhook_op['parameters'] || []
      sig_param = params.find { |p| p['name']&.include?('Signature') }

      schema = @resolver.resolve(webhook_op.dig('requestBody', 'content', 'application/json', 'schema'))
      statuses = schema&.dig('properties', 'status', 'enum') || []

      {
        path: '/webhooks/payout',
        method: 'post',
        signature_header: sig_param&.dig('name'),
        signature_type: 'HMAC-SHA256',
        payload_schema: schema,
        statuses: statuses,
        examples: webhook_op.dig('requestBody', 'content', 'application/json', 'examples')
      }
    end

    def webhook_summary
      wh = webhook_details
      return 'Not detected' unless wh&.dig(:signature_header)

      "#{wh[:signature_header]} (#{wh[:signature_type]})"
    end

    # Извлечение маппинга HTTP-ошибок
    def error_codes_map
      create_responses = @spec.dig('paths', '/payouts', 'post', 'responses') || {}
      create_responses.keys.select { |code| code.to_i >= 400 }.map(&:to_i).sort
    end
  end
end