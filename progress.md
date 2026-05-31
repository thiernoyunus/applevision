# Progress Log

## Session: 2026-03-01

### Phase 1: Requirements & Discovery
- **Status:** complete
- **Started:** 2026-03-01 14:52 EST
- Actions taken:
  - Confirmed the repository is empty.
  - Read the `xcodebuildmcp` skill because this is Apple platform work.
  - Read the `planning-with-files` skill because the task requires a multi-step build from scratch.
- Files created/modified:
  - `/Users/thiernodiallo/Coding/applevision/task_plan.md` (created)
  - `/Users/thiernodiallo/Coding/applevision/findings.md` (created)
  - `/Users/thiernodiallo/Coding/applevision/progress.md` (created)

### Phase 2: Planning & Structure
- **Status:** complete
- Actions taken:
  - Confirmed the public OCR path should be Vision text recognition rather than a direct Live Text API.
  - Chose a Swift Package Manager executable to keep setup minimal in an empty repo.
- Files created/modified:
  - `/Users/thiernodiallo/Coding/applevision/Package.swift` (modified)

### Phase 3: Implementation
- **Status:** complete
- Actions taken:
  - Replaced the placeholder executable with a real CLI parser and OCR pipeline.
  - Implemented batch image OCR with `VNRecognizeTextRequest`.
  - Implemented PDF handling that uses embedded PDF text when available and OCR fallback otherwise.
  - Added plain text and JSON output modes.
  - Added README usage documentation.
- Files created/modified:
  - `/Users/thiernodiallo/Coding/applevision/Sources/applevision/main.swift` (created)
  - `/Users/thiernodiallo/Coding/applevision/README.md` (created)

### Phase 4: Testing & Verification
- **Status:** complete
- Actions taken:
  - Built the package successfully with `swift build`.
  - Verified CLI help output.
  - Generated a sample PNG and sample PDF locally.
  - Verified OCR output for both sample files and JSON batch output for a folder.
  - Added structured OCR result models for per-line text, candidates, confidence, and bounding boxes.
  - Updated the OCR service to keep the top three Vision candidates per recognized line.
  - Verified JSON output now includes line-level OCR evidence for image OCR.
  - Added a heuristic review service and CLI verification report output.
  - Updated the macOS app to pause on suspicious lines and show a review panel before export.
  - Built the Xcode macOS app target successfully with `xcodebuild`.
- Files created/modified:
  - `/tmp/applevision-sample.png` (test artifact)
  - `/tmp/applevision-sample.pdf` (test artifact)
  - `/tmp/applevision-output.json` (test artifact)
  - `/Users/thiernodiallo/Coding/applevision/Sources/AppleVisionCore/Models.swift` (modified)
  - `/Users/thiernodiallo/Coding/applevision/Sources/AppleVisionCore/OCRService.swift` (modified)
  - `/Users/thiernodiallo/Coding/applevision/README.md` (modified)

### Phase 5: Delivery
- **Status:** complete
- Actions taken:
  - Reviewed the updated core model, OCR service, and README changes.
  - Prepared delivery notes describing the new structured OCR data.
- Files created/modified:
  - `/Users/thiernodiallo/Coding/applevision/task_plan.md` (updated)
  - `/Users/thiernodiallo/Coding/applevision/findings.md` (updated)
  - `/Users/thiernodiallo/Coding/applevision/progress.md` (updated)

## Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| Workspace inspection | `ls -la` | Detect current project state | Empty repo confirmed | ✓ |
| Package build | `swift build` | Executable should compile | Build completed successfully | ✓ |
| CLI help | `swift run applevision --help` | Usage text should render | Usage text printed successfully | ✓ |
| Image OCR | `./.build/debug/applevision /tmp/applevision-sample.png` | Recognize sample text | Recognized `Apple Vision OCR Test 123` | ✓ |
| PDF OCR/text extraction | `./.build/debug/applevision /tmp/applevision-sample.pdf` | Recognize sample text from PDF | Recognized `Apple Vision OCR Test 123` | ✓ |
| Batch JSON output | `./.build/debug/applevision /tmp/applevision-samples --format json` | Emit structured OCR results | Returned JSON entries for sample PDF and PNG | ✓ |
| Structured JSON output | `./.build/debug/applevision /tmp/applevision-sample.png --format json` | Emit line-level OCR evidence | Returned `lines`, `candidates`, `confidence`, and `boundingBox` fields | ✓ |
| Verification report | `./.build/debug/applevision /tmp/applevision-sample.png --verification-report /tmp/applevision-review.txt` | Write separate review report without changing OCR output | Report created successfully; no suspicious lines found after heuristic tightening | ✓ |
| macOS app build | `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build` | App target should compile with review UI changes | Build succeeded | ✓ |

