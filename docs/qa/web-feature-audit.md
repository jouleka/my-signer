# Web feature audit

Started 2026-10-03. Scope: the web product, excluding CLI implementation.

For each feature: reproduce in the browser with representative local data,
check the success and failure paths, fix concrete defects, add regression
coverage, then reload/reopen to verify persistence. Provider responses in
local tests are controlled fixtures; they do not prove a live store action.

## Baseline

- Existing suite: 3,101 examples, 0 failures (2026-10-03).
- Browser audit uses an isolated local PostgreSQL database and a test-mode
  app. External server requests are blocked, email uses the test delivery
  adapter, and background jobs are queued without contacting providers.
- Existing legal-page and comparison-copy changes predate this audit.

## Feature order and status

| Feature | Status | Follow-up |
| --- | --- | --- |
| Dashboard | Initial local pass | Active connection status, history windows, error guidance, desktop/mobile layout; metric units follow with Analytics |
| Store connections and sync | Initial local pass | Add/test/activate/remove, invalid input recovery, error dismissal, role restrictions; live provider sync still pending |
| Screenshot Studio | Initial local pass | Create/edit/reopen, all-scene save, ZIP files, translated upload staging, failure/retry, responsive preview; live store publishing and advanced combinations pending |
| Store listings and localization | Initial local pass | Save/reopen, locale limits, translation failure/retry, sync and multi-locale push status; live provider acceptance pending |
| Releases, notes, approvals, checklists | Initial local pass | Autosave, version scope, review state, checklist persistence, AI and submission failure/retry; live provider acceptance pending |
| Keywords and ASO | Pending | Suggestions, tracking, locales, degraded provider data |
| Reviews and ratings | Pending | Filters, templates, replies, provider failures |
| Analytics | Pending | Metric units, missing data, date windows, incomplete retention |
| Custom Product Pages | Pending | Editing/screenshots/submission; performance ingestion gap |
| Signing assets | Pending | Devices, profiles, capabilities, keystores, downloads |
| Organizations and teams | Pending | Membership, invitations, role boundaries |
| Security and API tokens | Pending | Tokens, SSO, audit log, BYOK failure paths |
| Notifications | Pending | Preferences, read/dismiss, links and delivery |
| Accounts and billing | Pending | Signup, restore, checkout and plan-change contracts |
| Public site and help | Pending | Navigation, documentation accuracy, contact form |

## Known gaps from initial inventory

- Retention analytics has display fields but no identified ingestion.
- Custom Product Page performance has display fields but no identified ingestion.
- Screenshot captions have manual locale overrides; no AI translation flow found.
- Browser submission is implemented for Apple apps only.

These are investigation items, not completed tests or a request to build all
missing features. Resolve each when its feature reaches the audit.

## Pass 1: dashboard and store connections

### Reproduced defects and changes

- The dashboard selected the most recently synced credential, even when it
  was inactive. A retired key could make a healthy connection look broken
  and bring back the setup checklist. It now reads the active connection.
- Dashboard totals ignored the Free plan's seven-day history limit. Current
  and previous periods also overlapped at their boundary and included future
  rows. A small `Dashboard::AnalyticsSummary` service now owns the date
  windows and omits comparisons outside the available history.
- The desktop header clipped its statistics. The shared header now stacks
  them at intermediate widths and allows the title to shrink. Inspected at
  1200px and 390px, including the painted mobile result.
- Apple agreement failures were reported as expired credentials. Agreement,
  authorization, authentication and connectivity failures now have separate
  guidance. Removed an unverified status-site link.
- Valid JSON with the wrong shape (`[]`, `null`, booleans, numbers, strings)
  raised a server error when adding an Android connection. It now returns a
  validation message.
- After a credential form redirect, an open native dialog could leave the
  replacement page unclickable. Dialogs are closed before Turbo replaces or
  caches the page. Verified invalid input, correction, save and reload.
- Adding an Apple connection failed before any HTTP request: JWT minting
  assumed a saved credential ID, but validation uses a temporary credential.
  Temporary keys now use the same signer without the persisted-key cache or
  credential-use audit; saved keys retain encrypted caching and auditing.
