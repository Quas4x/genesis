# lib/generator/ref_resolver.rb
# frozen_string_literal: true

module Generator
  class RefResolver
    MAX_DEPTH = 15

    attr_reader :spec

    def initialize(spec)
      @spec = spec || {}
    end

    def resolve(node, visited = [], depth = 0)
      return node if depth > MAX_DEPTH
      return node unless node.is_a?(Hash) || node.is_a?(Array)

      if node.is_a?(Hash)
        if node.key?('$ref')
          ref_path = node['$ref']
          # Если этот $ref уже раскрывается выше по дереву вызовов — останавливаем цикл
          return { '$ref' => ref_path, '_circular' => true, 'type' => 'object' } if visited.include?(ref_path)

          target = resolve_ref(ref_path)
          return { '$ref' => ref_path } if target.nil?

          resolve(target, visited + [ref_path], depth + 1)
        else
          node.transform_values { |v| resolve(v, visited, depth + 1) }
        end
      elsif node.is_a?(Array)
        node.map { |v| resolve(v, visited, depth + 1) }
      else
        node
      end
    end

    def resolve_ref(ref_path)
      return nil unless ref_path.is_a?(String) && ref_path.start_with?('#/')

      parts = ref_path.delete_prefix('#/').split('/')
      parts.reduce(@spec) do |current, part|
        unescaped_part = part.gsub('~1', '/').gsub('~0', '~')
        return nil unless current.is_a?(Hash) && current.key?(unescaped_part)

        current[unescaped_part]
      end
    end
  end
end