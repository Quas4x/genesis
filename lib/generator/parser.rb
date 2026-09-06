# lib/generator/parser.rb
# frozen_string_literal: true

require_relative 'ref_resolver'

module Generator
  class Parser
    SUPPORTED_VERSIONS = %w[3.0.0 3.0.1 3.0.2 3.0.3 3.1.0].freeze

    PAYOUT_KEYWORDS = %w[payout transfer withdrawal disbursement payment send create].freeze
    STATUS_KEYWORDS = %w[status fetch details info order].freeze
    WEBHOOK_KEYWORDS = %w[webhook callback notification event].freeze

    attr_reader :spec, :resolver, :warnings

    def initialize(spec_hash)
      @spec = spec_hash || {}
      @resolver = RefResolver.new(@spec)
      @warnings = []
    end

    def validate!
      version = @spec['openapi'] || @spec['swagger']
      raise Generator::UnsupportedSpecVersionError, 'Missing "openapi" or "swagger" version key in spec' unless version

      # Поддерживаем Swagger 2.0 и OpenAPI 3.0-3.1
      if version.start_with?('2.') || SUPPORTED_VERSIONS.any? { |v| version.start_with?(v[0..2]) }
        return
      end

      raise Generator::UnsupportedSpecVersionError, "Unsupported specification version: #{version}"
    end

    def endpoints_summary
      paths = @spec['paths'] || {}
      paths.flat_map do |path, methods|
        next [] unless methods.is_a?(Hash)

        methods.keys.select { |k| %w[get post put patch delete].include?(k.downcase) }
               .map { |verb| "#{verb.upcase} #{path}" }
      end
    end

    def idempotency_header
      @parser.create_payout_operation&.dig(:idempotency_header)
    end

    def auth_headers_expression
      case auth[:type]
      when 'http'
        "{ 'Authorization' => \"Bearer \#{credentials.token}\" }"
      else
        header = auth[:header_name] || 'X-API-Key'
        "{ '#{header}' => credentials.api_key }"
      end
    end

