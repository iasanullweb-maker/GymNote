import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

export function runTests(patchedPath) {
    const source = readFileSync(patchedPath, 'utf8');
    const start = source.indexOf('const offlineOverlay =');
    const end = source.indexOf('}, 1000);', start) + '}, 1000);'.length;
    assert.ok(start > 0 && end > start);
    function scenario(idle, fresh) {
        let tick;
        const requests = [];
        let hidden = false;
        const context = vm.createContext({
            document: {getElementById: () => ({classList: {
                add: () => {hidden = true;}, remove: () => {hidden = false;},
            }})},
            gymViewer: {canRecover: () => true, setReset: () => {}},
            frameCount: 10, gymServerHealth: {video_idle: idle},
            gymHealthUpdated: fresh ? 10000 : 0,
            performance: {now: () => 10000},
            setInterval: callback => {tick = callback;},
            fetch: url => {requests.push(url); return Promise.resolve();},
            log: () => {},
        });
        vm.runInContext(source.slice(start, end), context);
        for (let i = 0; i < 35; i++) tick();
        return {requests, hidden};
    }
    const idle = scenario(true, true);
    assert.deepEqual(idle.requests, [], 'confirmed idle must not restart a healthy device');
    assert.equal(idle.hidden, true);
    for (const result of [scenario(false, true), scenario(true, false)]) {
        assert.ok(result.requests.includes('/pli'));
        assert.ok(result.requests.includes('/restart'), 'stale health or decoder stall must retain recovery');
        assert.equal(result.hidden, false);
    }
    return 'Idle checks passed (fresh device status, stale status, decoder stall).';
}