## Session: 2026-03-01 Apple Intelligence Review Integration

### Discovery
- Confirmed the existing review panel and `AppViewModel` are the right insertion point for explicit AI actions.
- Confirmed the local Xcode install uses `MacOSX26.2.sdk` while the app deployment target remains `macOS 13.0`.
- Typechecked small probe files against `FoundationModels` to confirm `SystemLanguageModel.default.availability`, `LanguageModelSession`, and structured `@Generable` responses are available.

### Current Work
- Adding an app-only Apple Intelligence suggestion service for flagged OCR lines.
- Keeping AI suggestions user-invoked with per-line and bulk buttons in the review panel.
- Preserving the current heuristic review and export flow as the default behavior.

### Implementation Complete
- Added `AppleIntelligenceReviewService.swift` in the macOS app target with runtime availability checks around `FoundationModels`.
- Added per-line Apple Intelligence requests, bulk flagged-line requests, and explicit apply actions in `AppViewModel`.
- Updated the review panel UI to show Apple Intelligence availability, request buttons, returned suggestions, and per-line error messages.
- Strengthened the Apple Intelligence request by adding neighboring OCR lines, a short document excerpt, and a second OCR pass on the cropped line image before sending the prompt.
- Verified the package still builds with `swift build`.
- Verified the macOS app still builds with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-01 Reviewed Document Translation

### Discovery
- The existing review flow already pauses before export and stores reviewed text in `reviewEdits`, making it the right point to add translation.
- The current export path already writes multiple output files from one reviewed result set, so a translated document can be emitted as one more sidecar file.

### Implementation Complete
- Added `AppleIntelligenceTranslationService.swift` to translate the fully reviewed document into a selected target language using Apple Intelligence.
- Added review-panel controls to optionally translate the reviewed document and choose a target language before export.
- Updated reviewed export so it writes the normal reviewed OCR files first and adds an extra translated file when translation succeeds.
- Kept translation non-blocking: if Apple Intelligence translation fails, the reviewed OCR files are still exported and the UI shows that translation was skipped.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-02 Layout Export Reversal

### Actions Taken
- Removed the experimental `markdown` and `html` export formats from the shared OCR model and CLI.
- Restored `OutputRenderer` to the prior plain-text and JSON behavior.
- Removed the app-side export format selector and restored `.txt` output writing.
- Reverted README changes that documented the experimental layout-preserving workflow.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-03-01 14:50 EST | `rg --files` exited 1 | 1 | Treated as empty directory, not a tool failure |
| 2026-03-01 15:05 EST | Parallel `swift run` lock on `.build` | 1 | Used the built binary for runtime checks instead of concurrent SwiftPM runs |
| 2026-03-01 15:08 EST | `git status` failed outside a repository | 1 | Treated as environment context; no git operations required |
| 2026-03-01 18:19 EST | Verifier flagged a clean sample line due to equal-confidence alternatives | 1 | Tightened the heuristic to require sub-0.98 primary confidence before flagging close alternatives |
| 2026-03-02 11:40 EST | Experimental layout-preserving export did not produce acceptable results | 1 | Removed the feature and restored the previous text-only export workflow |
| 2026-03-02 12:23 EST | Xcode app build could not see the new full-review source file | 1 | Moved the app-local review structs into `AppViewModel.swift`, which is already registered in the Xcode target |
| 2026-03-03 17:14 EST | First searchable-PDF verification compiled a top-level Swift script incorrectly | 1 | Wrapped the verification script in `@main` and reran it as an executable |
| 2026-03-03 17:16 EST | First boxed-line PDF text layer clipped the tail of a long string | 1 | Switched boxed-line drawing from a framed text block to scaled `CTLineDraw` output |

## Session: 2026-03-02 Translation Provider Expansion

### Discovery
- The user wants to keep Apple Translation for free local use, but add a better cloud option for people who can provide an API key.
- The current translation flow already runs after OCR review, so it is the right place to branch between local and cloud providers.
- OpenAI’s official docs currently recommend the Responses API for new work, making it the best starting point for an OpenAI translation backend.

### Current Work
- Adding a translation provider abstraction in the macOS app target.
- Keeping Apple Translation as the default option.
- Adding an OpenAI-backed provider with a user-entered API key.

