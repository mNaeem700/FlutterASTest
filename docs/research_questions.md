# Research Questions: Reconciled Version

Status: proposed, awaiting the principal investigator's approval (Sprint S2).

The four research questions of the research design stay unchanged, because they are locked. Document 16 words its questions differently. Its evaluations are kept as sub-questions under the research-design question they serve, so no planned evaluation is lost.

## Mapping

| Research design | Sub-question | Comes from | Experiment | Metrics | Tool support |
|---|---|---|---|---|---|
| **RQ1** How can AST-based program analysis be integrated with LLMs to generate widget tests? | RQ1.1 How accurately is structural knowledge extracted? | Doc 16 RQ1 | Manual ground truth on a benchmark sample | Precision, recall, F1 for screens, navigation, interactions; PKG validation | `accuracy` command, `GraphValidator` |
| | RQ1.2 Which pipeline components contribute to the results? | Doc 16.11 A1, A2, A4 | Ablations | Same metrics as RQ2, compared with the full pipeline | `--ablation` |
| **RQ2** Does AST-guided context improve test quality compared with raw source or textual prompts? | RQ2.1 PKG context against source-based prompts | Doc 16 RQ2 | Groups A, B, C and Baseline 4 | Compilation, pass rate, line, branch and structural coverage, prompt size, tokens | `--mode`, `compare` |
| **RQ3** How far does FlutterASTest improve correctness, execution success, coverage, maintainability and developer effort? | RQ3.1 Effectiveness of the full approach | Research design | Group C on the benchmark | Pass rate, compilation, coverage, test smells, assertions per test | `results.json` |
| | RQ3.2 Does iterative reflection improve the tests? | Doc 16 RQ3, A3, A5 | Group C against D; A5 | Per-iteration failure reduction, coverage gain, assertions, stopping reasons | `--reflect`, `attempts` data |
| | RQ3.3 How much effort is saved? | Research design | Measured without human subjects, which the scope excludes | Repairs per screen, tokens, generation and execution time | `results.csv`, `performance.json` |
| **RQ4** How does FlutterASTest compare with existing approaches in quality and practical usability? | RQ4.1 Comparison with existing approaches | Doc 16.8 Baselines 1, 5 | Apps' existing human-written tests; a published tool if one applies to Flutter | Pass rate, coverage, test smells | Requires benchmark work (S12) |
| | RQ4.2 Does it scale to large repositories? | Doc 16 RQ4 | Small, medium and large apps | Time per stage, peak memory, throughput | `performance.json` |

## Hypotheses (Doc 16.4)

- H1: PKG-based prompting improves test generation compared with baseline prompting (RQ2).
- H2: Reflection improves generated test quality (RQ3.2).
- H3: FlutterASTest outperforms existing approaches (RQ4.1).

Each has its null hypothesis as stated in Doc 16.4, tested at α = 0.05 with effect sizes.

## Open points for the principal investigator

1. **Test correctness.** A passing test can assert very little, so pass rate alone is weak evidence of correctness. Mutation score is the standard stronger measure. Doc 16.5 marks it optional and the tool does not compute it. Reviewers at the target venues are likely to ask about this, so we recommend adding it, or at least stating the limitation under threats to validity.
2. **Practical usability (RQ4).** With human studies out of scope, usability is measured only through proxies such as effort and scalability. The paper must state this limit.
3. **Baseline 1.** Doc 16.8 says "Manual Test Development". Because human studies are excluded, this is interpreted as the tests already in the benchmark apps' repositories.
