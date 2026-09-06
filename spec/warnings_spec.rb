# spec/warnings_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Generator Warnings System' do
  let(:incomplete_spec) do
    {
      'openapi' => '3.0.3',
      'info' => { 'title' => 'Minimal API', 'version' => '1.0.0' },
      'paths' => {
        '/payouts' => {
          'post' => {
            'operationId' => 'createPayout',
            'requestBody' => {
              'content' => {
                'application/json' => {
                  'schema' => {
                    'type' => 'object',
                    'properties' => { 'amount' => { 'type' => 'integer' } } # minimum не указан
                  }
                }
              }
            }
          }
        },
        '/callback' => {
          'post' => {
            'summary' => 'Webhook notification' # signature header не указан
          }
        }
      }
    }
  end

  subject(:parser) { Generator::Parser.new(incomplete_spec) }

  it 'фиксирует предупреждение об отсутствии схем авторизации' do
    parser.auth_details
    expect(parser.warnings).to include(match(/No security schemes found/))
  end

  it 'фиксирует предупреждение об отсутствии минимального лимита суммы' do
    parser.create_payout_operation
    expect(parser.warnings).to include(match(/Minimum payout amount not specified/))
  end

  it 'фиксирует предупреждение об отсутствии сигнатуры вебхука и выставляет дефолт' do
    wh = parser.webhook_details
    expect(wh[:signature_header]).to eq('X-Signature')
    expect(parser.warnings).to include(match(/Webhook signature header not found/))
  end
end