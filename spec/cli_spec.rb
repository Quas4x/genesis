# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/generator'

RSpec.describe Generator::CLI do
  let(:valid_spec_path) { File.expand_path('fixtures/minimal_valid.yaml', __dir__) }
  let(:invalid_yaml_path) { File.expand_path('fixtures/invalid_syntax.txt', __dir__) }

  describe '.run' do
    context 'при проверке файла спецификации' do
      it 'возвращает код 1 при поврежденном YAML синтаксисе' do
        require 'tempfile'
        
        file = Tempfile.new(['invalid', '.yaml'])
        file.write("openapi: 3.0.3\n  invalid_indentation: true\n    broken: [")
        file.close

        args = ['--spec', file.path, '--provider', 'novapay', '--lang', 'ruby']
        expect {
          result = described_class.run(args)
          expect(result).to eq(1)
        }.to output(/Failed to parse YAML file/).to_stderr

        file.unlink
      end
    end

    context 'при корректных параметрах' do
      it 'успешно завершает выполнение с кодом 0 и выводит сводку' do
        args = ['--spec', valid_spec_path, '--provider', 'novapay', '--lang', 'ruby']
        expect {
          result = described_class.run(args)
          expect(result).to eq(0)
        }.to output(/Found 2 endpoints: POST \/payouts, GET \/payouts\/\{id\}/).to_stdout
      end
    end
  end
end