def auth_details
      # В OpenAPI 3.x это components/securitySchemes, в Swagger 2.0 — securityDefinitions
      schemes = @spec.dig('components', 'securitySchemes') || @spec['securityDefinitions'] || {}
      if schemes.empty?
        add_warning('No security schemes found. Defaulting to empty auth.')
        return nil
      end

      # 1. Поиск ApiKey
      api_key = schemes.find { |_name, meta| meta['type'] == 'apiKey' }
      if api_key
        name, meta = api_key
        return {
          scheme_name: name,
          type: 'apiKey',
          in: meta['in'] || 'header',
          header_name: meta['name'] || 'X-API-Key'
        }
      end

      # 2. Поиск HTTP Bearer / Basic
      # В Swagger 2.0 Basic Auth описывается как type: basic
      basic_auth = schemes.find { |_name, meta| meta['type'] == 'basic' }
      if basic_auth
        name, _meta = basic_auth
        return {
          scheme_name: name,
          type: 'http',
          scheme: 'basic',
          in: 'header',
          header_name: 'Authorization'
        }
      end

      http_scheme = schemes.find { |_name, meta| meta['type'] == 'http' }
      if http_scheme
        name, meta = http_scheme
        scheme_type = meta['scheme']&.downcase || 'bearer'
        return {
          scheme_name: name,
          type: 'http',
          scheme: scheme_type,
          in: 'header',
          header_name: 'Authorization'
        }
      end

      # 3. Fallback: первый доступный
      name, meta = schemes.first
      add_warning("Unsupported auth type '#{meta['type']}'. Using generic header.")
      {
        scheme_name: name,
        type: meta['type'],
        in: meta['in'] || 'header',
        header_name: meta['name'] || 'Authorization'
      }
    end

    def auth_summary
      auth = auth_details
      return 'None or Unknown' unless auth

      case auth[:type]
      when 'apiKey'
        "#{auth[:scheme_name]} (header: #{auth[:header_name]})"
      when 'http'
        "#{auth[:scheme_name]} (HTTP #{auth[:scheme]&.capitalize})"
      else
        "#{auth[:scheme_name]} (#{auth[:type]})"
      end
    end

    def create_payout_operation
      candidates = []
      paths = @spec['paths'] || {}

      paths.each do |path, methods|
        next unless methods.is_a?(Hash)
        post_op = methods['post']
        next unless post_op.is_a?(Hash)

        score = 0
        text = "#{path} #{post_op['operationId']} #{post_op['summary']} #{post_op['tags']&.join(' ')}".downcase

        score += 10 if PAYOUT_KEYWORDS.any? { |kw| text.include?(kw) }
        score -= 15 if text.match?(/\b(cancel|refund|reverse|webhook|callback)\b/)

        # Раскрываем схему только если эндпоинт семантически похож на создание выплаты
        schema = nil
        if score > 0
          raw_schema = post_op.dig('requestBody', 'content', 'application/json', 'schema')
          schema = @resolver.resolve(raw_schema) if raw_schema
          if schema.is_a?(Hash) && schema['properties'].is_a?(Hash)
            props = schema['properties'].keys.map(&:downcase)
            score += 5 if props.include?('amount')
            score += 3 if props.any? { |p| %w[recipient account destination phone].include?(p) }
          end
        end

        candidates << { path: path, op: post_op, schema: schema, score: score } if score > 0
      end

      best = candidates.max_by { |c| c[:score] }
      if best.nil? || best[:score] <= 0
        add_warning('Could not detect payout creation endpoint. Fallback to /payouts.')
        return nil
      end

      op = best[:op]
      schema = best[:schema]
      min_amount = schema&.dig('properties', 'amount', 'minimum')

      if min_amount.nil?
        add_warning('Minimum payout amount not specified in schema. Defaulting to 0.')
      end

      raw_params = op['parameters'] || []
      resolved_params = @resolver.resolve(raw_params)
      idem_param = resolved_params.find do |p|
        p.is_a?(Hash) && (p['name']&.match?(/idempotency|request-id/i) || false)
      end

      {
        path: best[:path],
        method: 'post',
        operation_id: op['operationId'],
        min_amount: min_amount,
        request_schema: schema,
        idempotency_header: idem_param&.dig('name'),
        examples: op.dig('requestBody', 'content', 'application/json', 'examples')
      }
    end

    def fetch_status_operation
      candidates = []
      paths = @spec['paths'] || {}

      paths.each do |path, methods|
        next unless methods.is_a?(Hash)
        get_op = methods['get']
        next unless get_op.is_a?(Hash)

        score = 0
        score += 10 if path =~ %r{/\{[^/]+\}$}
        text = "#{path} #{get_op['operationId']} #{get_op['summary']}".downcase

        score += 5 if (PAYOUT_KEYWORDS + STATUS_KEYWORDS).any? { |kw| text.include?(kw) }
        score -= 10 if text.match?(/\b(balance|users|history|metrics)\b/)

        candidates << { path: path, op: get_op, score: score }
      end

      best = candidates.max_by { |c| c[:score] }
      if best.nil? || best[:score] <= 0
        add_warning('Could not detect status fetching endpoint.')
        return nil
      end

      op = best[:op]
      {
        path: best[:path],
        method: 'get',
        operation_id: op['operationId'],
        responses: @resolver.resolve(op['responses'])
      }
    end

    def webhook_details
      candidates = []
      all_endpoints = (@spec['paths'] || {}).merge(@spec['webhooks'] || {})

      all_endpoints.each do |path, methods|
        next unless methods.is_a?(Hash)
        op = methods['post'] || methods['put']
        next unless op.is_a?(Hash)

        score = 0
        text = "#{path} #{op['operationId']} #{op['summary']}".downcase

        is_webhook = WEBHOOK_KEYWORDS.any? { |kw| text.include?(kw) }
        score += 15 if is_webhook
        # Исключаем CRUD-эндпоинты регистрации вебхуков (как в Stripe /v1/webhook_endpoints)
        score -= 20 if path.match?(%r{/webhook_endpoints(/|\z)})

        params = op['parameters'] || []
        # Сигнатура может быть только в header
        sig_param = params.find do |p|
          p.is_a?(Hash) && (p['in'] == 'header' || p['in'].nil?) && p['name']&.match?(/sign|hmac|signature/i)
        end
        score += 10 if sig_param && is_webhook

        candidates << { path: path, op: op, sig_param: sig_param, score: score } if score > 0
      end

      best = candidates.max_by { |c| c[:score] }
      if best.nil? || best[:score] <= 0
        add_warning('Webhook endpoint not detected in specification.')
        return nil
      end

      op = best[:op]
      schema = @resolver.resolve(op.dig('requestBody', 'content', 'application/json', 'schema'))
      statuses = schema&.dig('properties', 'status', 'enum') || []

      unless best[:sig_param]
        add_warning('Webhook signature header not found in parameters. Defaulting to X-Signature.')
      end

      {
        path: best[:path],
        method: 'post',
        signature_header: best[:sig_param]&.dig('name') || 'X-Signature',
        signature_type: 'HMAC-SHA256',
        payload_schema: schema,
        statuses: statuses,
        examples: op.dig('requestBody', 'content', 'application/json', 'examples')
      }
    end

    def webhook_summary
      wh = webhook_details
      return 'Not detected' unless wh&.dig(:signature_header)

      "#{wh[:signature_header]} (#{wh[:signature_type]})"
    end

    def error_codes_map
      create_op = create_payout_operation
      responses = if create_op
                    @spec.dig('paths', create_op[:path], 'post', 'responses') || {}
                  else
                    {}
                  end

      codes = responses.keys.select { |code| code.to_i >= 400 }.map(&:to_i)
      return codes.sort unless codes.empty?

      fallback_codes = []
      (@spec['paths'] || {}).each_value do |methods|
        next unless methods.is_a?(Hash)
        methods.each_value do |meta|
          next unless meta.is_a?(Hash) && meta['responses'].is_a?(Hash)
          meta['responses'].each_key do |resp_code|
            c = resp_code.to_i
            fallback_codes << c if c >= 400
          end
        end
      end
      fallback_codes.uniq.sort
    end

    private

    def add_warning(message)
      @warnings << message unless @warnings.include?(message)
    end
  end
end