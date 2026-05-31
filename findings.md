# Findings & Decisions

## Requirements
- Batch OCR multiple local image files without manual copy/paste.
- Use Apple's recognition stack, not a third-party OCR engine.
- Prefer a local macOS workflow the user can run from Terminal or Xcode.
- Produce output that is easy to save, inspect, or redirect.

## Research Findings
- The workspace is empty, so the tool needs to be created from scratch.
- Apple's public surface for this is Vision text recognition rather than a separate public Live Text batch API.
- Apple documents `VNRecognizeTextRequest` in Vision as the supported OCR request for extracting text from images.
- Apple documents VisionKit image analysis and Live Text interactions separately; that is closer to the Preview-style UI experience, but it is not the best fit for headless batch export.
- PDF input can still be supported by rendering each PDF page to an image on macOS and then sending those images through Vision OCR.
- `PDFPage.string` can extract existing selectable PDF text directly, so OCR should be a fallback for scanned pages rather than the first step.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Use Swift Package Manager for the CLI | Simpler than bootstrapping an Xcode project in an empty repo |
| Use `VNRecognizeTextRequest` instead of VisionKit UI analysis | Suitable for headless batch extraction from the command line |
| Prefer `PDFPage.string` before OCR | Avoids unnecessary OCR work on text PDFs |
| Keep top OCR candidates, confidence, and bounding boxes per line | Gives a later verifier evidence instead of only final flattened text |
| Preserve current plain-text output while enriching JSON/in-memory results | Avoids breaking current user workflows |
| Add a heuristic review service before any LLM integration | Useful review suggestions can be generated locally from OCR evidence alone |
| Keep verifier output as a sidecar report instead of rewriting OCR text | Makes the feature safe and opt-in |
| Keep Foundation Models in the app target only | Prevents the CLI/core package from depending on Apple Intelligence availability |
| Use explicit per-line and bulk review actions for AI | Matches the requirement to keep AI user-invoked instead of automatic |
| Run translation after the review step, not during OCR | The user wants verification first, then optional whole-document translation |
| Write translated output as an extra exported file | Preserves the reviewed OCR files and avoids mixing source text with translation |
| Keep Apple Translation as one provider among several | Local/offline translation is still valuable even if cloud quality is better |
| Use a provider abstraction for translation | Lets the review/export workflow stay stable while providers change underneath |
| Start cloud support with OpenAI using a user-supplied API key | Matches the immediate user need without overbuilding a generic provider matrix first |
| Store the OpenAI API key in macOS Keychain | Native and safer than persisting secrets in defaults or app files |
| Persist the last-used translation provider, target language, and OpenAI model in app preferences | Improves repeat use without storing secrets outside Keychain |
| Normalize PDF page bounds to a zero-origin crop/media box before rasterizing or exporting searchable pages | Prevents page content from being shifted, clipped, or padded when the source PDF page box does not start at `(0, 0)` |
| Render each searchable PDF page into its own exact-size PDF page before assembling the final document | Avoids implicit default page sizes introducing extra whitespace on image-backed or mixed-dimension exports |
| Preserve original PDF pages for unedited embedded-text export pages | Avoids rebuilding a text layer unnecessarily and preserves native selection behavior when the user never changed the page |
| Regenerate layout geometry for edited embedded-text PDF pages via OCR of the rendered page | Fits the current architecture better than introducing a new native PDF text-position extraction pipeline |
| Replace the old full-page invisible text block with synthetic per-line placement | Produces tighter and more predictable text selection/highlight behavior when real geometry is missing |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| `rg --files` returned exit code 1 in an empty workspace | Confirmed the directory is empty and proceeded with scaffolding |
| Parallel `swift run` processes contended on the shared `.build` directory | Switched runtime verification to the built binary for repeatable tests |
| `git status` failed | Confirmed the workspace is not initialized as a git repository |
| Searchable PDF export showed top cropping and right-side whitespace on some pages | Normalized page/image bounds and switched searchable PDF generation to exact per-page canvases before assembly |
| Searchable PDF selection highlights looked too tall/loose on some pages | Removed the page-wide text-frame fallback and moved to preserved original PDF text or line-aware placement instead |

