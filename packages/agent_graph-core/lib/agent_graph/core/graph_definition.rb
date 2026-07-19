# frozen_string_literal: true

module AgentGraph
  module Core
    class GraphDefinition
      attr_reader :name, :start_node, :state_schema

      def initialize(name:, start_node:, nodes:, edges:, state_schema: nil)
        @name = name.to_s
        @start_node = start_node.to_s
        @nodes = stringify_keys(nodes).freeze
        @edges = stringify_keys(edges).freeze
        @state_schema = state_schema
      end

      def node_for(name)
        @nodes[name.to_s]
      end

      def next_node_for(name, state)
        edge = @edges[name.to_s]
        raise "missing edge for node: #{name}" unless edge

        edge.next_node(state)
      end

      private

      def stringify_keys(hash)
        hash.to_h.transform_keys(&:to_s)
      end
    end
  end
end
