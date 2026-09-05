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
      @provider_name = provider_name.to_s.downcase
      @parser = parser
    end

    def class_name
      "#{@provider_name.capitalize}Service"
    end

    def env_base_url_key
      "#{@provider_name.upcase}_BASE_URL"
    end

    def base_url
      servers = @parser.spec['servers'] || []
      sandbox = servers.find { |s| s['description']&.downcase&.include?('sandbox') }
      sandbox&.dig('url') || servers.first&.dig('url') || 'https://api.example.com/v1'
    end

    def auth
      @parser.auth_details || { header_name: 'X-API-Key', scheme_name: 'ApiKeyAuth' }
    end

    def min_amount_rub
      payout_op = @parser.create_payout_operation
      raw_min = payout_op&.dig(:min_amount) || 100_000
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
      payout_example = payout_op.dig(:examples, 'sbp_payout', 'value') || {
        amount: 1_500_000,
        currency: 'RUB',
        external_id: 'op_abc123',
        recipient: { type: 'sbp', phone: '79001234567', bank_code: '044525225' }
      }

      wh = @parser.webhook_details || {}
      wh_completed = wh.dig(:examples, 'completed', 'value') || {
        event: 'payout.completed',
        payout_id: 'np_7f3a9b2c',
        status: 'completed'
      }
      wh_failed = wh.dig(:examples, 'failed', 'value') || {
        event: 'payout.failed',
        payout_id: 'np_7f3a9b2c',
        status: 'failed',
        error: { code: 'recipient_not_found' }
      }

      {
        create_request: {
          request: payout_example,
          response_201: { id: 'np_7f3a9b2c', status: 'pending' },
          response_422: { error: { code: 'validation_error', message: 'Amount must be at least 100000 kopecks' } }
        },
        fetch_status: {
          response_200: { id: 'np_7f3a9b2c', status: 'completed' }
        },
        callback: {
          payload: wh_completed,
          expected_operation_status: status_map[wh_completed['status']] || 'approved'
        },
        callback_failed: {
          payload: wh_failed,
          expected_operation_status: status_map[wh_failed['status']] || 'rejected'
        }
      }
    end
  end
end