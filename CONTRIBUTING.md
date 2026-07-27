# Contributing to Nyoy

Keep changes focused, covered by relevant tests, and explicit about graph, prompt, or external
service effects.

## Before you start

Read [AGENTS.md](AGENTS.md) for graph boundaries, LLM configuration, and local conventions.
Use an issue or discussion before changing persistent graph state, public MCP contracts,
authentication, tool policy, or service-connection behavior.

For local development:

```bash
bundle install
npm ci
bin/rails credentials:edit
bin/rails db:prepare
bin/dev
```

Never commit credentials, API tokens, model-server administration tokens, production URLs, or
user-provided chat and media data.

## Validation

Run focused checks while developing, then run the full suite before opening a pull request when
practical.

```bash
bin/rails test test/path/to/test.rb
bundle exec rake -C packages/agent_graph-core test
bin/rubocop
npm audit --audit-level=high
bin/ci
```

Graph changes need state-transition, retry, and resume coverage. Prompt or tool-policy changes
also need schema, parser, fallback, and prompt-cache effects reviewed. Run external-service
checks through the applicable runbook rather than against production services.

## Pull requests

Describe user-visible behavior, validation run, graph or API contract changes, and follow-up
work. Update documentation when changing public MCP tools, environment contracts, model
assignments, or operational procedures. Do not include generated media, credentials, private
environment details, or unrelated formatting changes.

## Security reports

Do not open public issues for suspected vulnerabilities. Follow [SECURITY.md](SECURITY.md)
instead.