- Apple validation requested `include=team`, an unsupported relationship,
  and tested fallbacks against invented response shapes. Removed those
  fallbacks and request only the documented `seedId` field on `bundleIds`.
  Replaced mocked-client tests with HTTP-boundary fixtures and real signing.
  References: [List bundle IDs](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-bundleids),
  [List apps](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps).
- The Test connection buttons rejected inactive credentials before making a
  request. Explicit connection tests can now use inactive credentials without
  activating them; normal API clients still reject inactive credentials.

### Durable browser coverage

`spec/system/dashboard_connections_spec.rb` exercises:

1. Healthy active connection plus a failed retired connection, then reload.
2. Invalid Android JSON, validation feedback, correction, save and reload.
3. Free analytics history and reload.
4. Apple connection creation, persistence, inactive-key test, activation,
   removal confirmation and reload.
5. Cancelling and confirming a sync-error dismissal, then reload.

Request/service tests additionally cover real JWT signatures, distinct
temporary keys, encrypted token caching, Apple 401/403/503 responses, blank
or malformed input, no writes/jobs on failed validation, and developer/viewer
restrictions on credential actions.

### Verification results

- Full suite after changes: **3,122 examples, 0 failures, 0 pending**, 136.3s.
- Five new headless-Chrome system scenarios passed, including reload and
  form-recovery checks. Screenshots from manual inspection are retained in
  the ignored `tmp/web-feature-audit/screenshots/` folder.
- RuboCop: 18 touched/new Ruby files inspected, no offenses.
- `git diff --check`: clean. Tailwind assets built successfully for browser QA.
- No commit, push or deployment was performed.

Re-run with a dedicated test database:

```sh
RAILS_ENV=test DATABASE_URL=postgresql://localhost/my_signer_test bundle exec rspec
```

### Limits of this pass

- Provider responses are fixtures; no production records or real Apple/Google
  resources were changed. Real store authentication, background sync completion
  and publishing remain unverified by this pass.
- Google Test connection obtains an OAuth token; it does not prove permission
  to manage a particular Play Store app.
- Analytics ingestion/metric units and the remaining feature areas above still
  need their own passes. A green test suite is not full product acceptance.

## Pass 2: Screenshot Studio

### Reproduced defects and changes

- Uploading the first scene left the canvas uninitialized until a full reload.
  Turbo morph kept the empty editor controller alive. The editor now requests
  replacement refreshes so scene uploads/deletions reconnect its canvas state.
- Save only wrote the selected scene; drafts on previously edited scenes were
  lost on reopening. Save and Ctrl/Cmd+S now save every dirty scene. Removed the
  unused save dropdown, counter, alias and duplicate save path.
- ZIP entries collided within presets. Three required iPhone sizes became one
  file, and two iPad sizes became one. Filenames now include dimensions. Actual
  downloaded PNGs retain all six selected iPhone/iPad/Android sizes in both ZIP
  layouts.
- Export used the selected scene's effective settings as the base for every
  scene. A red background on scene 1 made an otherwise black scene 2 red. Save,
  ZIP export and store rendering now share project settings without selected
  scene overrides. PNG pixel checks cover both ZIP and store staging. Frame
  selection and panoramic slice settings use each scene's effective settings.
- Server staging discarded locale identity, and the upload job reused the same
  images for different languages. Exports now retain locale, scene and size;
  jobs select each language's files. Missing translated files fail before
  creating screenshot sets or uploading images.
- Replacing a batch left stale cloud exports and counted both disk and cloud
  copies against quota. Web staging now replaces one ActiveStorage batch, credits
  its previous size, and rejects a partially invalid batch before removing the
  previous one. The API's existing unlocalized export path remains supported.
- Cloud files were sorted by random temporary filenames, which could put scene
  10 before scene 2. The upload order now follows numeric scene position.
- Google Play's Replace existing switch read the Apple tab's switch. The two
  targets are now independent. Failed upload progress no longer counts a file
  twice, and the progress bar reappears when retrying.
- The preview had a fixed 440px painted width and was clipped on a 390px phone
  viewport. It now scales to its container without changing the rendered image
  or its aspect ratio.

### Acceptance coverage

`spec/system/screenshot_studio_spec.rb` adds ten Chrome scenarios:

