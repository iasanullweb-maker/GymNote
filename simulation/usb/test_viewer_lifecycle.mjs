import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

export function runTests() {
    const callbacks = new Map();
    let focused = true, now = 0, resets = 0, recoveries = 0;
    const document = {
        visibilityState: 'visible', hasFocus: () => focused,
        addEventListener: (event, fn) => callbacks.set(event, fn),
    };
    const window = {addEventListener: (event, fn) => callbacks.set(event, fn)};
    const context = vm.createContext({});
    vm.runInContext(readFileSync(new URL('./viewer_lifecycle.js', import.meta.url), 'utf8'), context);
    const lifecycle = context.createGymNoteViewerLifecycle({document, window, now: () => now});
    lifecycle.setReset(() => resets++);
    lifecycle.setRecover(() => recoveries++);
    assert.equal(lifecycle.canRecover(), true);
    focused = false; callbacks.get('blur')(); now = 30000;
    assert.equal(lifecycle.canRecover(), false, 'other PC app must suppress automatic recovery');
    document.visibilityState = 'hidden'; callbacks.get('visibilitychange')();
    assert.equal(lifecycle.isActive(), false);
    focused = true; callbacks.get('focus')();
    assert.equal(recoveries, 0, 'hidden tab must not recover on focus alone');
    document.visibilityState = 'visible'; callbacks.get('visibilitychange')();
    assert.equal(recoveries, 1);
    assert.equal(resets, 1);
    assert.equal(lifecycle.canRecover(), false, 'return must allow decoder to recover before timeout');
    callbacks.get('focus')();
    assert.equal(recoveries, 1, 'focus and visibility events must not request duplicate keyframes');
    now += 4999; assert.equal(lifecycle.canRecover(), false);
    now++; assert.equal(lifecycle.canRecover(), true, 'real foreground stalls remain detectable');
    focused = false; callbacks.get('blur')(); focused = true; callbacks.get('focus')();
    assert.equal(recoveries, 2, 'second app round trip must recover again');
    return 'Lifecycle checks passed (background, return grace, duplicate events, repeated return).';
}
