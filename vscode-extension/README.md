# FlutterASTest for VS Code

Generate and run Flutter widget tests from inside VS Code. The extension calls the FlutterASTest CLI, so both behave the same.

## Setup

1. Install the CLI from a clone of the repository: `dart pub global activate --source path <clone>`
2. Package and install the extension (needs Node.js):

   ```bash
   cd vscode-extension
   npx @vscode/vsce package
   code --install-extension flutterastest-1.0.0.vsix
   ```

## Commands

| Command | What it does |
|---|---|
| Generate Tests for All Screens | Analyses the project, generates tests and runs them |
| Generate Tests for Screens in This File | The same, for the widget classes in the open file (also in the editor's context menu) |
| Build Prompts Only | Analysis and prompts, with no LLM calls and no key needed |
| Open Latest Report | Opens the latest run's report in the browser |
| Set API Key | Replaces the saved key |

Passing tests go to `test/flutterastest/` and reports to `.flutterastest/`. Your project's Flutter is detected automatically, and the extension never installs or upgrades Flutter. The API key is kept in VS Code's secret storage.

The generated code and your screen source are sent to the LLM provider you configure.
