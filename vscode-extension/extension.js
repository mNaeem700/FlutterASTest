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

// Asks before code first goes to a cloud provider, and remembers the answer.
async function cloudConsent(context, provider) {
  const name = `flutterastest.cloudConsent.${provider}`;
  if (context.globalState.get(name)) return true;
  const choice = await vscode.window.showWarningMessage(
    `The "${provider}" provider sends parts of your source code to a cloud service, under that service's terms. ` +
      'A local model keeps your code on this machine.',
    { modal: true },
    'Send to Cloud',
    'Choose Provider',
  );
  if (choice === 'Choose Provider') await selectProvider();
  if (choice !== 'Send to Cloud') return false;
  await context.globalState.update(name, true);
  return true;
}

async function selectProvider() {
  const items = [
    { label: 'local', description: 'Your code stays on this machine (needs Ollama or similar)' },
    { label: 'gemini', description: 'Google Gemini with your own key; code is sent to Google' },
    { label: 'openai', description: 'OpenAI-compatible service with your own key; code is sent to it' },
  ];
  const picked = await vscode.window.showQuickPick(items, { title: 'FlutterASTest LLM provider' });
  if (!picked) return;
  await vscode.workspace
    .getConfiguration('flutterastest')
    .update('provider', picked.label, vscode.ConfigurationTarget.Global);
  updateStatus();
}

function latestResults(project) {
  const report = project && latestReport(project);
  if (!report) return undefined;
  try {
    return JSON.parse(fs.readFileSync(path.join(path.dirname(report), 'results.json'), 'utf8'));
  } catch {
    return undefined;
  }
}

// Screens of the latest run, in the Testing panel.
class ResultsView {
  constructor() {
    this.changed = new vscode.EventEmitter();
    this.onDidChangeTreeData = this.changed.event;
  }

  refresh() {
    this.changed.fire();
  }

  getTreeItem(item) {
    return item;
  }

  getChildren() {
    const results = latestResults(projectFolder());
    if (!results) return [];
    return results.screens.map((screen) => {
      const run = screen.final;
      const passed = run && run.compiled && run.failed === 0 && run.passed > 0;
      const coverage = run?.screenCoverage?.percent;
      const item = new vscode.TreeItem(screen.screen);
      item.description = run
        ? `${run.passed} passed, ${run.failed} failed${coverage === undefined ? '' : `, ${coverage}% lines`}`
        : 'not run';
      item.iconPath = new vscode.ThemeIcon(passed ? 'pass' : 'error');
      item.tooltip = screen.screenFile;
      const project = projectFolder();
      if (project) {
        item.command = {
          command: 'vscode.open',
          title: 'Open Screen',
          arguments: [vscode.Uri.file(path.join(project, screen.screenFile))],
        };
      }
      return item;
    });
  }
}

let status;
let results;

function updateStatus() {
  status.text = `$(beaker) FlutterASTest: ${setting('provider')}`;
  status.tooltip =
    setting('provider') === 'local' ? 'Your code stays on this machine' : 'Code is sent to a cloud provider';
  status.show();
}

function runDoctor() {
  const project = projectFolder();
  const terminal = vscode.window.createTerminal('FlutterASTest');
  terminal.show();
  terminal.sendText(`${quote(setting('executable'))} doctor${project ? ` ${quote(project)}` : ''}`);
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
  const model = setting('model');
  if (model) args.push('--model', model);
  if (provider === 'local' && !model && !promptsOnly) {
    const choice = await vscode.window.showErrorMessage(
      'Choose a local model first (see "ollama list"), or choose another provider.',
      'Open Settings',
      'Choose Provider',
    );
    if (choice === 'Open Settings') {
      await vscode.commands.executeCommand('workbench.action.openSettings', 'flutterastest.model');
    } else if (choice === 'Choose Provider') {
      await selectProvider();
    }
    return;
  }
  for (const screen of screens) args.push('--screen', screen);
  if (promptsOnly) args.push('--prompts-only');
  else if (setting('reflect')) args.push('--reflect');
  const flutterPath = setting('flutterPath');
  if (flutterPath) args.push('--flutter', flutterPath);

  const env = { ...process.env };
  if (!promptsOnly && provider !== 'local') {
    if (!(await cloudConsent(context, provider))) return;
    const key = await apiKey(context, provider);
    if (!key) return;
    env[KEY_VARIABLES[provider]] = key;
    args.push('--accept-cloud');
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
          results.refresh();
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
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left);
  status.command = 'flutterastest.selectProvider';
  results = new ResultsView();
  updateStatus();
  context.subscriptions.push(
    output,
    status,
    vscode.window.registerTreeDataProvider('flutterastest.results', results),
    vscode.commands.registerCommand('flutterastest.selectProvider', selectProvider),
    vscode.commands.registerCommand('flutterastest.doctor', runDoctor),
    vscode.commands.registerCommand('flutterastest.refreshResults', () => results.refresh()),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('flutterastest.provider')) updateStatus();
    }),
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
