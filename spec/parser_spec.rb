# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Generator::Parser do
  let(:spec_path) { File.expand_path('../provider_api.yaml', __dir__) }
  let(:spec_hash) { YAML.safe_load_file(spec_path, permitted_classes: [Date, Time], aliases: true) }
  subject(:parser) { described_class.new(spec_hash) }

  describe '#validate!' do
    it 'успешно проходит валидацию для спецификации OpenAPI 3.0.3' do
      expect { parser.validate! }.not_to raise_error
    end
  end

  describe '#auth_details' do
    it 'корректно определяет заголовок и тип авторизации' do
      auth = parser.auth_details
      expect(auth[:scheme_name]).to eq('ApiKeyAuth')
      expect(auth[:header_name]).to eq('X-API-Key')
      expect(auth[:in]).to eq('header')
    end
  end

  describe '#create_payout_operation' do
    it 'распознает минимальную сумму выплаты и разрешает ссылки схемы' do
      op = parser.create_payout_operation
      expect(op[:path]).to eq('/payouts')
      expect(op[:min_amount]).to eq(100_000)
      expect(op.dig(:request_schema, 'properties', 'recipient', 'properties', 'phone')).to be_truthy
    end
  end

  describe '#webhook_details' do
    it 'определяет заголовок сигнатуры HMAC и статусы вебхука' do
      wh = parser.webhook_details
      expect(wh[:signature_header]).to eq('X-NovaPay-Signature')
      expect(wh[:statuses]).to include('pending', 'completed', 'failed')
    end
  end

  describe '#error_codes_map' do
    it 'извлекает список кодов клиентских и серверных ошибок' do
      expect(parser.error_codes_map).to include(400, 401, 402, 409, 422, 429, 500)
    end
  end
end