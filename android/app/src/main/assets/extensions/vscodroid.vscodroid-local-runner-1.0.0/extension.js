'use strict';

const fs = require('fs');
const path = require('path');
const vscode = require('vscode');

const RUN_COMMAND = 'vscodroid.localRunner.run';
const CANCEL_COMMAND = 'vscodroid.localRunner.cancel';
const MESSAGES = {
    en: {
        ready: 'Local Runner',
        running: 'Local Runner: running',
        select: 'Select a task, project script, or command to run',
        command: 'Run a command in the workspace',
        commandPrompt: 'Command',
        commandPlaceholder: 'npm test',
        noWorkspace: 'Open a workspace before using the local runner.',
        noInput: 'Enter a command to run.',
        finished: 'Local task finished successfully.',
        failed: 'Local task failed with exit code {0}.',
        cancelled: 'No local task is running.',
        cancelledMessage: 'Local task cancelled.',
        commandError: 'Could not start the local task: {0}',
    },
    pt: {
        ready: 'Runner local',
        running: 'Runner local: executando',
        select: 'Selecione uma tarefa, script ou comando para executar',
        command: 'Executar um comando no workspace',
        commandPrompt: 'Comando',
        commandPlaceholder: 'npm test',
        noWorkspace: 'Abra um workspace antes de usar o runner local.',
        noInput: 'Digite um comando para executar.',
        finished: 'Tarefa local concluída com sucesso.',
        failed: 'A tarefa local falhou com código de saída {0}.',
        cancelled: 'Nenhuma tarefa local está em execução.',
        cancelledMessage: 'Tarefa local cancelada.',
        commandError: 'Não foi possível iniciar a tarefa local: {0}',
    },
};

let activeExecution;
let activeLabel = '';
let statusItem;

function message(key) {
    const language = String(vscode.env && vscode.env.language || 'en').toLowerCase();
    const bundle = language === 'pt' || language === 'pt-br' ? MESSAGES.pt : MESSAGES.en;
    return bundle[key];
}

function shellQuote(value) {
    return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function workspaceFolders() {
    return vscode.workspace.workspaceFolders || [];
}

async function chooseWorkspace() {
    const folders = workspaceFolders();
    if (folders.length === 0) {
        await vscode.window.showErrorMessage(message('noWorkspace'));
        return null;
    }
    if (folders.length === 1) return folders[0];
    const picked = await vscode.window.showQuickPick(
        folders.map((folder) => ({
            label: folder.name,
            description: folder.uri.fsPath,
            folder,
        })),
        { placeHolder: message('select') }
    );
    return picked ? picked.folder : null;
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return null;
    }
}

function packageScripts(root) {
    const data = readJson(path.join(root, 'package.json'));
    if (!data || !data.scripts || typeof data.scripts !== 'object') return [];
    return Object.keys(data.scripts).sort().map((name) => ({
        kind: 'script',
        label: `npm: ${name}`,
        description: 'package.json',
        command: `npm run ${shellQuote(name)}`,
    }));
}

function makeTargets(root) {
    const file = path.join(root, 'Makefile');
    let text;
    try {
        text = fs.readFileSync(file, 'utf8');
    } catch (_) {
        return [];
    }
    const names = new Set();
    for (const line of text.split(/\r?\n/)) {
        const match = line.match(/^([A-Za-z0-9][A-Za-z0-9_.-]*):(?!=)/);
        if (match) names.add(match[1]);
    }
    return [...names].sort().map((name) => ({
        kind: 'make',
        label: `make: ${name}`,
        description: 'Makefile',
        command: `make ${shellQuote(name)}`,
    }));
}

async function taskItems() {
    let tasks = [];
    try {
        tasks = await vscode.tasks.fetchTasks();
    } catch (_) {
        tasks = [];
    }
    return tasks.map((task) => ({
        kind: 'task',
        label: task.name || task.definition && task.definition.task || 'Task',
        description: task.source || 'VS Code task',
        task,
    }));
}

function updateStatus() {
    if (!statusItem) return;
    if (activeExecution) {
        statusItem.text = `$(sync~spin) ${message('running')}`;
        statusItem.tooltip = activeLabel;
        statusItem.command = CANCEL_COMMAND;
    } else {
        statusItem.text = `$(play) ${message('ready')}`;
        statusItem.tooltip = message('select');
        statusItem.command = RUN_COMMAND;
    }
}

async function start(item, root) {
    if (activeExecution) {
        await vscode.window.showWarningMessage(message('running'));
        return;
    }
    let execution;
    if (item.task) {
        execution = await vscode.tasks.executeTask(item.task);
    } else {
        const task = new vscode.Task(
            { type: 'shell', task: 'vscodroid.localRunner' },
            vscode.TaskScope.Workspace,
            item.label,
            'VSCodroid Local Runner',
            new vscode.ShellExecution(
                process.env.SHELL || 'bash',
                ['-c', item.command],
                { cwd: root }
            )
        );
        execution = await vscode.tasks.executeTask(task);
    }
    activeExecution = execution;
    activeLabel = item.label;
    updateStatus();
}

async function chooseAndRun() {
    if (activeExecution) {
        await vscode.window.showWarningMessage(message('running'));
        return;
    }
    const folder = await chooseWorkspace();
    if (!folder) return;
    const root = folder.uri.fsPath;
    const items = [
        ...(await taskItems()),
        ...packageScripts(root),
        ...makeTargets(root),
        {
            kind: 'custom',
            label: message('command'),
            description: 'Shell command',
        },
    ];
    const picked = await vscode.window.showQuickPick(items, {
        placeHolder: message('select'),
        matchOnDescription: true,
        matchOnDetail: true,
    });
    if (!picked) return;
    if (picked.kind === 'custom') {
        const command = await vscode.window.showInputBox({
            prompt: message('commandPrompt'),
            placeHolder: message('commandPlaceholder'),
            validateInput: (value) => value && value.trim() ? undefined : message('noInput'),
        });
        if (!command) return;
        picked.command = command.trim();
    }
    try {
        await start(picked, root);
    } catch (error) {
        await vscode.window.showErrorMessage(message('commandError').replace('{0}', String(error)));
    }
}

async function cancel() {
    if (!activeExecution) {
        await vscode.window.showInformationMessage(message('cancelled'));
        return;
    }
    await activeExecution.terminate();
    await vscode.window.showInformationMessage(message('cancelledMessage'));
}

function activate(context) {
    statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusItem.name = 'VSCodroid Local Runner';
    context.subscriptions.push(statusItem);
    context.subscriptions.push(vscode.commands.registerCommand(RUN_COMMAND, chooseAndRun));
    context.subscriptions.push(vscode.commands.registerCommand(CANCEL_COMMAND, cancel));
    context.subscriptions.push(vscode.tasks.onDidEndTaskProcess((event) => {
        if (event.execution !== activeExecution) return;
        const exitCode = event.exitCode;
        activeExecution = undefined;
        activeLabel = '';
        updateStatus();
        vscode.window.showInformationMessage(
            exitCode === 0 ? message('finished') : message('failed').replace('{0}', String(exitCode))
        );
    }));
    context.subscriptions.push(vscode.tasks.onDidStartTaskProcess((event) => {
        if (event.execution === activeExecution) updateStatus();
    }));
    updateStatus();
}

function deactivate() {
    if (activeExecution) activeExecution.terminate();
    activeExecution = undefined;
    activeLabel = '';
    statusItem = undefined;
}

module.exports = { activate, deactivate, packageScripts, makeTargets, shellQuote };
