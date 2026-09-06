# lib/generator/model.rb
# frozen_string_literal: true

module Generator
  class Model
    DEFAULT_STATUS_MAP = {
      'pending'    => 'in_progress',
      'processing' => 'in_progress',
      'completed'  => 'approved',
      'success'    => 'approved',
      'failed'     => 'rejected',
      'cancelled'  => 'rejected',
      'declined'   => 'rejected'
    }.freeze

    DEFAULT_ERROR_MAP = {
      400 => 'validation_error',
      401 => 'invalid_credentials',
      402 => 'insufficient_balance',
      422 => 'validation_error',
      429 => 'rate_limit',
      500 => 'internal_error'
    }.freeze

    attr_reader :provider_name, :parser

    def initialize(provider_name, parser)
      @raw_name = provider_name.to_s
      @provider_name = sanitize_snake_case(@raw_name)
      @parser = parser
    end

    # Превращает любые строки ("Stripe API-swagger", "gov.uk") в валидный CamelCase класс Ruby:
    # "StripeApiSwaggerService", "GovUkPayApiSwaggerService"
    def class_name
      words = @raw_name.split(/[^a-zA-Z0-9]+/).reject(&:empty?)
      camel = words.map(&:capitalize).join
      
      # Если имя пустое — ставим дефолтное
      camel = 'CustomProvider' if camel.empty?
      
      # Если имя начинается с цифры, добавляем префикс (например, Api20200914Service)
      camel = "Api#{camel}" if camel.match?(/^\d/)
      
      "#{camel}Service"
    end

    def env_base_url_key
      words = @raw_name.split(/[^a-zA-Z0-9]+/).reject(&:empty?)
      key = words.map(&:upcase).join('_')
      key = 'PROVIDER' if key.empty?
      "#{key}_BASE_URL"
    end

    def create_path
      @parser.create_payout_operation&.dig(:path) || '/payouts'
    end

    def status_path_template
      @parser.fetch_status_operation&.dig(:path) || '/payouts/{id}'
    end

    def idempotency_header
      @parser.create_payout_operation&.dig(:idempotency_header)
    end

    def base_url
      servers = @parser.spec['servers'] || []
      sandbox = servers.find { |s| s['description']&.downcase&.include?('sandbox') }
      sandbox&.dig('url') || servers.first&.dig('url') || 'https://api.example.com/v1'
    end

    def auth
      @parser.auth_details || { header_name: 'X-API-Key', scheme_name: 'ApiKeyAuth', type: 'apiKey' }
    end

    def auth_headers_expression
      case auth[:type]
      when 'http'
        if auth[:scheme] == 'basic'
          "{ 'Authorization' => \"Basic \#{credentials.api_key}\" }"
        else
          "{ 'Authorization' => \"Bearer \#{credentials.token}\" }"
        end
      else
        header = auth[:header_name] || 'X-API-Key'
        "{ '#{header}' => credentials.api_key }"
      end
    end

    def min_amount_rub
      payout_op = @parser.create_payout_operation
      raw_min = payout_op&.dig(:min_amount)
      return 0 unless raw_min

      raw_min / 100
    end

    def status_map
      wh = @parser.webhook_details
      statuses = wh&.dig(:statuses) || []

      map = {}
      statuses.each do |st|
        normalized = st.to_s.downcase
        map[st] = DEFAULT_STATUS_MAP[normalized] || 'in_progress'
      end

      map.empty? ? DEFAULT_STATUS_MAP : map
    end

    def error_map
      codes = @parser.error_codes_map
      map = {}
      codes.each do |code|
        map[code] = DEFAULT_ERROR_MAP[code] || 'unexpected_error'
      end
      map.empty? ? DEFAULT_ERROR_MAP : map
    end

    def webhook
      @parser.webhook_details || {
        signature_header: 'X-Signature',
        signature_type: 'HMAC-SHA256'
      }
    end

    def fixtures_data
      payout_op = @parser.create_payout_operation || {}
      payout_req_example = extract_example(payout_op[:examples]) ||
                           SchemaSynthesizer.generate(payout_op[:request_schema])

      status_op = @parser.fetch_status_operation || {}
      status_schema = status_op.dig(:responses, '200', 'content', 'application/json', 'schema')
      status_example = extract_example(status_op.dig(:responses, '200', 'content', 'application/json', 'examples')) ||
                       SchemaSynthesizer.generate(status_schema)

      wh = @parser.webhook_details || {}
      wh_example = extract_example(wh[:examples]) ||
                   SchemaSynthesizer.generate(wh[:payload_schema])

      callback_success = wh_example.is_a?(Hash) ? wh_example.dup : { 'status' => 'completed' }
      callback_success['status'] = 'completed' if callback_success.key?('status')
      callback_success['event'] = 'payout.completed' if callback_success.key?('event')

      callback_failed = wh_example.is_a?(Hash) ? wh_example.dup : { 'status' => 'failed' }
      callback_failed['status'] = 'failed' if callback_failed.key?('status')
      callback_failed['event'] = 'payout.failed' if callback_failed.key?('event')
      callback_failed['error'] = { 'code' => 'rejected_by_bank', 'message' => 'Operation declined' }

      {
        create_request: {
          request: payout_req_example,
          response_201: { id: 'sample_id_123', status: 'pending' },
          response_422: { error: { code: 'validation_error', message: 'Validation failed' } }
        },
        fetch_status: {
          response_200: status_example || { id: 'sample_id_123', status: 'completed' }
        },
        callback: {
          payload: callback_success,
          expected_operation_status: status_map[callback_success['status']] || 'approved'
        },
        callback_failed: {
          payload: callback_failed,
          expected_operation_status: status_map[callback_failed['status']] || 'rejected'
        }
      }
    end

    private

    def sanitize_snake_case(str)
      words = str.split(/[^a-zA-Z0-9]+/).reject(&:empty?)
      words.map(&:downcase).join('_')
    end

    def extract_example(examples_node)
      return nil unless examples_node.is_a?(Hash) && !examples_node.empty?

      first_entry = examples_node.values.first
      first_entry.is_a?(Hash) && first_entry.key?('value') ? first_entry['value'] : first_entry
    end
  end
end