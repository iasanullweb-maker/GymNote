# demo-v1 capture workstream

This directory defines captures, not completed screenshots. The checked-in manifest has the ten base 834×1194pt IDs, all pending, appCommit=null, and no invented image paths or hashes. Run-generated images/manifests stay under ignored simulation/runs/. Node 24+ is required for the standalone collector; no dependencies or model/API calls are used.

## Product entry points and limits

| ID | Actual entry point | Limitation |
|---|---|---|
| workout-ready | TodayView, idle preview model | AppModel.todayPlan/workoutDate use Date(). XCTest skips outside the anchor day (2026-10-12 Seoul) rather than capturing the wrong day's workout. |
| workout-active | TodayView, fixed activeWorkout | Fixed session date and actual reps; direct screen without RootView's pinned timer/tab chrome. |
| workout-rest | WorkoutStatusBanner | Skipped: TimelineView context.date and Text(timer) cannot be frozen with current injection points. |
| plan-month | RoutineView(selectedDate: anchor) | Fixed selected date/month; Calendar.current.isDateInToday highlight still follows actual day. |
| plan-date-detail | NavigationStack + ScheduledDayEditor(date: anchor) | Fixed selected date and exercises. |
| records-overview | RecordsView + offline unconfigured account | Actual common-record cards using bundle defaults, no server refresh. |
| journal-calendar | WorkoutJournalView | Skipped: private selectedDate=Date() prevents the fixed initial month/day. A standalone calendar is not substituted. |
| journal-entry | ManualWorkoutView + isolated UserDefaults suite | Seeded synthetic draft for 2026-10-08. DatePicker maximum/validation still use real Date(). |
| friends-home | FriendsView in separate friend tab | Skipped: authenticated profile/friend/group state has no safe offline injection. Guest gate is not substituted for populated management. |
| friends-ranking | FriendRankingView in records | Skipped: same private authenticated state/entries limitation. It is a separate entry point from FriendsView. |

Each test builds a fresh value copy/model. Fixed UUIDs, plan values, record dates, completed journal values and active session dates do not depend on execution time. AppData.init's temporary current-week/UUID seed is replaced before returning. Neither the fixture nor tests load AppData.sample. AccountModel(client:nil, initialConnection:.offline, monitorConnectivity:false) is assigned to the model's lazy account before screen rendering. Its catalog lock is redirected through existing SharedStore.testingDirectory to a fresh temporary directory and restored/removed afterward. No bootstrap/login/Keychain or network client is invoked by the capture harness. ManualWorkoutView uses a fresh defaultAppStorage suite and synthetic user ID, never the guest draft key. The suite is deleted afterward.

The hosted application starts BEFORE XCTest setup and still runs its normal AppModel/RootView lifecycle. Therefore use a NEW dedicated simulator with no accounts/data and empty Supabase build settings; these tests do not claim process-wide isolation from the host lifecycle. Never run on an operating user's device or a simulator containing their records/tokens. This limitation cannot be solved by the allowed B files alone.

The view harness injects ko_KR, Gregorian calendar and Asia/Seoul, and temporarily sets NSTimeZone.default for existing DayKey/Calendar.current calls. It does not freeze Date(), TimelineView or UIKit's status bar clock. Keep the metadata JSON attachment (renderedAt and system-clock-not-frozen) beside the PNG evidence. This is direct product-view rendering, not proof of navigation, saves, notifications or authenticated friends flows. The product RootView tab bar and pinned status card are outside these direct entry points.

## Mac execution (no CI or remote push needed)

Use a clean committed checkout containing B changes. Install Xcode/XcodeGen separately if needed. Create a dedicated iPad simulator in Xcode's Devices and Simulators window (no login/restore). Replace SIMULATOR-UDID below with that simulator's actual UDID. Keep parallel testing disabled because the existing SharedStore hook/timezone are process globals.

~~~sh
xcodegen generate
mkdir -p simulation/runs/mac-capture-001
# Save the exact checkout SHA BEFORE rendering. Do not change code between test and export.
git rev-parse HEAD > simulation/runs/mac-capture-001/app-commit.txt
xcodebuild test -project GymNote.xcodeproj -scheme GymNote -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UDID' \
  -derivedDataPath DerivedData/ux-capture \
  -resultBundlePath simulation/runs/mac-capture-001/Capture.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:GymNoteTests/UXSimulationCaptureTests \
  GYMNOTE_SUPABASE_URL= GYMNOTE_SUPABASE_PUBLISHABLE_KEY= CODE_SIGNING_ALLOWED=NO
~~~

Review passed, failed and skipped test cases in Xcode's result bundle. Export each keepAlways PNG and its metadata attachment through Xcode to simulation/runs/mac-capture-001/attachments/. Attachment names are ID--WIDTHxHEIGHT--TEXTSCALE.png; exported physical names may differ. Do not mark a test captured if its assertions failed even if an attachment exists. Record failure evidence as status=failed with a nonempty error; skipped/unrun remain pending. A fresh run ID/output directory is required on retries.

Create a mapping from actual exported files, not predicted names. The following is a format example ONLY; replace relativePath with the real exported name. Missing IDs stay pending. Include accessibility3 plan detail (834×1194, accessibility) and split workout (417×1194, standard) as additional variants only if those tests passed.

~~~json
{"captures":[{"id":"plan-date-detail","status":"captured","width":834,"height":1194,"textScale":"standard","relativePath":"actual-exported-file.png"}]}
~~~

Save the mapping in simulation/runs/mac-capture-001/receipts.json and run:

~~~sh
node simulation/capture/test-collect.mjs
node simulation/capture/collect.mjs --help
node simulation/capture/collect.mjs \
  --attachments simulation/runs/mac-capture-001/attachments \
  --receipts simulation/runs/mac-capture-001/receipts.json \
  --app-commit "$(cat simulation/runs/mac-capture-001/app-commit.txt)" \
  --output simulation/runs/mac-capture-001/capture
~~~

The collector verifies real source files, PNG chunk bounds/CRCs, scale=1 pixel dimensions, unique variants and SHA-256, then copies bytes under output/images/. relativePath is relative to the NEW output manifest; ../, absolute/drive paths and input symlinks are refused. Output is a new directory under ignored simulation/runs/; existing outputs are never overwritten. Keep the original xcresult, exported metadata, mapping and commit receipt as evidence. The collector validates file integrity, not the screenshot's UI content/test outcome or the truth of a supplied commit SHA; those must be checked against the result bundle and saved checkout receipt. It cannot promote the four blocked screens to captured without a future safe product injection point.

## Windows verification

The standalone Node executable, Swift, XcodeGen and Xcode were not present on PATH. The exporter self-tests ran via Codex's bundled Node REPL and passed (explicit synthetic 2×1 PNG input, never product evidence). Windows denied synthetic symlink creation, so that live filesystem symlink check is not-run; rejection code and path traversal checks were reviewed/tested. Swift fixture/isolation XCTest and real renders are not-run. No generated product PNG exists.
