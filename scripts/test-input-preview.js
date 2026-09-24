'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(
    path.join(__dirname, '../android/app/src/main/kotlin/com/vscodroid/MainActivity.kt'),
    'utf8'
);
const marker = 'private const val INPUT_PREVIEW_SCRIPT = """';
const start = source.indexOf(marker) + marker.length;
const script = source.slice(start, source.indexOf('"""', start));
assert(start > marker.length - 1, 'input preview script is missing');

class FakeContext {
    constructor(text) {
        this.text = text;
        this.listeners = new Map();
    }

    addEventListener(type, listener) {
        const listeners = this.listeners.get(type) || [];
        listeners.push(listener);
        this.listeners.set(type, listeners);
    }

    emit(type) {
        for (const listener of this.listeners.get(type) || []) listener();
    }
}

class FakeInput {
    constructor(value) {
        this.value = value;
    }
}

const listeners = new Map();
const document = {
    activeElement: null,
    addEventListener(type, listener) {
        const entries = listeners.get(type) || [];
        entries.push(listener);
        listeners.set(type, entries);
    },
};
const context = new FakeContext('abc');
const editHost = {
    editContext: context,
    isContentEditable: false,
    closest(selector) {
        return selector.includes('native-edit-context') ? this : null;
    },
};
const body = {
    isContentEditable: false,
    closest() {
        return null;
    },
};
document.activeElement = editHost;
const window = {
    requestAnimationFrame(listener) {
        listener();
    },
};
const sandbox = {
    window,
    document,
    setTimeout,
    clearTimeout,
    WeakSet,
    HTMLInputElement: FakeInput,
    HTMLTextAreaElement: class {},
};
vm.runInNewContext(script, sandbox);
const state = window.__vscodroidInputPreviewState;
assert.strictEqual(state.text, 'abc');

function emit(type) {
    for (const listener of listeners.get(type) || []) listener();
}

function wait() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function main() {
    context.text = 'ab';
    context.emit('textupdate');
    await wait();
    assert.strictEqual(state.text, 'ab');

    document.activeElement = body;
    emit('focusout');
    await wait();
    assert.strictEqual(state.text, '');

    document.activeElement = new FakeInput('deleted');
    emit('focusin');
    await wait();
    assert.strictEqual(state.text, 'deleted');

    vm.runInNewContext(script, sandbox);
    assert.strictEqual(listeners.get('input').length, 1);
    console.log('ok -- landscape input preview follows EditContext and input events');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
