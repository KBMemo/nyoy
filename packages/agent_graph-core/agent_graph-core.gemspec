# frozen_string_literal: true

require_relative "lib/agent_graph/core/version"

Gem::Specification.new do |spec|
  spec.name = "agent_graph-core"
  spec.version = AgentGraph::Core::VERSION
  spec.authors = [ "Nyoy contributors" ]
  spec.summary = "Pure Ruby state-machine runtime for AgentGraph"
  spec.description = "Core graph definitions and execution runtime extracted from Nyoy."
  spec.homepage = "https://github.com/KBMemo/nyoy"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.3"

  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "LICENSE", "README.md"] }
  spec.require_paths = [ "lib" ]

  spec.add_development_dependency "minitest", ">= 5", "< 7"
  spec.add_development_dependency "rake", ">= 13", "< 14"
end
