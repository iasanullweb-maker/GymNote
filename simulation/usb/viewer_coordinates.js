// Canvas CSS coordinates -> unrotated video buffer -> portrait HID coordinates.
(function (root) {
    root.gymNoteTouchCoordinates = function (point, geometry, mode = 'auto') {
        const {left, top, width, height, canvasWidth: cw, canvasHeight: ch, visualRotation = 0} = geometry;
        if (![width, height, cw, ch].every(value => Number.isFinite(value) && value > 0)) {
            throw new Error('Invalid touch surface dimensions');
        }
        const sideways = Math.abs(visualRotation % 180) === 90;
        const dw = sideways ? ch : cw, dh = sideways ? cw : ch;
        const dx = (point.clientX - left) * cw / width - cw / 2;
        const dy = (point.clientY - top) * ch / height - ch / 2;
        const rad = -visualRotation * Math.PI / 180;
        const clamp = value => Math.max(0, Math.min(1, value));
        let x = clamp((dx * Math.cos(rad) - dy * Math.sin(rad) + dw / 2) / dw);
        let y = clamp((dx * Math.sin(rad) + dy * Math.cos(rad) + dh / 2) / dh);
        // Real-device click and drag verification confirmed the 270-degree mode.
        const rotation = mode === 'auto' ? (dw > dh ? '270' : '0') : mode;
        if (rotation === '90') [x, y] = [y, 1 - x];
        else if (rotation === '270') [x, y] = [1 - y, x];
        else if (rotation === '180') [x, y] = [1 - x, 1 - y];
        else if (rotation !== '0') throw new Error('Unknown touch coordinate mode');
        return {x: Math.round(x * 65535), y: Math.round(y * 65535)};
    };
})(globalThis);
