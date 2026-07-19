# AgentGraph Core

Pure Ruby state-machine runtime extracted from Nyoy.

This package is currently a private, vendored path gem. It contains the graph definition, transition result, state schema, execution runner, and runtime context protocol. Rails persistence and application workflows remain in Nyoy.

## Development

```bash
bundle exec rake test
gem build agent_graph-core.gemspec
```