### Implementation Complete
- Added a translation provider picker so reviewed document translation can use either Apple Translation or OpenAI.
- Added `OpenAITranslationService.swift` using the OpenAI Responses API for cloud translation.
- Added `OpenAIKeychainStore.swift` so the API key is stored in macOS Keychain instead of app defaults.
- Updated the review panel to show provider-specific controls and key management for OpenAI.
- Kept the Apple Translation path intact as the default local option.
- Added an OpenAI model picker with persisted model selection.
- Persisted the last-used translation provider and target language between launches.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-02 Structured Full-Document Review

### Discovery
- Confirmed the user wants a structured full-review flow after the warning/critical checkpoint, with page-by-page navigation and the source image beside editable OCR.
- Confirmed the current app state and UI are issue-first: only flagged lines are first-class editable items in the current review panel.
- Confirmed the OCR pipeline already retains enough page/line structure to support a richer review mode without changing OCR generation itself.
- Spawned parallel explorer agents to inspect review-state architecture and preview-rendering constraints before implementation.

### Implementation Complete
- Reframed the planning files around the new full-review feature.
- Replaced the old issue-only edit map with a full-document review state that tracks every page and every OCR line.
- Updated reviewed export to rebuild `OCRResult` values from the full-review state, so non-flagged edits are preserved on export.
- Extended `ReviewPreviewRenderer` with cached full-page preview rendering for both images and PDF pages.
- Reworked the review UI into a page-by-page split layout with page navigation, source preview, and line-by-line editing.
- Kept existing flagged-line helper actions and Apple Intelligence suggestion actions working as filtered actions over the new review state.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-02 Checkpoint Separation Planning

### Discovery
- The current implementation incorrectly mixes the warning/critical checkpoint with the full review workspace in one visual shell.
- The user wants those to be two clearly different steps, not one long screen.
- Parallel agents confirmed the best split is:
  - a compact flagged-only checkpoint
  - a dedicated full-review reading workspace

### Planning Complete
- Reframed the task plan around separating checkpoint mode from full review mode.
- Synthesized flow guidance and minimalist UI guidance into `findings.md`.
- Decided to keep one shared editable review state while changing the surrounding screen architecture.

### Implementation Complete
- Added an explicit `ReviewMode` so the app can switch cleanly between checkpoint and full review.
- Updated the workspace to hide the initial drop zone during active review sessions.
- Replaced the mixed review surface with:
  - a compact checkpoint card for flagged lines only
  - a dedicated wide full-review workspace for page-by-page editing
- Moved global AI and translation/export utilities into the checkpoint utility area so they no longer compete with the reading desk.
- Simplified full-review line presentation with subtler separators and flagged-line gutters instead of heavy card boxes for every line.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-03 Dual-Mode Full Review

### Discovery
- Confirmed the user wants full review to support two switchable page-scoped modes:
  - full-page image plus one full-page text editor
  - selected-line crop plus one selected-line editor
- Confirmed line review should be scoped to the current page’s lines only, not a document-wide line stream.
- Confirmed the existing checkpoint behavior should remain separate and should keep its cropped flagged-item previews.
- Confirmed the current renderer already has most of the crop math needed, but it only exposes crop rendering for flagged issues.

### Current Work
- Adding a `Page Review` / `Line Review` toggle inside the full-review workspace.
- Keeping `ReviewedLine` as the canonical review model while projecting page text as an editable aggregate.
- Adding a reusable zoom pattern for page and line previews.

### Implementation Complete
- Added a `FullReviewMode` state so the full-review workspace can switch cleanly between page-level and line-level review.
- Added page-scoped selected-line memory so each page remembers its current line in line review.

## Session: 2026-03-03 Searchable PDF Framing Fix

### Discovery
- Confirmed the visible export defects were framing defects, not text-layer placement defects:
  - some pages were clipped at the top
  - some pages showed extra blank space on the right
- Traced the issue to two renderer assumptions:
  - PDF pages were being drawn from raw page boxes without consistently normalizing non-zero origins
  - searchable PDF output could inherit an unintended canvas size when pages were assembled

### Implementation Complete
- Updated `OCRService.renderPDFPage` to normalize PDF page bounds from the preferred display box and translate by the source page origin before drawing.
- Exposed shared PDF page-bound helpers so export rendering and review preview rendering use the same framing logic.
- Updated `SearchablePDFRenderer` to:
  - normalize oriented image extents to a zero-origin canvas
  - use normalized PDF bounds for PDF-backed pages
  - render each page into its own exact-size PDF page before assembling the final searchable PDF
- Updated `ReviewPreviewRenderer` to use the same normalized PDF/image framing path as export rendering.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Additional Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| Swift package rebuild after framing changes | `swift build` | Core package should still compile | Build completed successfully | ✓ |
| macOS app rebuild after framing changes | `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build` | App target should still compile | Build succeeded | ✓ |