1. Create a project, upload its first scene, edit captions, save and reload.
2. Download and inspect all selected sizes in the standard ZIP.
3. Download and inspect all selected sizes in the Fastlane ZIP layout.
4. Edit two scenes, click Save once, and verify both after reload.
5. Verify different scene backgrounds in actual exported PNG pixels.
6. Edit English/German captions, block the scene save request, retain the draft,
   recover with the keyboard shortcut, and verify both languages after reload.
7. Apply a template, undo, redo, save and reopen.
8. Render/stage translated Google Play images, inspect saved PNGs and upload
   config, display a failed job, retry, and display completion.
9. Resize between mobile and desktop, checking preview bounds and aspect ratio.
10. Export a dark variant with readable light caption pixels, preserving saved
    project colors. This caught and corrected a regression during the settings
    refactor; exports need visible preview colors while Save needs canonical ones.

`spec/requests/screenshot_locale_uploads_spec.rb` adds nine cases for distinct
language bytes at Apple/Google handoff, stale-batch replacement, missing locale
failure, numeric scene order, temporary-file cleanup, partial upload failure,
quota replacement and preservation after invalid input. Existing request/model/
service coverage also runs in the full suite.

Manual Chrome inspection additionally checked saved emoji stickers, an iPhone
frame after reopening, and the painted responsive preview. Artifacts are retained in the ignored
`tmp/web-feature-audit/` folder.

### Verification results

- Initial focused Studio baseline: **293 examples, 0 failures**. New browser
  and request tests reproduced defects that this baseline did not catch.
- Full suite: **3,140 examples, 0 failures**, 171.6s.
- New coverage: **19 examples**, including **10 browser scenarios**. After the
  final dark-preview compatibility adjustment, all ten Studio browser scenarios
  passed again (38.6s), including the new dark export check.
- RuboCop and JavaScript syntax checks passed for the changed implementation
  and new specs; `git diff --check` is clean.
- No commit, push, deployment or production data change was performed.

### Limits of this pass

- Apple/Google image handoff uses controlled provider doubles. Browser polling
  uses locally persisted job states. Neither proves real store publishing,
  provider acceptance of every size, or live credentials.
- All advanced design combinations are not certified: custom image libraries,
  every frame/perspective/panorama combination, bulk editing and full Fastlane
  tool import still need targeted acceptance checks.
- Followed by the store listings and localization pass below.

## Pass 3: store listings and localization

### Reproduced defects and changes

- Autosave could overlap requests, lose the latest edit during a locale/tab
  switch, or leave a failed draft behind. Saves now run sequentially and
  navigation, translation and push wait for them. Failed saves retain the
  draft and show the server's validation error. Every locale has a visible
  save indicator and an explicit Save button for recovery.
- Locale switching reused editor elements across languages. Editors now have
  a stable identity per listing. The Android selector now uses Google Play
  locale codes, and its menu stays open after choosing an option. Initial
  creation and Add Locale both validate store support; counts and creation
  are protected by an app lock. The locale bar wraps on phone screens.
- Viewers could see editable fields and write controls even though the server
  rejected changes. Their listing fields now render disabled and write actions
  are hidden. Backend authorization remains enforced.
- AI translation truncated every source field to 500 characters, accepted
  incomplete or empty responses, could change unrequested fields, and could
  overwrite edits made during the API call. It now sends the full source,
  validates the requested output, preserves other fields and rejects stale
  results. Listing translation leaves release notes to the What's New flow.
- Translation progress disappeared on reload. A failed job or a quota exhausted
  after enqueueing could leave the button stuck, without an explanation.
  Pending/error state is now persisted, duplicate requests are checked under
  a listing lock, failures retain the draft and refund quota, and a broadcast
  failure does not refund a completed translation. A job also verifies that
  source and target belong to the same app.
- Sync could claim completion before a queued job ran, using existing listing
  timestamps. It now tracks a scoped operation ID through queued, running,
  retrying, completed and failed states. The job resolves the app through its
  organization. Empty imports can complete correctly, and errors remain visible.
- Imports overwrote unpushed local drafts. Both store importers now preserve
  local changes and use row locks when merging screenshot metadata. A push
  finishing during a manual edit leaves those newer edits marked as unpushed.
- Push polling watched only the primary language. It now aggregates all locales,
  waits for every result, and identifies failures/skipped fields by locale.
  Page views no longer erase other languages' results. Retry restores the
  button and submits normally after confirmation.
