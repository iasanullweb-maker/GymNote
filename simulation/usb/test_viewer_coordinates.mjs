import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

export function runTests() {
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(new URL('./viewer_coordinates.js', import.meta.url), 'utf8'), context);
    const convert = context.gymNoteTouchCoordinates;
    const base = {left: 100, top: 50, width: 800, height: 600, canvasWidth: 1600, canvasHeight: 1200};
    const point = (u, v, geometry = base, mode = 'auto') => {
        const result = convert({clientX: geometry.left + u * geometry.width, clientY: geometry.top + v * geometry.height}, geometry, mode);
        return [result.x, result.y];
    };
    // User's two corner observations plus the opposite corners and center.
    assert.deepEqual(point(1, 0), [0, 0]);
    assert.deepEqual(point(1, 1), [65535, 0]);
    assert.deepEqual(point(0, 0), [0, 65535]);
    assert.deepEqual(point(0, 1), [65535, 65535]);
    assert.deepEqual(point(.5, .5), [32768, 32768]);
    const start = point(.5, .8), end = point(.5, .2);
    assert.ok(end[0] < start[0]); assert.equal(start[1], end[1]);
    // CSS scale / backing pixel ratio cannot change the target.
    assert.deepEqual(point(.23, .71), point(.23, .71, {...base, width: 400, height: 300}));
    assert.deepEqual(point(.23, .71), point(.23, .71, {...base, canvasWidth: 800, canvasHeight: 600}));
    const portrait = {...base, canvasWidth: 1200, canvasHeight: 1600};
    assert.deepEqual(point(1, 0, portrait), [65535, 0]);
    assert.deepEqual(point(1, 0, base, '270'), [65535, 65535]);
    assert.deepEqual(point(1, 0, portrait, '180'), [0, 65535]);
    assert.deepEqual(point(1, 0, base, '0'), [65535, 0]);
    // Visually rotating a portrait buffer must not apply the native correction twice.
    assert.deepEqual(point(1, 0, {...base, visualRotation: 90}), [0, 0]);
    assert.deepEqual(point(1, 0, {...base, visualRotation: -90}), [65535, 65535]);
    assert.deepEqual(point(-.2, 1.2), [65535, 65535]);
    assert.throws(() => point(0, 0, {...base, width: 0}), /dimensions/);
    assert.throws(() => point(0, 0, base, 'bad'), /mode/);
    return 'Coordinate checks passed (corners, drag axis, scale, portrait, opposite rotation, visual rotation, bounds).';
}
