# Differences Between the Implementation and the Phase 2 Specification

Status: open, Sprint S7. These must be resolved or reported in the paper before the tool is frozen in S8.

**Audit coverage so far.** Checked against the code: Doc 9 (identity, serialization, traversal), Doc 10 (scoring, DTO, pruning), Doc 11 (modes, DTO, budget, validation), Doc 12 (configuration, retry), Doc 13 (validation), parts of Doc 14 and Doc 15 (outputs, stopping rules), Doc 16, and Doc 17 (configuration). Docs 1 to 8 and the remaining sections have not been compared line by line.

## Waiting for a decision: LLM settings (Doc 12)

The principal investigator asked to leave the Gemini integration unchanged for now.

| Setting | Specification | Implementation | Why it matters |
|---|---|---|---|
| Provider, model | OpenAI, gpt-4.1 (Doc 12.19), gpt-5.5 in the Doc 17 example | Gemini, `gemini-3.6-flash` | The paper must report the model used |
| Temperature | 0.20 | Provider default, not set | Independent variable in Doc 16.5; output varies more between runs |
| Top P, seed | 1.0, fixed where supported | Not set | Doc 16.12 names a fixed seed as a mitigation |
| Max output tokens | 4096 | Not set | Affects truncated replies |
| Retry | 3 attempts, delays 2, 4, 8 s | 4 attempts, fixed 30 s, for the free-tier limit | Longer runs, no effect on results |
| Request timeout | 120 s | None | A hung call could block a batch |

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
| Flaky tests | Open review item (Doc 14) | Up to 2 reruns of failing files; flaky tests stay failed | Does not inflate results |

## Not implemented

| Item | Specification | Status |
|---|---|---|
| CPU usage metric | Doc 14.18.5, Doc 16.9 | Dart has no portable per-process measure; time and peak memory are recorded |
| Confidence scores, expected gains | Doc 15.17 | Omitted: the rule-based diagnosis has no measured probability, and invented numbers would not be evidence |
| Line-level HTML coverage | Doc 14.18.4 | `report.html` gives a per-screen summary; per-line needs `genhtml`, which is not available on Windows |
| Token budget allocation 20/20/50/10 | Doc 11 review item | The budget applies to the context section only; the template has a fixed size |
| Literal DTO names and fields | Docs 10 to 15 (PromptPackage, ExecutionResult, ...) | Equivalent data under simpler classes; checksums and UUID fields omitted |
| Plugin architecture, parallel modes | Docs 12 to 14 | Not built; runs are sequential, which is the specified research default |
| GraphML is present; NetworkX and Neo4j exports | Doc 9.17.1 (optional) | Not built |
| Bloc event handlers | Not specified | `bloc.add(Event())` is recorded, but the `on<Event>` handler is not followed, so its state changes are not attributed |
| Mutation score | Doc 16.5 (optional) | Not built; see `research_questions.md` |
| Docker image | Doc 16.15 | Scheduled for S13 |
