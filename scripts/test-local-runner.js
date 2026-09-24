'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const Module = require('module');

const extensionPath = path.join(
    __dirname,
    '../android/app/src/main/assets/extensions/vscodroid.vscodroid-local-runner-1.0.0/extension.js'
);
const registered = new Map();
const errors = [];
const information = [];
const status = { command: null, text: '', tooltip: '' };
const vscode = {
    env: { language: 'en' },
    StatusBarAlignment: { Left: 1 },
    TaskScope: { Workspace: 1 },
    workspace: { workspaceFolders: [] },
    window: {
        createStatusBarItem() {
            return status;
        },
        showErrorMessage(message) {
            errors.push(message);
            return Promise.resolve();
        },
        showWarningMessage(message) {
            errors.push(message);
            return Promise.resolve();
        },
        showInformationMessage(message) {
            information.push(message);
            return Promise.resolve();
        },
        showQuickPick() {
            return Promise.resolve(undefined);
        },
        showInputBox() {
            return Promise.resolve(undefined);
        },
    },
    commands: {
        registerCommand(name, callback) {
            registered.set(name, callback);
            return { dispose() {} };
        },
    },
    tasks: {
        fetchTasks() {
            return Promise.resolve([]);
        },
        executeTask() {
            return Promise.resolve({ terminate() {} });
        },
        onDidEndTaskProcess() {
            return { dispose() {} };
        },
        onDidStartTaskProcess() {
            return { dispose() {} };
        },
    },
    Task: class {
        constructor(definition, scope, name, source, execution) {
            this.definition = definition;
            this.scope = scope;
            this.name = name;
            this.source = source;
            this.execution = execution;
        }
    },
    ShellExecution: class {
        constructor(command, options) {
            this.command = command;
            this.options = options;
        }
    },
};

const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
    if (request === 'vscode') return 'vscode';
    return originalResolve.call(this, request, ...rest);
};
require.cache.vscode = { id: 'vscode', filename: 'vscode', loaded: true, exports: vscode };

const extension = require(extensionPath);
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vscodroid-runner-'));
try {
    fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ scripts: { test: 'node test.js', "it's": 'ok' } }));
    fs.writeFileSync(path.join(root, 'Makefile'), 'build:\n\t@echo build\ncheck::\nclean:\n');

    const scripts = extension.packageScripts(root);
    assert.deepStrictEqual(scripts.map((item) => item.label), ["npm: it's", 'npm: test']);
    assert.strictEqual(scripts[0].command, "npm run 'it'\\''s'");
    assert.deepStrictEqual(extension.makeTargets(root).map((item) => item.label), ['make: build', 'make: check', 'make: clean']);
    assert.strictEqual(extension.shellQuote("a'b"), "'a'\\''b'");

    const context = { subscriptions: [] };
    extension.activate(context);
    assert.ok(registered.has('vscodroid.localRunner.run'));
    assert.ok(registered.has('vscodroid.localRunner.cancel'));
    assert.strictEqual(status.command, 'vscodroid.localRunner.run');

    return registered.get('vscodroid.localRunner.run')().then(() => {
        assert.deepStrictEqual(errors, ['Open a workspace before using the local runner.']);
        extension.deactivate();
        console.log('ok -- local runner discovery, quoting, and workspace guard');
    });
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
