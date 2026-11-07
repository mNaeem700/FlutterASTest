# Differences Between the Implementation and the Phase 2 Specification

Status: open, Sprint S7. These must be resolved or reported in the paper before the tool is frozen in S8.

**Audit coverage.** Read in full: Docs 1, 2, 3, 8, and Doc 7 from section 7.7 on. Read for requirements: Doc 4 (execution trace), Doc 6 (report and test structure), Doc 9 (identity, serialization, traversal), Doc 10 (scoring, DTO, pruning), Doc 11 (modes, DTO, budget, validation), Doc 12 (configuration, retry), Doc 13 (validation), Doc 14 (outputs, flaky review), Doc 15 (components, algorithm, stopping rules), Doc 16, Doc 17 (configuration). Other sections of Docs 4 to 6 and 12 to 15, mostly rationale, risk matrices and traceability tables, were listed by heading only.

## Waiting for a decision: LLM settings (Doc 12)

All of these can now be set (`--temperature`, `--top-p`, `--seed`, `--max-output-tokens`, `--request-timeout`, or the YAML file). Nothing is sent unless it is set, so the Gemini calls stay as they were until the values are chosen for the experiments.

| Setting | Specification | Implementation | Why it matters |
|---|---|---|---|
| Provider, model | OpenAI, gpt-4.1 (Doc 12.19), gpt-5.5 in the Doc 17 example | `local` by default for developers; research runs name `--provider gemini` (`gemini-3.6-flash`) or `openai` | The paper must report the model used |
| Temperature | 0.20 | Provider default unless set | Independent variable in Doc 16.5; output varies more between runs |
| Top P, seed | 1.0, fixed where supported | Unset unless given | Doc 16.12 names a fixed seed as a mitigation |
| Max output tokens | 4096 | Unset unless given | Affects truncated replies |
| Retry | 3 attempts, delays 2, 4, 8 s | Gemini: 4 attempts, fixed 30 s, for the free-tier limit. OpenAI-compatible: as specified | Longer runs, no effect on results |
| Request timeout | 120 s | 10 minutes unless set | Long enough for slow models; a hung call cannot block a batch |

## Design decisions to report in the paper

| Area | Specification | Implementation | Reason |
|---|---|---|---|
| Relevance score parts | W, N, S are named but not defined (Doc 10.14) | W: interactive 1, labelled 0.6, other widget 0.2. N: navigating 1, widget that navigates 0.75. S: state field or member 1, dependency or lifecycle 0.75 | The specification leaves them open |
| Traversal depth 5 | Depth of graph traversal (Doc 9.24.1) | Containment edges do not consume depth | Widget trees are deeper than 5 and the UI hierarchy is mandatory (Doc 10.19.1) |
| Destination screens | Not specified | Linked but not expanded | Another screen's tree is not context for this screen |
| Pruning | Four stages (Doc 10.19.1) | Stage 1 only, compression applied separately | Stage 1 already considers every non-mandatory entity |
| Node id | `Package::File::Entity::Offset` | Tree entities add their tree path to the entity name | One helper inlined twice has one source offset |
| Default output | Not specified | Developer runs write into the project; research runs use `--output` | Product requirement of the principal investigator |
| Failing tests | Not specified | Only fully passing files are installed in the project | A generation must not turn the project's suite red |
| Network isolation | Open review item (Doc 14) | `flutter_test`'s default HTTP behaviour, no OS-level block | Stated as a threat to validity |
| Confidence score | Doc 15.17.4, undefined | Share of the run's failures the primary cause accounts for, measured rather than predicted | The specification gives no formula |
| CPU usage | Doc 14.18.5, Doc 16.9 | CPU of the tool's own process; `flutter test` children appear as execution time | Per-child CPU is not portable |
| Flaky tests | Open review item (Doc 14) | Up to 2 reruns of failing files; flaky tests stay failed | Does not inflate results |

## Not implemented

| Item | Specification | Status |
|---|---|---|
| Expected gains | Doc 15.17.5 | Omitted: predicting improvement would need a calibrated model, and invented numbers would not be evidence |
| Line-level HTML coverage | Doc 14.18.4 | `report.html` gives a per-screen summary; lcov files are saved for each attempt, and `genhtml` can render them where it is installed |
| Token budget allocation 20/20/50/10 | Doc 11 review item | The budget applies to the context section only; the template has a fixed size |
| Literal DTO names and fields | Docs 10 to 15 (PromptPackage, ExecutionResult, ...) | Equivalent data under simpler classes; checksums and UUID fields omitted |
| Plugin registry, parallel analysis | Docs 6, 8, 12 to 14 | Extension is by interfaces (`LlmService`, `PipelineModule`) without a registry; runs are sequential, the specified research default |
| Publication-styled figures | Docs 2, 3, 6 | `report.pdf` is text only; `compare` writes simple SVG bar charts with confidence intervals |
| Folder layout `reports/`, `artifacts/`, `test/unit/` | Doc 6 | One folder per run under `runs/`, with the same content |
| Vertex types Application, Input, Output; edge RETURNS | Doc 3 | Mapped instead: Method as interaction or member, State as stateField, Service as dependency, Validation as validation; return types are in member signatures |
| Widget type enum: Material, Cupertino, Inherited | Doc 8.14.10 | Stateless and stateful only; other widgets appear by name in the tree |
| Estimated API cost, per-DTO hashes in the trace | Doc 4.10.2 | Token counts and artifacts are kept; cost needs provider prices |
| Partial-result counters for analysis | Doc 8.17 | A failing screen is skipped with a warning in `run.log`; no separate counters |
| GraphML is present; NetworkX and Neo4j exports | Doc 9.17.1 (optional) | Not built |
| Docker image | Doc 16.15 | `Dockerfile` written but not built yet, because Docker is not installed on the development machine |
