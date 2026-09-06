# spec/contract_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Universal OpenAPI Invariant Contract' do
  # Исключаем намеренно сломанные тестовые файлы (например, invalid_syntax.yaml)
  spec_files = Dir.glob(File.expand_path('fixtures/*.{yaml,yml}', __dir__))
                  .reject { |f| File.basename(f).include?('invalid') }
                  .uniq

  spec_files.each do |spec_path|
    provider_name = File.basename(spec_path, '.*').sub(/_api$/, '')

    context "для спецификации #{File.basename(spec_path)}" do
      let(:spec_hash) { YAML.safe_load_file(spec_path, permitted_classes: [Date, Time], aliases: true) }
      let(:parser) { Generator::Parser.new(spec_hash) }
      let(:model) { Generator::Model.new(provider_name, parser) }

      it 'успешно парсит схему и выявляет эндпоинты' do
        expect { parser.validate! }.not_to raise_error
        expect(parser.endpoints_summary).to be_an(Array)
      end

      it 'генерирует валидный синтаксис Ruby (без SyntaxError)' do
        Dir.mktmpdir do |dir|
          writer = Generator::Writer.new(model, output_dir: dir)
          service_path = writer.render_service
          code = File.read(service_path)

          expect do
            RubyVM::InstructionSequence.compile(code)
          end.not_to raise_error, "Сгенерированный файл #{service_path} содержит синтаксические ошибки"
        end
      end

      it 'строго соблюдает контракт методов BaseService' do
        Dir.mktmpdir do |dir|
          writer = Generator::Writer.new(model, output_dir: dir)
          code = File.read(writer.render_service)

          expect(code).to match(/class \w+Service < BaseService/)
          expect(code).to include('def create_request(')
          expect(code).to include('def fetch_status(')
          expect(code).to include('def process_callback(')
          expect(code).to include('def check_conditions(')
        end
      end

      it 'генерирует валидные тестовые фикстуры и документацию' do
        Dir.mktmpdir do |dir|
          writer = Generator::Writer.new(model, output_dir: dir)
          writer.generate_all!

          fixtures = JSON.parse(File.read(File.join(dir, 'fixtures.json')))
          expect(fixtures).to have_key('create_request')
          expect(fixtures).to have_key('fetch_status')
          expect(fixtures).to have_key('callback')

          guide = File.read(File.join(dir, 'INTEGRATION.md'))
          expect(guide).to include('## Авторизация')
          expect(guide).to include('## Методы')
        end
      end
    end
  end
end