## Session: 2026-03-03 Arabic Searchable PDF Extraction Fix

### Discovery
- Confirmed the OCR/full-review text was correct before export, so the bug was in PDF text embedding rather than OCR review state.
- Local renderer probes showed that Quartz-generated Arabic extraction quality depends heavily on the chosen font.
- Identified that the final corruption was introduced by `PDFDocument.insert(...).dataRepresentation()` when assembling the final multi-page PDF, even when the single-page Quartz output extracted correctly.
- Reviewed OCRmyPDF renderer guidance and used it as a sanity check that naive searchable-text overlays are especially fragile for RTL text.

### Implementation Complete
- Updated `SearchablePDFRenderer` to add explicit RTL paragraph/writing-direction attributes for Arabic text runs.
- Switched Arabic text-layer generation away from the system Arabic fallback path and toward extraction-stable installed Arabic fonts, preferring `DecoTypeNaskh`.
- Reworked final searchable PDF assembly to write all pages in a single Quartz PDF context instead of rebuilding them through `PDFDocument` page insertion and serialization.
- Kept the rest of the app export flow intact.

### Verification
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.
- Ran a standalone searchable-PDF smoke test using `SearchablePDFRenderer.render(results:)` with a harakat-heavy Arabic line and confirmed `PDFPage.string` now contains the expected line.
- Ran an additional Arabic edge-case smoke test and confirmed the extracted text is substantially improved, with only minor combining-mark normalization remaining in the harsher sample.

## Session: 2026-03-04 Word-Level Searchable PDF Placement

### Discovery
- Confirmed the remaining selection mismatch was mainly a geometry-granularity problem: copyable text was correct, but highlight rectangles were still too coarse because the renderer mostly emitted one invisible text run per OCR line.
- Compared this against OCRmyPDF’s `hocr` renderer behavior and used that as the model for the next pass.
- Verified locally that naive separate Arabic word draw calls can scramble extraction order unless the words are emitted in geometric left-to-right order.

### Implementation Complete
- Added optional `OCRWord` geometry under `OCRLine` in the core OCR model.
- Extended `OCRService` to derive per-word bounding boxes from Vision’s top recognized candidate using `boundingBox(for:)`.
- Extended full-review export plumbing so word geometry survives reviewed export when a line is unchanged, and is cleared automatically when the line text is edited.
- Updated `SearchablePDFRenderer` to prefer word-level invisible text placement when word boxes are available, then fall back to the existing line-level placement or page-level fallback as needed.

### Verification
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.
- Ran a standalone smoke test using synthetic word boxes and confirmed:
  - Arabic word-level rendering extracts as `مخطط يوضح أقسام الكلام`
  - English word-level rendering extracts as `Sahih al-Bukhari`

## Session: 2026-03-03 Searchable PDF Text-Layer Fidelity

### Discovery
- Confirmed the loose/tall text highlight behavior was primarily caused by the old full-page invisible text-frame fallback used when page geometry was missing.
- Confirmed embedded-text PDF pages in `preferEmbeddedText` mode preserved text content but discarded layout geometry early in OCR processing.
- Confirmed reviewed export already had enough state to detect whether an embedded-text PDF page was actually edited before export.

### Implementation Complete
- Added page metadata to `OCRResult` so export can distinguish OCR-derived text from embedded PDF text and know when the original PDF text layer may be safely preserved.
- Updated OCR processing to mark embedded-text PDF pages as preservable originals and exposed a core helper to re-OCR rendered PDF pages for recovered line geometry.
- Updated reviewed export to:
  - preserve original embedded-text PDF pages when they were not edited
  - recover line geometry via OCR for edited embedded-text PDF pages
  - rebuild reviewed OCR lines with recovered or synthesized geometry before searchable export
- Reworked `SearchablePDFRenderer` to:
  - short-circuit untouched embedded-text PDF pages and insert the original `PDFPage`
  - remove the normal full-page invisible text-block fallback
  - use synthetic per-line placement when real boxes are missing
  - tighten line rectangles and baseline/font heuristics for less bulky selection behavior
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Additional Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| Embedded-text preserve branch | Standalone temp PDF with native drawn text | Exported page should keep original searchable text layer | `PDFPage.string` returned `ORIGINAL PDF TEXT` | ✓ |
| Synthetic line fallback branch | Image-backed page with lines but no bounding boxes | Exported page should still be searchable line-by-line | `PDFPage.string` returned `LINE ONE` and `LINE TWO` | ✓ |
- Added page-level text projection and write-back so one full-page editor updates the underlying reviewed lines used for export.
- Extended the preview renderer so full-review line mode can crop any reviewed line, not just flagged checkpoint issues.
- Reworked the full-review workspace into:
  - `Page Review`: full page preview plus one full-page text editor
  - `Line Review`: cropped line preview plus one selected-line editor with previous/next line navigation
