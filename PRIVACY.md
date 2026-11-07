# Privacy Policy

> **Draft.** Have a qualified lawyer review this before a public release, and fill in the contact details below. It describes what the software does today.

**Effective date:** to be set at release
**Contact:** to be added at release

## Summary

FlutterASTest runs on your own computer. It has no account system, no analytics and no telemetry, and it does not send anything to the FlutterASTest authors.

## What stays on your computer

- Analysis of your source code, the knowledge graph, prompts, generated tests and reports.
- Test runs, through your own Flutter installation.
- Settings and any API keys you save, in `~/.flutterastest/config.json`. The VS Code extension keeps keys in VS Code's secret storage.

## When code leaves your computer

Only when you choose a cloud provider. With the default `local` provider, requests go only to a model server on your own machine.

With a cloud provider (`gemini` or `openai`), FlutterASTest sends to that provider, using your own API key:

| Context mode | What is sent |
|---|---|
| `pkg` (default) | A summary of the screen: widget tree, texts, method signatures, routes, validators |
| `baseline` | The screen's full source file |
| `file` | The screen's file and the project files it imports |
| `repository` | Every Dart file under `lib/` |
| with `--reflect` | Also the generated tests and their error output |

FlutterASTest asks for your agreement before the first use of each cloud provider. The provider handles this data under its own terms and privacy policy, which you accepted with them. Free tiers may allow the provider to use your data to improve its products, so check these terms before sending private or client code.

## Your control

- Use `--provider local` to keep code on your machine, and `--prompts-only` to send nothing at all.
- Remove saved keys with `flutterastest config remove-key <provider>`.
- Delete `~/.flutterastest/` and your project's `.flutterastest/` folder to remove all local data.

## Changes

Changes to this policy will be published in this file with the project's releases.
