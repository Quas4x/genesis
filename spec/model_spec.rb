# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Generator::Model do
  let(:spec_path) do
    [
      File.expand_path('fixtures/provider_api.yaml', __dir__)
    ].find { |path| File.exist?(path) }
  end
  let(:spec_hash) { YAML.safe_load_file(spec_path, permitted_classes: [Date, Time], aliases: true) }
  let(:parser) { Generator::Parser.new(spec_hash) }
  subject(:model) { described_class.new('novapay', parser) }

  describe '#class_name' do
    it 'формирует корректное имя Ruby-класса' do
      expect(model.class_name).to eq('NovapayService')
    end
  end

  describe '#base_url' do
    it 'выбирает Sandbox URL провайдера' do
      expect(model.base_url).to eq('https://api.sandbox.novapay.example/v1')
    end
  end

  describe '#min_amount_rub' do
    it 'переводит минимальную сумму из копеек в рубли' do
      expect(model.min_amount_rub).to eq(1000)
    end
  end

  describe '#status_map' do
    it 'сопоставляет внешние статусы провайдера со статусами Space Payments' do
      map = model.status_map
      expect(map['pending']).to eq('in_progress')
      expect(map['processing']).to eq('in_progress')
      expect(map['completed']).to eq('approved')
      expect(map['failed']).to eq('rejected')
      expect(map['cancelled']).to eq('rejected')
    end
  end

  describe '#error_map' do
    it 'сопоставляет HTTP-коды ошибок с внутренними идентификаторами' do
      map = model.error_map
      expect(map[400]).to eq('validation_error')
      expect(map[401]).to eq('invalid_credentials')
      expect(map[402]).to eq('insufficient_balance')
      expect(map[429]).to eq('rate_limit')
      expect(map[500]).to eq('internal_error')
    end
  end

  describe '#fixtures_data' do
    it 'содержит структуру с примерами запросов, ответов и коллбеков' do
      data = model.fixtures_data
      expect(data).to have_key(:create_request)
      expect(data).to have_key(:fetch_status)
      expect(data).to have_key(:callback)
      expect(data).to have_key(:callback_failed)
      expect(data.dig(:callback, :expected_operation_status)).to eq('approved')
      expect(data.dig(:callback_failed, :expected_operation_status)).to eq('rejected')
    end
  end
end