- Added compact zoom controls to the page and line preview surfaces.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

### Verification Notes
- `swift build` passed immediately after the state and renderer changes.
- The first app build failed due to a malformed `HStack` in the new page preview card.
- After fixing that SwiftUI structure issue, the app build passed.
- I did not run an interactive visual walkthrough, so the remaining validation gap is hands-on feel for the page-editor typing experience and the zoom ergonomics.

### Follow-Up Correction
- The user reported that `Line Review` is not matching the intended workflow:
  - it only shows one inspected line at a time
  - the crop preview surface is much too large for compact line-by-line proofing
- The next pass will convert line review into a per-page list of compact cropped-line rows and tighten the crop sizing.

### Follow-Up Correction Complete
- Replaced the selected-line two-panel layout with a page-scoped list of compact line-review rows.
- Each row now shows a smaller cropped image preview on the left and the line editor/actions on the right.
- Tightened the toolbar segmented control so the `Review Mode` picker no longer wraps awkwardly.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

### Line Review Preview Upgrade Complete
- Enlarged the inline line-review crop previews from the compact tile to a larger `260x156` interactive preview surface.
- Refactored the shared zoom surface so it now supports configurable viewport sizing and compact controls.
- Added inline `-`, zoom percentage, `+`, and `Fit` controls to each line-review crop preview.
- Added mouse drag panning for zoomed images, with zoom clamping and fit reset behavior.
- Kept the page-scoped line-review list architecture intact while improving row spacing for the wider preview area.
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.

## Session: 2026-03-03 Searchable PDF MVP

### Discovery
- Read the `planning-with-files` skill because this change spans export models, UI, rendering, and verification.
- Read the `xcodebuildmcp` skill and used XcodeBuildMCP discovery/defaults before running builds.
- Spawned parallel explorer agents to inspect:
  - export architecture and payload flow
  - SwiftUI export-control placement
  - searchable-PDF data and geometry constraints
- Confirmed the current app export path was text-only and the safest MVP insertion point was `AppViewModel`.
- Confirmed annotation overlays are not enough for true searchable PDFs; the invisible text has to be written into the PDF content stream.

### Implementation Complete
- Added `DocumentExportChoice` to the shared core models.
- Added `SearchablePDFRenderer.swift` in `AppleVisionCore` to generate a combined searchable PDF from reviewed OCR results.
- Implemented two text-layer paths:
  - line-positioned invisible text for OCR-derived pages with bounding boxes
  - full-page invisible text blocks for pages without OCR geometry
- Updated `AppViewModel` so exports can now write text files, a searchable PDF, or both from the same reviewed result set.
- Generalized the app-side writer to handle mixed artifact types instead of only `.txt` outputs.
- Added a new sidebar `Export Format` section in the macOS app for `Text Files`, `Searchable PDF`, and `Both`.
- Updated generated-file rows and README copy to reflect PDF output.

### Verification
- Rebuilt with `swift build`.
- Rebuilt with `xcodebuild -project AppleVisionApp.xcodeproj -scheme AppleVisionApp -configuration Debug build`.
- Compiled and ran a local Swift verification executable that generated `/tmp/applevision-searchable-mvp.pdf`; `PDFPage.string` returned `HELLO OCR MVP` and `findString` returned 1 hit.
- Compiled and ran a second local Swift verification executable that generated `/tmp/applevision-searchable-fallback.pdf` with no OCR bounding boxes; `PDFPage.string` returned the fallback page text and `findString` returned 1 hit.
- I did not run an interactive click-through of the macOS app export buttons, so the remaining gap is a hands-on UI smoke test for `Text Files` and `Both`.

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Phase 5 |
| Where am I going? | Delivery of the searchable-PDF MVP and any follow-up polish |
| What's the goal? | Add `Text Files`, `Searchable PDF`, and `Both` export choices to the macOS app while preserving the reviewed export flow |
| What have I learned? | The hard part was PDF writing, not OCR; the existing OCR results already had enough structure for a real text layer on OCR-derived pages |
| What have I done? | Added a searchable PDF renderer, export-choice plumbing, app UI controls, and runtime verification for both line-box and fallback page-text paths |

---
*Update after completing each phase or encountering errors*
