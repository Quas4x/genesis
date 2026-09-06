# spec/cli_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Generator::CLI do
  let(:valid_spec_path) { File.expand_path('fixtures/provider_api.yaml', __dir__) }
  let(:invalid_syntax_path) { File.expand_path('fixtures/invalid_syntax.yaml', __dir__) }

  describe '.run' do
    it 'возвращает код 1 при поврежденном YAML синтаксисе' do
      args = ['--spec', invalid_syntax_path, '--provider', 'novapay', '--lang', 'ruby']

      expect do
        result = described_class.run(args)
        expect(result).to eq(1)
      end.to output(/Failed to parse YAML file/).to_stderr
    end

    it 'успешно завершает выполнение с кодом 0 и выводит сводку при корректных параметрах' do
      Dir.mktmpdir do |dir|
        args = ['--spec', valid_spec_path, '--provider', 'novapay', '--lang', 'ruby', '--output', dir]

        expect do
          result = described_class.run(args)
          expect(result).to eq(0)
        end.to output(/Parsing spec\.\.\./).to_stdout
      end
    end
  end
end