# AgentGraph Core

Pure Ruby state-machine runtime extracted from Nyoy.

This package is currently a private, vendored path gem. It contains the graph definition, transition result, state schema, execution runner, and runtime context protocol. Rails persistence and application workflows remain in Nyoy.

It is buildable as a gem, but separate-repository and public release work is intentionally deferred until there is a second consumer or an independent release requirement. The detailed assessment is maintained in Nyoy's `docs/architecture/agent-graph-core-extraction-assessment.md`.

## Development

```bash
bundle exec rake test
gem build agent_graph-core.gemspec
```
