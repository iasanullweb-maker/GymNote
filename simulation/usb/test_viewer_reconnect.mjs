import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

// Use the generated, fully patched upstream source so a patch integration
// error cannot be hidden by testing a second copy of the reconnect function.
export function runTests(patchedPath) {
    const source = readFileSync(patchedPath, 'utf8');
    const boundary = source.indexOf('/* Lifecycle for the local USB viewer.');
    assert.ok(boundary > 0);
    const prefix = source.slice(0, boundary);
    const storage = new Map();
    let reloads = 0;
    let timers = [];
    let expectedDelay = 5000;
    function page() {
        timers = [];
        const context = vm.createContext({
            performance: {now: () => 0},
            sessionStorage: {getItem: k => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, v)},
            location: {reload: () => reloads++},
            setTimeout: (fn, delay) => { assert.equal(delay, expectedDelay); timers.push(fn); },
            log: () => {},
        });
        vm.runInContext(prefix, context);
        return context;
    }
    for (let remaining = 2; remaining >= 0; remaining--) {
        expectedDelay = [30000, 15000, 5000][remaining];
        const context = page();
        vm.runInContext('gymReconnectViewer(); gymReconnectViewer();', context);
        assert.equal(timers.length, 1, 'read failure and foreground recovery must share a reload');
        assert.equal(storage.get('gymReconnectBudget'), String(remaining));
        timers[0]();
    }
    const exhausted = page();
    vm.runInContext('gymReconnectViewer()', exhausted);
    assert.equal(timers.length, 0, 'repeated failure must stop after 3 reloads');
    assert.equal(reloads, 3);
    storage.set('gymReconnectBudget', 'invalid');
    vm.runInContext('gymReconnectViewer()', page());
    assert.equal(timers.length, 0, 'corrupt stored budget must not create an infinite loop');
    assert.ok(source.includes('performance.now() - gymStartedAt >= 60000'));
    assert.ok(source.includes('streamTerminated = true; gymReconnectViewer();'));
    assert.ok(source.includes('gymBrowserCounters.messages++'));
    assert.ok(source.includes('drawFrame(f); gymBrowserCounters.drawn++'));
    return 'Reconnect checks passed (deduplication, cross-reload budget, invalid budget, stream integration).';
}
