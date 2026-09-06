# lib/generator/schema_synthesizer.rb
# frozen_string_literal: true

module Generator
  class SchemaSynthesizer
    MAX_DEPTH = 6

    def self.generate(schema, field_name = nil)
      new.generate(schema, field_name)
    end

    def generate(schema, field_name = nil, depth = 0)
      return {} if depth > MAX_DEPTH
      return nil unless schema.is_a?(Hash)
      return nil if schema['_circular']
      return schema['example'] if schema.key?('example')
      return schema['enum'].first if schema['enum'].is_a?(Array) && !schema['enum'].empty?

      type = schema['type'] || infer_type(schema)

      case type
      when 'object'
        generate_object(schema, depth)
      when 'array'
        generate_array(schema, field_name, depth)
      when 'string'
        generate_string(schema, field_name)
      when 'integer'
        schema['minimum'] || 100_000
      when 'number'
        schema['minimum'] || 100.0
      when 'boolean'
        true
      else
        {}
      end
    end

    private

    def infer_type(schema)
      return 'object' if schema.key?('properties')
      return 'array' if schema.key?('items')

      'string'
    end

    def generate_object(schema, depth)
      props = schema['properties'] || {}
      result = {}
      props.each do |key, prop_schema|
        val = generate(prop_schema, key, depth + 1)
        result[key] = val unless val.nil?
      end
      result
    end

    def generate_array(schema, field_name, depth)
      items = schema['items'] || {}
      val = generate(items, field_name, depth + 1)
      val ? [val] : []
    end

    def generate_string(schema, field_name)
      case schema['format']
      when 'uuid'
        '123e4567-e89b-12d3-a456-426614174000'
      when 'date-time'
        '2026-07-30T10:00:00Z'
      when 'date'
        '2026-07-30'
      when 'email'
        'merchant@example.com'
      else
        case field_name.to_s.downcase
        when 'currency' then 'RUB'
        when 'phone' then '79001234567'
        when /id$/ then 'sample_id_123'
        when 'status' then 'completed'
        when 'event' then 'payout.completed'
        else 'sample_value'
        end
      end
    end
  end
end