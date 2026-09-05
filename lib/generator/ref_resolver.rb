# frozen_string_literal: true

module Generator
  class RefResolver
    def initialize(spec)
      @spec = spec || {}
    end

    # Рекурсивно раскрывает $ref ссылки во вложенных структурах
    def resolve(node)
      case node
      when Hash
        if node.key?('$ref')
          resolve_ref(node['$ref'])
        else
          node.transform_values { |v| resolve(v) }
        end
      when Array
        node.map { |v| resolve(v) }
      else
        node
      end
    end

    # Разрешает локальный JSON Pointer вида '#/components/schemas/Recipient'
    def resolve_ref(ref_path)
      return ref_path unless ref_path.start_with?('#/')

      parts = ref_path.delete_prefix('#/').split('/')
      target = @spec.dig(*parts)

      raise Generator::Error, "Unresolved reference: #{ref_path}" if target.nil?

      # Рекурсивно резолвим, если целевая схема сама содержит $ref
      resolve(target)
    end
  end
end