- Web pushes previously queued concurrent jobs for each locale. One batch now
  processes locales sequentially and continues after a locale fails; duplicate
  web push/sync requests are guarded. Google documents that committing an edit
  invalidates other open edits for that app:
  [Google Play edit workflow](https://developers.google.com/android-publisher/edits).
- The Apple adapter omitted Privacy Policy URL and skipped promotional text
  when only a live version existed. Both paths are covered now. Explicitly
  clearing a saved field is tracked separately from an untouched empty draft
  and sent as an empty value; provider rejection remains visible. References:
  [App info localizations](https://developer.apple.com/documentation/appstoreconnectapi/app-info-localizations),
  [Apple version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).
- Failed Google release-note pushes reported full success. They now report
  partial success with skipped fields. Unsupported URL fields are hidden from
  Android listing forms; the API listing resource has no corresponding URL
  properties: [Google listing resource](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.listings).
- Keyword validation and counters treated Apple's 100-byte limit as 100
  characters. They now count UTF-8 bytes, including AI keyword fitting. Other
  counters count Unicode code points consistently with server validation.
  URL validation also rejects protocol-only values such as `https:`.
  [Apple's metadata limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

### Acceptance coverage

`spec/system/store_listings_spec.rb` adds eleven Chrome scenarios:

1. Validation failure, correction, save and reload.
2. Japanese keyword byte counts, over-limit rejection and corrected persistence.
3. Save before translation, pending after reload, failed job, retry and translated
   content after reload, with the review marker intact.
4. Queued sync stays pending after polling; failure is visible and retry enabled.
5. Secondary-locale push progress and failure shown from the primary locale.
6. Save before push, confirmation, failed batch and another accepted push request.
7. Read-only viewer fields and hidden write controls.
8. Readable language tabs at a 390px viewport.
9. Delayed save requests, rapid edits and switching languages without data loss.
10. Failed save blocks leaving the draft; recovery persists it through reload.
11. Add a Google Play Japanese locale, edit it and reopen it.

Request, model, job and service coverage additionally checks locale limits and
validation on both creation routes, translation quotas and malformed output,
organization boundaries, full sync retry exhaustion, per-locale push aggregation,
batch failure continuation, import preservation, edits made during push, Apple
privacy/live promotional text, explicit field clearing, and Google partial results.

Manual Chrome inspection checked the painted desktop and phone layouts, a real
local PATCH response, cross-locale references, and persistence after reopening.
Screenshots and CLI traces are retained under ignored `tmp/web-feature-audit/`.

### Verification results

- Initial focused baseline: **111 examples, 0 failures**; new scenarios exposed
  failures absent from that baseline.
- Full suite before final field-clearing/Unicode checks: **3,177 examples,
  0 failures**, 179.3s.
- Final full suite: **3,183 examples, 0 failures**, 183.7s. This pass adds
  **43 regression examples**, including **11 browser scenarios**.
- RuboCop: **23 Ruby files inspected, no offenses**. All three changed JavaScript
  controllers pass syntax checks; `git diff --check` is clean. Tailwind built
  successfully for the painted browser checks.
- Explicit field clearing was also verified through the manual browser, reload,
  persisted database value and outgoing adapter value: saved `null`, recorded
  clear intent, outgoing empty string.

### Limits of this pass

- Apple, Google and AI responses are controlled local fixtures/doubles. Live
  credentials, provider acceptance, translation quality and production queue/
  cache/Cable behavior remain unverified. The browser checks pending/result
  state through reload; they do not certify live Cable delivery.
- Imported local drafts are preserved; there is no new conflict comparison or
  explicit discard-and-reimport workflow in this pass.
- Serialization covers web listing batches. Concurrent operations initiated in
  external consoles, other sync/upload flows or the CLI can still invalidate
  a Google edit and must surface as a failed operation.
- Release notes, approvals, builds, checklists and store submission are the next
  feature pass. Shared release pages were included in regression testing, but
  those workflows have not received their own acceptance pass yet.
- No commit, push, deployment or production-data change was performed.

## Pass 4: releases, notes, approvals and checklists

### Reproduced defects and changes

- Freeform notes and translations were overwritten in hidden fields when the
  editor connected. Template bullet removal did not schedule a save. The
  editor now preserves the saved content on load and serializes every edit.
- Autosave tracked only one form and allowed overlapping requests. Version,
  base text and translation saves now share a queue, preserve failed drafts,
  expose server validation errors, and finish before navigation, review,
  application or push. iOS and Android counters handle emoji consistently
  with server limits. Template output is validated before persistence.
- Notes and checklists from an older version were reused for a new release.
  Notes, checklists, build/status displays and submission now use the selected
  version. Old Apple validation errors no longer block the current version.
  A first draft can be created before any store version has been synced.
- Approval with a comment was interpreted as rejection. The new
  `review_decision` column records the actual decision. The migration preserves
  the old interpretation of existing rows; it cannot recover whether a
  historical comment was actually attached to an approval. Pending notes are
  frozen at the server, state transitions lock the record, edits invalidate an
  approval, and rejected notes can be corrected and resubmitted. The browser
  clears stale approval messaging as soon as an edited draft is saved.
- Note mutations and checklist routes now verify the app as well as the
  organization. Viewer controls and pending-review editors are read only;
  server policies enforce the same boundary.
- Applying a note no longer reports success while silently omitting a missing
  locale listing. Application is atomic and gives a useful missing-locale
  error. Editing an applied note returns it to draft for reapplication.
- AI rewrite/translation state survives reload, rejects duplicate work, and
  exposes queue/provider/quota failures with retry. Invalid or overlong
  responses preserve the draft and refund quota. Stale AI output cannot
  overwrite intervening edits. Broadcast failures do not refund saved work.
- A second checklist click used the original endpoint, so unchecking could
  appear successful but remain checked in the database. Check/uncheck now use
  separate endpoints, wait for the response, show failures and allow retry.
  Progress uses server totals including detected issues, excludes the custom
  item's Required checkbox, and updates both counters and readiness.
- Custom-item duplicates display an error instead of failing the Turbo
  response. Concurrent checklist edits preserve each other, reset also clears
  custom items, and readiness cannot report success if a required detected
  issue exists or detection fails. Manual items remain the existing advisory
  checklist; required detected errors gate push and submission.
- Scheduled submission sent a timezone-less value despite promising local
  time. A Stimulus controller now sends UTC converted from the browser's local
  time, enforces the date input and replaces accumulating inline listeners.
  Automatic release is explicitly persisted to Apple, including after a
  previously manual/scheduled setting. Client initialization failures now
  clear the submitting state and expose a retryable error.
- The Build tab is a status display, so missing-build guidance now points to
  App Store Connect. Review controls no longer overlap the message on mobile.
  Apple release-setting contract checked against
  [App Store version update attributes](https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionupdaterequest/data-data.dictionary/attributes-data.dictionary).

### Durable browser coverage

`spec/system/release_workflow_spec.rb` covers freeform load, template removal,
validation/correction, immediate apply, multiple forms and locales, review
rejection/resubmission/approval, approval invalidation after editing, viewer
permissions, custom checklist add/duplicate/remove, check/uncheck persistence,
failed-save retry, AI pending/reload/failure/retry, scheduled iOS submission
failure/retry, Android limits and emoji, mobile review layout, and creating,
reopening through History and deleting the first unsynced draft.

Provider responses and AI responses are controlled fixtures. Submission tests
verify the chosen UTC time reaches the job and that failure/retry updates the
visible browser state. Manual local QA also checked the painted 390px editor
and review banner, persisted edits, and approval invalidation.

### Validation and remaining boundaries

- Final full suite: **3,228 examples, 0 failures** (208.9 seconds).
- Added **45 regression examples**, including **17 browser scenarios**.
- RuboCop: 28 Ruby files inspected, no offenses. Seven touched JavaScript
  controllers passed syntax checks; `git diff --check` passed.
- Local evidence is under ignored `tmp/web-feature-audit/releases/`, including
  before/final test logs and desktop/mobile screenshots.
- Requires the included `AddReviewDecisionToReleaseNotes` migration on any
  environment receiving the code. Applied only to local test/QA databases.
- Live Apple/Google submission, real AI output quality and production job/
  websocket delivery remain unverified. No deployment or production mutations
  were performed in this pass. Browser Android track promotion/submission and
  build attachment are not implemented features; use the provider consoles.
