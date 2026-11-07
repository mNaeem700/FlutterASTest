# FlutterASTest: AI Flutter Test Generator

**Generate and run Flutter widget tests and unit tests with AI, right inside VS Code.** Choose one screen, one class or your whole app. FlutterASTest reads your Dart code's structure, writes tests, runs them in your project and shows you what worked, what failed and why.

By default it uses a **local AI model, so your code stays on your machine**. You can also use Gemini or an OpenAI-compatible service with your own API key.

> **Pre-release.** This is an early version. Test quality depends on the AI model and your app, and you may meet bugs. Please report them on [GitHub Issues](https://github.com/mNaeem700/FlutterASTest/issues).

## How it works

1. **Reads your code.** AST analysis finds screens, widgets, navigation, form validators, state and dependencies.
2. **Writes tests.** The AI writes tests from that information, instead of guessing from raw text.
3. **Runs them.** Tests run with your project's own Flutter version, with line and branch coverage.
4. **Repairs failures.** Errors go back to the AI, up to 5 times.
5. **Keeps your suite green.** Passing tests go to `test/flutterastest/`. Failing tests are added only if you choose to, and your own test files are never overwritten.

## Getting started

1. **Install the Flutter SDK**, and run `flutter pub get` in your project.
2. **Install the command-line tool** once:

   ```bash
   dart pub global activate --source git https://github.com/mNaeem700/FlutterASTest
   ```

3. **Choose your AI.** Click **FlutterASTest** in the status bar:
   - **Local:** install [Ollama](https://ollama.com), download a code model, and set its name in the `flutterastest.model` setting.
   - **Gemini or OpenAI-compatible:** the extension asks for your API key and keeps it in VS Code's secret storage.
4. **Run `FlutterASTest: Check Setup`** from the Command Palette. It shows what is ready and how to fix what is not.
5. **Generate.** Run `FlutterASTest: Generate Widget Tests for Chosen Screens...`, or right-click a Dart file.

## Commands

| What you want | Command |
|---|---|
| Widget tests for one or more screens | Generate Widget Tests for Chosen Screens... |
| Widget tests for the open file | Generate Widget Tests for This File (also in the right-click menu) |
| Widget tests for every screen | Generate Widget Tests for All Screens |
| Unit tests for one or more classes | Generate Unit Tests for Chosen Classes... |
| Unit tests for the open file | Generate Unit Tests for This File (also in the right-click menu) |
| Unit tests for every class and function | Generate Unit Tests for All Classes |
| See the prompts, with no AI calls | Build Prompts Only |
| Check your setup | Check Setup |
| Read the latest report | Open Latest Report |
| Change the AI or the key | Choose AI Provider, Set API Key |

## Seeing what happened

- **Output panel:** progress, and the reason for each failure.
- **Testing panel, FlutterASTest section:** one line per screen or class. Click it to open the test. On a failed test, **Add Test to Project** keeps it so you can fix it yourself.
- **Report:** a summary page in your browser.

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
- Screens tied to Firebase, network or heavy services are harder to test, and some may fail.
- Generated tests run your app's code on your machine, so use this on projects you trust.

## Support

Report bugs and ideas on [GitHub Issues](https://github.com/mNaeem700/FlutterASTest/issues), or email neemiidev@gmail.com.

MIT License.
