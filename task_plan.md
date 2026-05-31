# Task Plan: Searchable PDF Export MVP

## Goal
Add an MVP export flow with three user-facing choices: text files, searchable PDF, or both, while preserving the current reviewed-text export flow and keeping the generated PDF actually searchable/selectable.

## Current Phase
Phase 6

## Phases

### Phase 1: Requirements & Discovery
- [x] Confirm current export architecture and UI insertion points
- [x] Confirm the minimum viable searchable-PDF strategy for images, OCR’d PDFs, and text PDFs
- [x] Capture implementation risks and constraints in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Define the new export choice model and where it should live
- [x] Decide how text outputs and PDF outputs should coexist in one export pass
- [x] Decide how to treat PDFs with existing embedded text versus reviewed OCR text
- **Status:** complete

### Phase 3: Implementation
- [x] Add a searchable PDF renderer/writer path
- [x] Add export-choice state and payload plumbing
- [x] Update the app export workflow to write text, searchable PDF, or both
- [x] Add sidebar and review-surface controls for the new export choice
- [x] Keep current text export, Arabic variants, review, and translation behavior intact
- **Status:** complete

### Phase 4: Testing & Verification
- [x] Build the Swift package successfully
- [x] Build the macOS app target successfully
- [x] Confirm text-only export still uses the existing `.txt` renderer/writer path
- [x] Verify searchable PDF export writes a `.pdf` that is searchable/selectable
- [x] Confirm the `Both` path is wired to emit both text output and searchable PDF artifacts
- [x] Document test results in progress.md
- **Status:** complete

### Phase 5: Delivery
- [x] Review changed files
- [x] Summarize implementation, tradeoffs, and remaining risks
- [ ] Deliver to user
- **Status:** in_progress

### Phase 6: Text Layer Fidelity
- [ ] Replace the full-page invisible text fallback with line-aware fallback placement
- [ ] Preserve original PDF page/text behavior for unedited embedded-text PDF pages
- [ ] Regenerate line geometry for edited embedded-text PDF pages before searchable export
- [ ] Verify `swift build` and app build after the text-layer changes
- [ ] Document the new tradeoffs and residual risks in findings.md/progress.md
- **Status:** in_progress

## Key Questions
1. What is the smallest export-model change that supports `Text`, `Searchable PDF`, and `Both` without destabilizing review/export?
2. How should the searchable-PDF writer handle pages that already have embedded PDF text?
3. What should the first MVP do when page geometry is missing for reviewed text lines?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Keep the current text export as-is | The user explicitly wants text export preserved |
| Add a second export dimension for deliverable type | Arabic output mode already controls text variants, so searchable PDF should not replace that |
| Treat searchable PDF as an app-export feature first | The current request is centered on the app workflow and reviewed export path |
| Target a true searchable PDF, not a PDF annotation overlay | Local proof showed annotations are not searchable via `PDFPage.string`/`findString` |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| `git status` failed because the workspace is not a git repository | 1 | Proceed without git-based diff/status workflows |

## Notes
- The current app export path is centralized in `AppViewModel.exportPendingOutputs()`, which is the right integration point for the MVP.
- The current output writer only writes `.txt` files, so searchable PDF needs a sibling export path rather than a small tweak.
- The MVP should favor correctness and searchability over layout-perfect text placement for every edge case.
- Pages with OCR bounding boxes now get line-positioned invisible text, while pages without geometry fall back to a full-page invisible text block.
- The next pass should phase out the full-page invisible text block because it produces loose/high “fat” selection highlights, especially on embedded-text PDF pages that lost geometry.
- Arabic copy/paste corruption turned out to be a renderer/assembly problem, not an OCR review-state problem.
- The current fix direction is:
  - use Arabic-friendly extraction fonts instead of the system `.SFArabic` path
  - keep explicit RTL paragraph metadata for Arabic runs
  - avoid `PDFDocument.insert(...).dataRepresentation()` for final assembly because it mutates Arabic extraction
- The current selection-geometry fix direction is:
  - keep the existing line-level contract intact
  - add optional word boxes under each OCR line when Vision provides them
  - preserve word geometry through reviewed export only when the line text is unchanged
  - prefer word-level placement in the searchable PDF renderer and fall back to line-level placement otherwise
