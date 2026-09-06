# spec/schema_synthesizer_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Generator::SchemaSynthesizer do
  subject(:synthesizer) { described_class }

  it 'синтезирует вложенный объект с типами string, integer и boolean' do
    schema = {
      'type' => 'object',
      'properties' => {
        'amount' => { 'type' => 'integer', 'minimum' => 5000 },
        'is_active' => { 'type' => 'boolean' },
        'recipient' => {
          'type' => 'object',
          'properties' => {
            'phone' => { 'type' => 'string' }
          }
        }
      }
    }

    result = synthesizer.generate(schema)
    expect(result['amount']).to eq(5000)
    expect(result['is_active']).to be true
    expect(result.dig('recipient', 'phone')).to eq('79001234567')
  end

  it 'выбирает первое значение из enum' do
    schema = { 'type' => 'string', 'enum' => %w[card sbp wallet] }
    expect(synthesizer.generate(schema)).to eq('card')
  end

  it 'распознает формат uuid и date-time' do
    uuid_schema = { 'type' => 'string', 'format' => 'uuid' }
    date_schema = { 'type' => 'string', 'format' => 'date-time' }

    expect(synthesizer.generate(uuid_schema)).to match(/^[0-9a-f-]+$/)
    expect(synthesizer.generate(date_schema)).to include('2026')
  end
end