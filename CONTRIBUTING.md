# Contributing

```bash
dart pub get
dart analyze lib bin test
dart test
```

Both checks must pass before a pull request is merged, and they run automatically in CI. New behaviour needs a unit test; fixtures in `test/support/` show how to test analyzers without a real project.

A new LLM provider needs a class implementing `LlmService` and a case in `lib/llm/llm_factory.dart`. A new pipeline stage implements `PipelineModule` and is registered in `lib/orchestrator/pipeline_orchestrator.dart`.

Differences from the design documents are recorded in `doc/spec_deviations.md`.
