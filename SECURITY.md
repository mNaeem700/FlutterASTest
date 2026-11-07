# Security Policy

## Reporting a vulnerability

Please do not open a public issue. Email neemiidev@gmail.com, or use GitHub's private vulnerability reporting under the repository's **Security** tab if it is enabled. Include the steps to reproduce and the affected version.

## API keys

Never commit API keys. Revoke any key that has been exposed, because removing it from the latest code does not remove it from git history.

## What FlutterASTest executes

Generated tests are ordinary Dart code written by a language model, and `flutter test` runs them with your user's permissions. Run the tool only on projects you trust, and review generated tests before committing them.
