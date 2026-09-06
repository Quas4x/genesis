# spec/writer_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Generator::Writer do
  let(:spec_path) do
    [
      File.expand_path('fixtures/provider_api.yaml', __dir__)
    ].find { |path| File.exist?(path) }
  end
  let(:spec_hash) { YAML.safe_load_file(spec_path, permitted_classes: [Date, Time], aliases: true) }
  let(:parser) { Generator::Parser.new(spec_hash) }
  let(:model) { Generator::Model.new('novapay', parser) }

  it 'успешно генерирует все артефакты интеграции с поддержкой боевой логики' do
    Dir.mktmpdir do |dir|
      writer = described_class.new(model, output_dir: dir)
      generated_files = writer.generate_all!

      expect(generated_files.size).to eq(3)
      expect(File.exist?(File.join(dir, 'novapay_service.rb'))).to be true
      expect(File.exist?(File.join(dir, 'INTEGRATION.md'))).to be true
      expect(File.exist?(File.join(dir, 'fixtures.json'))).to be true

      service_code = File.read(File.join(dir, 'novapay_service.rb'))
      expect(service_code).to include('class NovapayService < BaseService')
      expect(service_code).to include('STATUS_MAP')
      expect(service_code).to include("OpenSSL::HMAC.hexdigest('SHA256'")
      expect(service_code).to include('OpenSSL.fixed_length_secure_compare')
      expect(service_code).to include("headers['Idempotency-Key'] = operation.id")
      expect(service_code).to include("'X-API-Key' => credentials.api_key")

      guide_text = File.read(File.join(dir, 'INTEGRATION.md'))
      expect(guide_text).to include('Novapay Integration Guide')

      fixtures = JSON.parse(File.read(File.join(dir, 'fixtures.json')))
      expect(fixtures['create_request']).to be_truthy
    end
  end
end