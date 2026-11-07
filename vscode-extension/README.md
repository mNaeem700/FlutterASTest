# FlutterASTest: AI Widget Test Generator for Flutter

**Generate and run Flutter widget tests with AI, right inside VS Code.** FlutterASTest reads your Dart code's structure (widgets, navigation, state and form validators), writes `flutter_test` widget tests, runs them in your project and reports the results with coverage.

By default it uses a **local AI model, so your code stays on your machine**. You can also use Gemini or an OpenAI-compatible service with your own API key.

> **Pre-release.** This is an early version and you may meet bugs. Please report them on [GitHub Issues](https://github.com/mNaeem700/FlutterASTest/issues).

## Why FlutterASTest

- **Understands your Flutter app.** Tests are based on your app's real widget tree, screens, routes and form validators, found through AST analysis, instead of a model guessing from raw text.
- **Private by default.** With a local model, nothing leaves your computer. A cloud provider is used only if you choose one, and the extension asks first.
- **Runs what it writes.** Tests run with your project's Flutter version, and you get pass/fail results with line and branch coverage.
- **Repairs failing tests.** Errors go back to the model so it can fix the test, up to 5 times.
- **Keeps your test suite green.** Only fully passing tests are added to `test/flutterastest/`, and your own test files are never overwritten.
- **Works with common architectures.** Analysis covers GetX, Provider, Bloc/Cubit, Riverpod, ValueNotifier and MobX, and Navigator, GoRouter and AutoRoute.

## Getting started

FlutterASTest needs its command-line tool, which this extension runs for you.

1. **Install the Flutter SDK**, and run `flutter pub get` in your project.
2. **Install the command-line tool:**

   ```bash
   dart pub global activate --source git https://github.com/mNaeem700/FlutterASTest
   ```

   Make sure Dart's global `bin` folder is on your `PATH`.
3. **Choose your AI model.** Click **FlutterASTest** in the status bar:
   - **Local:** install [Ollama](https://ollama.com), download a code model, and set its name in the `flutterastest.model` setting.
   - **Gemini or OpenAI-compatible:** the extension asks for your API key and keeps it in VS Code's secret storage.
4. **Run `FlutterASTest: Check Setup`** from the Command Palette to confirm that everything is ready.
5. **Generate tests.** Right-click a Dart file and choose **FlutterASTest: Generate Tests for Screens in This File**.

## Commands

| Command | What it does |
|---|---|
| Generate Tests for All Screens | Analyses the project, then writes and runs tests |
| Generate Tests for Screens in This File | The same, for the widget classes in the open file |
| Build Prompts Only (No LLM Calls) | Runs the analysis and builds prompts, with no AI calls and no key |
| Open Latest Report | Opens the latest report in your browser |
| Choose LLM Provider | Switches between a local model and a cloud provider |
| Set API Key | Replaces your saved key |
| Check Setup | Checks Flutter, your project and your AI model |

Results of the latest run appear in the **Testing** panel.

## Settings

| Setting | Default | Description |
|---|---|---|
| `flutterastest.provider` | `local` | `local`, `gemini` or `openai` |
| `flutterastest.model` | empty | Model name; required for `local` |
| `flutterastest.reflect` | `true` | Repair failing tests |
| `flutterastest.flutterPath` | empty | Flutter to use; empty detects it per project, including FVM |
| `flutterastest.executable` | `flutterastest` | The command-line tool |

## Privacy

There are no accounts and no telemetry. With the `local` provider, your code stays on your machine. With a cloud provider, parts of your source code go to that provider under its own terms, using your own key. Read the [Privacy Policy](https://github.com/mNaeem700/FlutterASTest/blob/main/PRIVACY.md) and [Terms of Use](https://github.com/mNaeem700/FlutterASTest/blob/main/TERMS.md).

## Good to know

- Tests are written by an AI model and can be wrong, so review them before relying on them.
- A local model's test quality depends on the model and your hardware.
- Generated tests run your app's code on your machine, so use this on projects you trust.

## Support

Report bugs and ideas on [GitHub Issues](https://github.com/mNaeem700/FlutterASTest/issues), or email neemiidev@gmail.com.

MIT License.
