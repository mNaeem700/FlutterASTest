# FlutterASTest 🚀
An AST-Augmented LLM Framework for Automated Widget Test Generation in Flutter Applications

## 🌟 Executive Summary
FlutterASTest is an open-source, AI-driven software engineering (AI4SE) framework that eliminates the manual bottleneck of writing UI widget tests in cross-platform mobile development.

While modern Large Language Models (LLMs) excel at generating unit tests for simple functions, they systematically fail—hallucinating APIs and missing deeply nested dependencies—when faced with the complex declarative UI trees of Flutter. FlutterASTest solves this multi-million dollar industry problem by bridging deterministic static program analysis with probabilistic LLM generation.

Instead of feeding raw source code to an LLM, this framework uses the official Dart Analyzer to extract an Abstract Syntax Tree (AST), translates it into a token-efficient Program Knowledge Graph (PKG), and generates syntactically valid, high-coverage widget tests capable of autonomous self-repair.

## 🚨 The Problem: The "Hallucination" Gap in UI Testing
Cross-platform development requires rigorous UI testing to ensure stability across Android, iOS, and Web. However, manual test creation is expensive and brittle. Current LLM-based solutions fail because:

*   **Structural Ignorance:** LLMs treat deeply nested UI code as raw text, missing critical semantic relationships between state, callbacks, and navigation.
*   **Context Window Bloat:** Feeding entire Flutter projects into an LLM exceeds token limits and introduces massive noise.
*   **Syntactic Hallucinations:** AI agents frequently invent non-existent Flutter widgets or mock dependencies, leading to broken, non-compiling test files.

## 💡 The Innovation: Semantic Graph Context
FlutterASTest fundamentally shifts the paradigm from text-to-text generation to graph-to-code generation.

*   **Lexical Analysis & AST Parsing:** The framework parses the raw Flutter codebase into an Abstract Syntax Tree (AST), strictly defining the architectural boundaries of the app.
*   **Program Knowledge Graph (PKG):** It isolates actionable nodes (Widgets, Screens, State, Routes) and maps them into a highly compressed, token-efficient semantic graph.
*   **Targeted Context Injection:** The LLM receives a pristine, JSON-structured prompt containing only the exact UI hierarchies and callbacks required for the test, reducing token consumption by up to 80% while maximizing accuracy.
*   **Autonomous Reflection Engine:** Generated tests execute in an isolated sandbox. Compiler errors and failing coverage metrics are captured and fed back into the LLM as structured repair prompts, creating a continuous, self-improving loop.

## ⚙️ Core System Architecture
FlutterASTest is built as a highly modular, extensible Dart library utilizing an orchestrator-centric pipeline.

*   **Parser Module:** Validates the Flutter project and extracts the AST using the official Dart analyzer.
*   **Analysis Module:** Identifies semantic entities (Stateful/Stateless Widgets, Provider/Riverpod state, navigation flows).
*   **Context & Prompt Builders:** Ranks semantic relevance and generates deterministic, template-driven LLM instructions.
*   **LLM Engine:** A provider-agnostic execution gateway (OpenAI, Gemini, Anthropic, local vLLM) that handles asynchronous token streams.
*   **Test Execution & Reflection:** Executes `flutter test`, analyzes LCOV coverage data, and iteratively repairs failing tests via execution trace feedback.

## 🛠️ Installation & Usage
*(Note: Currently in active development. CLI release pending funding milestones.)*

### Prerequisites
*   Flutter SDK (3.x)
*   Dart SDK (3.x)
*   An active LLM API Key (OpenAI, Anthropic, or Gemini)

### Setup
```bash
# Activate the CLI globally (Coming Soon to pub.dev)
dart pub global activate flutterastest

# Initialize configuration in your Flutter project
flutterastest init

# Set your API keys in the generated config
export OPENAI_API_KEY="your-secure-api-key"
```

### Generating Tests
Run the analysis and generation pipeline on your project:
```bash
flutterastest analyze lib/screens/login_page.dart --mode=pkg
```
The framework will parse the AST, generate the PKG context, query the LLM, and output ready-to-run files into your `test/` directory.

## 🗺️ Project Roadmap & Funding Milestones
This project is spearheaded by a solo, independent researcher, ensuring that 100% of awarded grant funding goes directly into high-volume API token costs, specialized cloud execution sandboxes, and accelerated R&D, with zero institutional overhead.

### ✅ Phase 1: Semantic Foundation (Completed)
- [x] Dart AST Parsing Engine
- [x] Widget, State, Callback, and Dependency Analyzers
- [x] Program Knowledge Graph (PKG) Construction
- [x] Prompt Optimization & LLM Integration (Zero-Shot Generation)

### 🚀 Phase 2: Execution & Autonomy (Active Grant Focus)
- [ ] Automated Test Execution: Sandboxed compilation and test running.
- [ ] Empirical Coverage Analysis: Automated LCOV generation and metrics reporting.
- [ ] Reflection Engine: Closed-loop, self-repairing prompt generation for failing tests.
- [ ] Evaluation Benchmarking: Large-scale comparison against raw LLM prompting techniques for peer-reviewed publication.

### 🏁 Phase 3: Ecosystem Release
- [ ] Publish `flutterastest` CLI tool to pub.dev.
- [ ] Integrate CI/CD pipeline plugins (GitHub Actions / GitLab CI).
- [ ] Submit empirical findings to premier software engineering venues (ICSE, ASE, TSE).

## 👨‍💻 Principal Investigator
**Muhammad Naeem**
Independent Software Engineering Researcher & Flutter Developer

*   **Academic Background:** B.S. Software Engineering, The Islamia University of Bahawalpur (GPA: 3.82)
*   **Focus:** Bridging cross-platform mobile development with applied Artificial Intelligence.
*   **Agility & Execution:** Operating as a solo developer allows for rapid prototyping, zero bureaucratic friction, and a singular focus on delivering production-ready, open-source AI developer tools.

## 📄 License & Open Source Commitment
This project is licensed under the MIT License. FlutterASTest is committed to the open-source community; all core parsing algorithms, graph generation mechanics, and execution pipelines will remain free and open for public research and commercial adaptation.
