# spec/heuristics_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'OpenAPI Parser Heuristics' do
  let(:custom_spec) do
    {
      'openapi' => '3.1.0',
      'info' => { 'title' => 'AlphaPay API', 'version' => '2.0.0' },
      'components' => {
        'securitySchemes' => {
          'BearerAuth' => { 'type' => 'http', 'scheme' => 'bearer' }
        }
      },
      'paths' => {
        '/v2/transfers' => {
          'post' => {
            'operationId' => 'initiateTransfer',
            'summary' => 'Create a money transfer',
            'requestBody' => {
              'content' => {
                'application/json' => {
                  'schema' => {
                    'type' => 'object',
                    'properties' => {
                      'amount' => { 'type' => 'integer', 'minimum' => 50_000 },
                      'destination' => { 'type' => 'string' }
                    }
                  }
                }
              }
            },
            'responses' => {
              '200' => { 'description' => 'Success' },
              '403' => { 'description' => 'Forbidden' }
            }
          }
        },
        '/v2/transfers/{uuid}' => {
          'get' => {
            'operationId' => 'getTransferDetails',
            'responses' => { '200' => { 'description' => 'OK' } }
          }
        },
        '/notifications/callback' => {
          'post' => {
            'summary' => 'Event callback',
            'parameters' => [
              { 'name' => 'X-Alpha-Signature', 'in' => 'header', 'schema' => { 'type' => 'string' } }
            ]
          }
        }
      }
    }
  end

  subject(:parser) { Generator::Parser.new(custom_spec) }

  it 'распознает Bearer-авторизацию' do
    auth = parser.auth_details
    expect(auth[:type]).to eq('http')
    expect(auth[:scheme]).to eq('bearer')
    expect(parser.auth_summary).to eq('BearerAuth (HTTP Bearer)')
  end

  it 'находит эндпоинт создания перевода без жесткого пути /payouts' do
    op = parser.create_payout_operation
    expect(op[:path]).to eq('/v2/transfers')
    expect(op[:operation_id]).to eq('initiateTransfer')
    expect(op[:min_amount]).to eq(50_000)
  end

  it 'находит эндпоинт получения статуса по шаблону {uuid}' do
    op = parser.fetch_status_operation
    expect(op[:path]).to eq('/v2/transfers/{uuid}')
    expect(op[:operation_id]).to eq('getTransferDetails')
  end

  it 'находит вебхук по ключевому слову callback и извлекает заголовок сигнатуры' do
    wh = parser.webhook_details
    expect(wh[:path]).to eq('/notifications/callback')
    expect(wh[:signature_header]).to eq('X-Alpha-Signature')
  end
end