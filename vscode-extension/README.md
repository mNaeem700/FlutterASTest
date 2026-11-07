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
| Choose LLM Provider | Switch between a local model and a cloud provider (also from the status bar) |
| Check Setup | Runs `flutterastest doctor` in a terminal |

Results of the latest run appear in the Testing panel. Passing tests go to `test/flutterastest/` and reports to `.flutterastest/`. Your project's Flutter is detected automatically, and the extension never installs or upgrades Flutter.

## Privacy

By default the extension uses a local model, so your code stays on your machine. Set the model in `flutterastest.model`. A cloud provider is used only if you choose one, and the extension asks first. Your API key stays in VS Code's secret storage. See the [privacy policy](../PRIVACY.md).