## Resources
- /Users/thiernodiallo/.codex/skills/public/xcodebuildmcp/SKILL.md
- /Users/thiernodiallo/.codex/skills/planning-with-files/SKILL.md
- Apple Vision `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- Apple VisionKit image analysis overview: https://developer.apple.com/documentation/visionkit/imageanalysisinteraction
- Local SDK probe: `FoundationModels` is present in `MacOSX26.2.sdk`, and `LanguageModelSession` plus `SystemLanguageModel.default.availability` typecheck successfully against the installed toolchain.
- The current app export path already centralizes reviewed output writing in `AppViewModel.exportPendingOutputs()`, so translation can be added there without changing OCR core models.
- The current app export path also makes it straightforward to add a provider picker and defer translation execution to the selected backend.
- OpenAI’s current docs recommend the Responses API for new applications, which is the right cloud entry point for a translation provider. Source: https://platform.openai.com/docs/api-reference/responses
- A simple `Security`-based Keychain wrapper is sufficient for this app; app-local key storage does not require extra keychain-sharing entitlements.
- OCRmyPDF’s docs explicitly call out that the older sandwich renderer has poor RTL support and Preview selection issues, while the newer `fpdf2` renderer improves multilingual and RTL text-layer behavior. Sources: https://ocrmypdf.readthedocs.io/en/stable/advanced.html and https://github.com/ocrmypdf/OCRmyPDF/issues/1157

## Arabic Searchable PDF Discovery: 2026-03-03
- The reviewed OCR text was already correct in memory; corruption happened when copying text back out of the exported PDF, so the defect was in PDF text-layer generation/serialization.
- Quartz/Core Text PDF generation is highly font-sensitive for Arabic extraction. Local probes showed:
  - system `.SFArabic`-style fallback produced mangled extraction
  - several older installed Arabic fonts produced much better extraction
  - `DecoTypeNaskh` gave the best round-trip results among tested built-in fonts
- The biggest corruption step was not line drawing itself; a single page generated directly by Quartz extracted correctly, but the text was corrupted after round-tripping that page through `PDFDocument.insert(...).dataRepresentation()` to assemble the final document.
- The current renderer fix therefore does three things:
  - prefers extraction-stable Arabic fonts for Arabic runs
  - keeps explicit RTL paragraph and writing-direction metadata
  - writes the final searchable PDF in one Quartz pass instead of page-by-page PDFKit reassembly
- Residual limitation: some harakat-heavy edge cases still normalize combining marks on extraction (`ٱللّٰهِ` vs `ٱللّٰهِ`-style reordering), but this is substantially closer than the previous scrambled output.

## Word-Level Searchable PDF Discovery: 2026-03-04
- OCRmyPDF’s `hocr` renderer uses word-granularity placement inside a line transform, which is a closer match for natural PDF selection than one coarse full-line box.
- Local probes showed that naive separate word draw calls can break Arabic extraction order if emitted in logical word order; for Arabic, the renderer must draw word runs in geometric left-to-right order to preserve correct extracted line order.
- Vision can provide per-word geometry without changing OCR frameworks: `VNRecognizedText.boundingBox(for:)` is enough to derive word boxes from the top candidate string.
- The safest compatibility shape for this app is additive:
  - keep `OCRResult -> OCRLine` as-is
  - add optional `OCRWord` geometry under `OCRLine`
  - preserve it through review/export only when the edited line text still matches the original OCR text
- Embedded-text PDF pages still do not have word geometry in the current pipeline, so they continue to use the existing line/block fallback path.

## Visual/Browser Findings
- Official Apple docs separate Vision OCR from VisionKit Live Text UI APIs.

## Full-Review Discovery: 2026-03-02
- The current app review experience is issue-first: it only pauses before export when suspicious lines exist, then renders a list of `OCRReviewIssue` rows with per-line edits and export actions.
- `OCRResult` already stores `sourcePath`, `pageNumber`, and a full `[OCRLine]` array, so the OCR pipeline already has the page-by-page structure needed for a fuller review mode.
- `OCRReviewIssue` ids are derived from `sourcePath`, `pageNumber`, and `lineIndex`, which works for flagged lines but is not a complete edit model for full-document review.
- `AppViewModel.reviewEdits` is currently initialized only from flagged issues and later applied back to results by matching against `payload.reviewIssues`; this means unflagged lines are not currently editable in the export pipeline.
- `ReviewPreviewRenderer` already knows how to render PDF pages and oriented images, but its public API currently returns cropped images for flagged lines; full-page review should likely expand that renderer instead of creating a second rendering path.
- The current review panel is centered around `reviewPanel(_:)` and `reviewIssueRow(_:)` in `ContentView`, so adding a second review surface is more natural than overloading the flagged-list layout with page navigation.

## Emerging Technical Direction
| Decision | Rationale |
|----------|-----------|
| Add a dedicated full-review state alongside flagged review data | Keeps the quick issue summary intact while enabling full-document editing |
| Key review edits by page/line identity rather than issue existence | Full review must cover all OCR lines, including clean ones |
| Reuse the current OCR result set as the source of truth | Avoids re-running OCR or creating duplicate export models |
| Extend `ReviewPreviewRenderer` to return full-page images | Keeps image/PDF rendering behavior consistent across issue preview and full review |
| Start with page preview plus structured line editor, not line overlay interactions | Delivers the requested flow sooner and avoids premature geometry-heavy UI work |
| Keep the flagged review summary actions, but make full-document review the canonical edit surface | Lets users move fast on suspicious lines without maintaining two separate edit systems |
| Store the new review types inside an existing app target source file | The Xcode project currently compiles an explicit list of app files, so this avoids immediate project-file maintenance |

## Checkpoint Separation Plan: 2026-03-02

### Interface-Design Synthesis
- The real product problem is not missing functionality; it is that the checkpoint and the reading workspace were visually and structurally collapsed into one surface.
- The right mental model is a two-gate review flow:
  - `Checkpoint Review`
  - `Full Review Workspace`
- The checkpoint should answer: "Are the suspicious lines acceptable?"
- The full review workspace should answer: "Is the whole document ready to export?"

### Domain Exploration
- proofing
- redlining
- page turns
- source vs transcription
- triage
- approval gate
- margin notes
- reading desk

### Color World
- off-black reading table
- warm paper white
- graphite text
- muted amber warning marks
- restrained crimson for critical issues
- cool steel-gray dividers
- faint blue focus ring

### Signature
- A proof-stage layout: a compact centered checkpoint card before entering a dedicated reading desk.

### Defaults To Reject
| Default | Replace With |
|---------|--------------|
| One giant review screen with every control visible | Two explicit modes with different responsibilities |
| Same card treatment for checkpoint and full review | Narrow checkpoint card plus wide reading workspace |
| Equal visual weight for settings, warnings, preview, and editor | One primary action area per mode with utilities visually recessed |

### Concrete Screen Split
| Mode | Purpose | Must Include | Must Exclude |
|------|---------|--------------|--------------|
| Checkpoint Review | Triage flagged OCR risk fast | severity counts, flagged lines only, quick suggestion actions, `Continue to Full Review`, `Export Now` | full-page preview, full document line list, reading-desk navigation |
| Full Review Workspace | Review and edit the whole document page by page | source page, editable OCR for current page, previous/next navigation, back to checkpoint, export | flagged summary card, bulk triage actions as dominant controls, long checkpoint messaging |

### Shared-State Decision
- Keep one canonical mutable review state for all lines and pages.
- Derive checkpoint rows from flagged lines in that shared state.
- Derive full review from the current page in that shared state.
- Export always uses the shared review state, regardless of which mode last made the edits.

### Minimalist UI Guidance
- Checkpoint should feel like a decision card, not a dashboard.
- Full review should feel like a reading desk, not a stack of cards.
- Translation controls, AI availability messaging, confidence values, and source paths should be visually quiet.
- Severity counts, current mode, current page, and the primary action for the current mode should carry emphasis.
- Use a real mode switch, not conditional sections inside the same card shell. If both modes look similar at a glance, the separation is insufficient.

### Implemented Fix Direction
- Add `ReviewMode` in app state so the UI can explicitly switch between `checkpoint` and `fullReview`.
- Keep the shared reviewed document state untouched so edits persist across both modes.
- Show only the checkpoint card when flagged review is active.
- Show only the full reading workspace when full review is active.
- Hide the large drop zone while a review session is active so the workspace feels intentional.
- Reduce full-review row chrome by using subtle separators and a slim severity gutter instead of heavy card boxes on every line.

## Dual-Mode Full Review: 2026-03-03

### Confirmed User Intent
- The user wants the full review workspace to support two switchable review styles on the current page:
  - `Page Review`: full page image on the left, one large text editor for the entire current page on the right
  - `Line Review`: cropped image for the selected line on the left, one line editor for the selected line on the right
- `Line Review` is page-scoped, not document-global. Changing pages should switch to that page’s own lines and crops.
- The checkpoint must stay separate and keep its cropped flagged-item previews.
- The full review workspace should also gain image zoom for inspection.

### State And Data Findings
- The current `FullDocumentReviewState` already holds the right canonical structure: pages containing reviewed lines with OCR evidence and optional issues.
- The current export pipeline rebuilds `OCRResult` values from `ReviewedLine.editedText`, so preserving per-line state is the safest path.
- The current UI only supports line-by-line editing in full review; there is no page-level projection/editor yet.
- Because AI suggestions and flagged issue actions already address lines by `line.id`, adding a second text model for pages would create unnecessary synchronization risk.

### Recommended State Strategy
| Need | Recommendation | Why |
|------|----------------|-----|
| Full-review sub-mode | Add a `FullReviewMode` enum with `page` and `line` | Keeps the workspace explicit and simple to branch in SwiftUI |
| Selected line in line review | Store selected line index per page, not globally | Prevents page-to-page line navigation from feeling broken |
| Page editor | Expose a computed page text getter/setter that reads and writes the current page’s lines | Keeps `ReviewedLine` as the only true editable model |
| Page text splitting | Use newline splitting when saving page text back to lines and preserve order | Aligns with current OCR text structure and export behavior |
| Crop rendering | Add renderer support for `ReviewedLine` crop previews, not just `OCRReviewIssue` | Needed for non-flagged line review rows |

### Interface-Design Synthesis
- Human: someone proofreading OCR carefully before export.
- Task: move between pages, inspect text precisely, and correct either the whole page or one line at a time.
- Feel: calm, editorial, minimal, like a proofing desk rather than a settings panel.

### Domain
- proof sheet
- crop mark
- margin inspection
- line slug
- page turn
- source versus transcription

### Color World
- dark reading table
- warm paper
- graphite ink
- soft red correction marks
- amber caution tabs
- muted steel dividers

### Signature
- A review desk that can “zoom in” from page view to line-snip view without leaving the current page.

### Defaults To Reject
| Default | Replace With |
|---------|--------------|
| Two unrelated screens for page and line review | One workspace with a calm segmented toggle |
| Dense list of every line even in line-review mode | Single selected line inspection with purposeful navigation |
| Separate floating zoom UI for every image type | One compact zoom control pattern reused in both review modes |

### UI Component Guidance
- Put the `Page Review` / `Line Review` toggle in the full-review toolbar near the page navigation, not buried in the editor card.
- In `Page Review`, keep the current two-pane balance but simplify the right pane to one large editor plus a small metadata strip.
- In `Line Review`, use the left pane as a fixed crop inspection stage and the right pane as a focused single-line editor with line navigation, OCR/source context, and issue actions.
- Keep page chips visible in both modes so the user always knows they are still working on a page.
- Zoom controls should be small stepper-style controls or plus/minus buttons anchored to the preview header, not giant floating overlays.

### Likely Edge Cases
- Some PDF-text-derived lines may not have a bounding box. Line review should show a graceful fallback state when a crop is unavailable.
- If page-level editing changes the number of lines, line review behavior must still remain stable. The safest first pass is to remap lines by newline order and create replacement `ReviewedLine` values as needed while preserving existing issue metadata where possible by index.

## Line Review Course Correction: 2026-03-03
- The shipped `Line Review` mode is too literal: it behaves like one selected-line inspector with a large preview stage.
- The user actually wants `Line Review` to stay page-scoped but list every line on that page, each with:
  - a compact cropped preview
  - the OCR text
  - the editable export field
- This should feel like a denser proof sheet, not a two-panel gallery.
- The oversized crop stage should be replaced by smaller inline crops similar to the checkpoint pattern, but visually lighter and more compact.
- The toolbar’s segmented control should also be labels-hidden so the control does not wrap awkwardly.

---

## Searchable PDF MVP: 2026-03-03

### Architecture Findings
- The current export workflow is centralized in `AppViewModel.processDroppedItems()` and `AppViewModel.exportPendingOutputs()`, so the MVP can be added without restructuring OCR or review.
- `ArabicOutputMode` already controls text-variant output, so searchable PDF should be modeled as a second export dimension, not a replacement for text output selection.
- `PendingExportPayload` is the right place to capture export settings through the review checkpoint so reviewed export matches the sidebar choices made before OCR.

### PDF Layer Findings
- A `PDFAnnotation` overlay is not enough for true searchable export: local proof showed annotation text did not surface through `PDFPage.string` or `findString`.
- Drawing invisible text into the actual PDF content stream does produce searchable/selectable text.
- OCR-derived lines already have normalized bounding boxes, which is enough to place invisible text back onto image inputs and OCR-rendered PDF pages.
- Pages created from `PDFPage.string` do not retain geometry in the current OCR pipeline, so they need a fallback strategy rather than line-perfect placement.

### MVP Decisions
| Decision | Rationale |
|----------|-----------|
| Add `DocumentExportChoice` in shared core models | Keeps app UI and export logic aligned around one source of truth |
| Keep searchable PDF as an app export feature while leaving the CLI unchanged | The request is centered on the reviewed desktop export flow |
| Generate one combined `*_searchable.pdf` | Matches the current combined reviewed-output mental model |
| Keep `outputMode` text-only | Avoids unexpectedly multiplying PDF outputs when `Both Versions` is selected |
| Use line-positioned invisible text when bounding boxes exist | Gives the best search/select fidelity for OCR-derived pages |
| Use a full-page invisible text block when boxes do not exist | Provides a safe searchable fallback for embedded-text PDF pages and reviewed edits |

### Verification Findings
- A synthetic image-backed PDF generated through the new renderer exposed the full hidden string through `PDFPage.string` and `findString`.
- The no-bounding-box fallback path also produced searchable text, confirming the MVP works for page-level fallback text blocks as well as line-placed OCR text.
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*
