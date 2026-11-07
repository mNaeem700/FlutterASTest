// Thin wrapper around the FlutterASTest CLI: all analysis and test logic lives
// there, so the extension and the CLI always behave the same.
const vscode = require('vscode');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const KEY_VARIABLES = { gemini: 'GEMINI_API_KEY', openai: 'OPENAI_API_KEY' };
const WIDGET_CLASS =
  /class\s+(\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|GetView|GetWidget|HookWidget|StatefulHookWidget|ConsumerWidget|ConsumerStatefulWidget|HookConsumerWidget)\b/g;

let output;
let running = false;

function setting(name) {
  return vscode.workspace.getConfiguration('flutterastest').get(name);
}

function projectFolder() {
  const activeUri = vscode.window.activeTextEditor?.document.uri;
  const folder =
    (activeUri && vscode.workspace.getWorkspaceFolder(activeUri)) ||
    vscode.workspace.workspaceFolders?.[0];
  if (!folder) return undefined;
  return fs.existsSync(path.join(folder.uri.fsPath, 'pubspec.yaml')) ? folder.uri.fsPath : undefined;
}

// A Windows shell is needed to start the pub `.bat` launcher, so every argument
// is quoted; project paths often contain spaces.
function quote(argument) {
  return `"${String(argument).replace(/"/g, '\\"')}"`;
}

async function apiKey(context, provider) {
  const name = `flutterastest.key.${provider}`;
  const saved = await context.secrets.get(name);
  if (saved) return saved;
  const entered = await vscode.window.showInputBox({
    prompt: `API key for ${provider} (kept in VS Code's secret storage)`,
    password: true,
    ignoreFocusOut: true,
  });
  if (entered) await context.secrets.store(name, entered);
  return entered;
}

function latestReport(project) {
  const runs = path.join(project, '.flutterastest', 'runs');
  if (!fs.existsSync(runs)) return undefined;
  const reports = fs
    .readdirSync(runs)
    .map((run) => path.join(runs, run, 'report.html'))
    .filter((file) => fs.existsSync(file))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return reports[0];
}

async function openReport() {
  const project = projectFolder();
  const report = project && latestReport(project);
  if (!report) {
    vscode.window.showInformationMessage('FlutterASTest: no report yet. Generate tests first.');
    return;
  }
  await vscode.env.openExternal(vscode.Uri.file(report));
}

async function run(context, { screens = [], promptsOnly = false } = {}) {
  if (running) {
    vscode.window.showWarningMessage('FlutterASTest is already running.');
    return;
  }
  const project = projectFolder();
  if (!project) {
    vscode.window.showErrorMessage('FlutterASTest: open a Flutter project (a folder with pubspec.yaml).');
    return;
  }

  const provider = setting('provider');
  const args = ['analyse', project, '--provider', provider];
  for (const screen of screens) args.push('--screen', screen);
  if (promptsOnly) args.push('--prompts-only');
  else if (setting('reflect')) args.push('--reflect');
  const flutterPath = setting('flutterPath');
  if (flutterPath) args.push('--flutter', flutterPath);

  const env = { ...process.env };
  if (!promptsOnly) {
    const key = await apiKey(context, provider);
    if (!key) return;
    env[KEY_VARIABLES[provider]] = key;
  }

  running = true;
  output.clear();
  output.show(true);
  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: 'FlutterASTest', cancellable: true },
    (progress, token) =>
      new Promise((resolve) => {
        progress.report({ message: promptsOnly ? 'building prompts...' : 'generating and running tests...' });
        const child = spawn([quote(setting('executable')), ...args.map(quote)].join(' '), {
          cwd: project,
          env,
          shell: true,
        });
        token.onCancellationRequested(() => child.kill());
        child.stdout.on('data', (data) => output.append(data.toString()));
        child.stderr.on('data', (data) => output.append(data.toString()));
        child.on('error', (error) => {
          output.appendLine(`Could not start FlutterASTest: ${error.message}`);
        });
        child.on('close', async (code) => {
          running = false;
          resolve();
          if (code !== 0) {
            vscode.window.showErrorMessage(
              'FlutterASTest failed. See the output panel. If the command was not found, install it ' +
                'with: dart pub global activate --source path <clone>',
            );
            return;
          }
          const message = promptsOnly
            ? 'Prompts are in .flutterastest/.'
            : 'Done. Passing tests are in test/flutterastest/.';
          const choice = promptsOnly
            ? await vscode.window.showInformationMessage(`FlutterASTest: ${message}`)
            : await vscode.window.showInformationMessage(`FlutterASTest: ${message}`, 'Open Report');
          if (choice === 'Open Report') await openReport();
        });
      }),
  );
}

function screensInActiveFile() {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'dart') return [];
  return [...editor.document.getText().matchAll(WIDGET_CLASS)].map((match) => match[1]);
}

function activate(context) {
  output = vscode.window.createOutputChannel('FlutterASTest');
  context.subscriptions.push(
    output,
    vscode.commands.registerCommand('flutterastest.generateProject', () => run(context)),
    vscode.commands.registerCommand('flutterastest.generateFile', () => {
      const screens = screensInActiveFile();
      if (screens.length === 0) {
        vscode.window.showInformationMessage('FlutterASTest: no widget classes in this file.');
        return undefined;
      }
      return run(context, { screens });
    }),
    vscode.commands.registerCommand('flutterastest.preview', () => run(context, { promptsOnly: true })),
    vscode.commands.registerCommand('flutterastest.openReport', openReport),
    vscode.commands.registerCommand('flutterastest.setApiKey', async () => {
      const provider = setting('provider');
      await context.secrets.delete(`flutterastest.key.${provider}`);
      await apiKey(context, provider);
    }),
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
