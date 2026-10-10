/* Lifecycle for the local USB viewer. No clipboard, audio or device data. */
(function (root) {
    root.createGymNoteViewerLifecycle = function (env) {
        let paused = !active();
        let graceUntil = 0;
        let reset = () => {};
        let recover = () => {};
        function active() {
            return env.document.visibilityState === 'visible' && env.document.hasFocus();
        }
        function changed() {
            if (!active()) { paused = true; return; }
            if (!paused) return;
            paused = false;
            graceUntil = env.now() + 5000;
            reset();
            recover();
        }
        env.window.addEventListener('blur', () => { paused = true; });
        env.window.addEventListener('focus', changed);
        env.document.addEventListener('visibilitychange', changed);
        return {
            isActive: active,
            canRecover: () => active() && env.now() >= graceUntil,
            setReset: callback => { reset = callback; },
            setRecover: callback => { recover = callback; },
        };
    };
})(globalThis);
