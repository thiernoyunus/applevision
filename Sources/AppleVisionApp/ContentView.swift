import AppleVisionCore
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isTargeted = false

    private var statusStyle: ViewStatusStyle {
        if viewModel.isProcessing {
            return .processing
        }

        let message = viewModel.statusMessage.lowercased()
        if message.contains("completed") || message.contains("saved") {
            return .success
        }
        if message.contains("unable") || message.contains("failed") || message.contains("error") {
            return .error
        }
        if !viewModel.droppedURLs.isEmpty {
            return .ready
        }
        return .idle
    }

    private var droppedSummary: String {
        let names = viewModel.droppedURLs.map(\.lastPathComponent)
        guard !names.isEmpty else {
            return "Images, PDFs, and folders supported"
        }
        if names.count <= 2 {
            return names.joined(separator: " | ")
        }
        return "\(names.prefix(2).joined(separator: " | ")) + \(names.count - 2) more"
    }

    var body: some View {
        translationManagedContent {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    sidebar
                    Divider().opacity(0.5)
                    workspace
                }
                footerBar
            }
        }
        .background(windowBackground)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 640, idealHeight: 700)
        .animation(.easeInOut(duration: 0.18), value: isTargeted)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isProcessing)
        .animation(.easeInOut(duration: 0.18), value: viewModel.generatedFiles)
        .task {
            await viewModel.refreshTranslationAvailability()
        }
        .onChange(of: viewModel.translationTarget) { _ in
            Task {
                await viewModel.refreshTranslationAvailability()
            }
        }
        .onChange(of: viewModel.translationProvider) { _ in
            Task {
                await viewModel.refreshTranslationAvailability()
            }
        }
    }

    @ViewBuilder
    private func translationManagedContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
#if canImport(Translation)
        if #available(macOS 15.0, *) {
            content()
                .modifier(
                    ReviewedTranslationTaskModifier(
                        descriptor: viewModel.pendingTranslationConfiguration,
                        sourceText: viewModel.pendingTranslationText,
                        onSuccess: { translatedText in
                            viewModel.finishPendingTranslation(with: translatedText)
                        },
                        onFailure: { error in
                            viewModel.failPendingTranslation(with: error)
                        }
                    )
                )
        } else {
            content()
        }
#else
        content()
#endif
    }

    private var windowBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.12),
                    Color(red: 0.05, green: 0.07, blue: 0.14),
                    Color.black.opacity(0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    sidebarSection(title: "Output Mode", footnote: "Choose which Arabic text variant to write when text files are included.") {
                        modeOptionRow(
                            title: "Both Versions",
                            subtitle: "With harakat and without harakat",
                            symbol: "square.grid.2x2",
                            isSelected: viewModel.outputMode == .both
                        ) {
                            viewModel.outputMode = .both
                        }
                        modeOptionRow(
                            title: "With Harakat",
                            subtitle: "Keep vowel marks in the output",
                            symbol: "text.line.first.and.arrowtriangle.forward",
                            isSelected: viewModel.outputMode == .withHarakat
                        ) {
                            viewModel.outputMode = .withHarakat
                        }
                        modeOptionRow(
                            title: "Without Harakat",
                            subtitle: "Remove vowel marks after OCR",
                            symbol: "eye.slash",
                            isSelected: viewModel.outputMode == .withoutHarakat
                        ) {
                            viewModel.outputMode = .withoutHarakat
                        }
                    }

                    sidebarSection(title: "Export Format", footnote: "Choose whether to write text files, a searchable PDF, or both.") {
                        modeOptionRow(
                            title: "Text Files",
                            subtitle: "Write the current `.txt` exports only",
                            symbol: "doc.text",
                            isSelected: viewModel.exportChoice == .text
                        ) {
                            viewModel.exportChoice = .text
                        }
                        modeOptionRow(
                            title: "Searchable PDF",
                            subtitle: "Write one searchable PDF with embedded text",
                            symbol: "doc.richtext",
                            isSelected: viewModel.exportChoice == .searchablePDF
                        ) {
                            viewModel.exportChoice = .searchablePDF
                        }
                        modeOptionRow(
                            title: "Both",
                            subtitle: "Write the text files and the searchable PDF",
                            symbol: "square.stack.3d.up",
                            isSelected: viewModel.exportChoice == .both
                        ) {
                            viewModel.exportChoice = .both
                        }
                    }

                    sidebarSection(title: "PDF Handling", footnote: "Force OCR when a PDF's text layer is unreliable.") {
                        modeOptionRow(
                            title: "Prefer PDF Text",
                            subtitle: "Use embedded text first when available",
                            symbol: "doc.text",
                            isSelected: viewModel.pdfTextMode == .preferEmbeddedText
                        ) {
                            viewModel.pdfTextMode = .preferEmbeddedText
                        }
                        modeOptionRow(
                            title: "Force OCR",
                            subtitle: "Render each PDF page and OCR the image",
                            symbol: "exclamationmark.circle",
                            isSelected: viewModel.pdfTextMode == .ocrOnly
                        ) {
                            viewModel.pdfTextMode = .ocrOnly
                        }
                    }

                    sidebarSection(title: "Review Checkpoint", footnote: "Pause before export when OCR finds risky lines.") {
                        Toggle(isOn: $viewModel.reviewBeforeExport) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Review Low-Confidence Lines")
                                Text("Show suspicious lines and suggested fixes before writing files")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    outputFolderSection
                }
                .padding(18)
            }

            Spacer(minLength: 0)

            sidebarActions
        }
        .frame(width: 320)
        .background(.ultraThinMaterial.opacity(0.78))
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AppleVision OCR")
                .font(.system(size: 26, weight: .semibold))

            Text("Native OCR utility for images and PDFs")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private func sidebarSection<Content: View>(title: String, footnote: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(sidebarPanelFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func modeOptionRow(title: String, subtitle: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                SelectionPill(isSelected: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var outputFolderSection: some View {
        sidebarSection(title: "Output Folder", footnote: "Generated text files and PDFs are written in this folder.") {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.outputDirectory.path)
                    .textSelection(.enabled)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Choose Folder") {
                    viewModel.chooseOutputDirectory()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var sidebarActions: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.35)

            Button {
                viewModel.processDroppedItems()
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isProcessing || viewModel.droppedURLs.isEmpty)

            Button("Open Output Folder") {
                viewModel.openOutputDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button("Open Logs") {
                viewModel.openLogs()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(.regularMaterial.opacity(0.76))
    }

    private var workspace: some View {
        ZStack {
            workspaceBackground

            if viewModel.hasPendingExport,
               let report = viewModel.reviewReport,
               !report.issues.isEmpty {
                Group {
                    if viewModel.isFullReviewActive {
                        fullReviewWorkspace
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 22) {
                                checkpointReviewPanel(report)
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        dropZone

                        if !viewModel.generatedFiles.isEmpty {
                            generatedFilesPanel
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var workspaceBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.clear,
                    Color.black.opacity(0.25),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(.black.opacity(0.12))
        }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: viewModel.isProcessing ? "waveform.path.ecg" : "doc.text.viewfinder")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.85))

            VStack(spacing: 10) {
                Text(viewModel.isProcessing ? "Processing Files" : "Drop Files or Folders Here")
                    .font(.system(size: 23, weight: .semibold))

                Text(viewModel.isProcessing ? processingSubtitle : droppedSummary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if viewModel.isProcessing {
                VStack(spacing: 10) {
                    ProgressView(value: viewModel.progressValue)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(maxWidth: 360)

                    HStack(spacing: 12) {
                        Text("\(viewModel.completedUnitCount) / \(max(viewModel.totalUnitCount, 1))")
                        if let estimate = viewModel.estimatedTimeRemaining {
                            Text(estimate)
                        } else {
                            Text("Estimating remaining time...")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } else if !viewModel.droppedURLs.isEmpty {
                Label("\(viewModel.droppedURLs.count) item\(viewModel.droppedURLs.count == 1 ? "" : "s") ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 720)
        .frame(height: 390)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(isTargeted ? 0.24 : 0.12), lineWidth: isTargeted ? 1.6 : 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 22, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .padding(20)
        )
        .scaleEffect(isTargeted ? 1.01 : 1)
        .opacity(viewModel.isProcessing ? 0.98 : 1)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    private var processingSubtitle: String {
        if let label = viewModel.currentProcessingLabel {
            return label
        }
        return "OCR is running with Arabic defaults."
    }

    private var buttonTitle: String {
        if viewModel.isProcessing {
            return "Processing..."
        }
        if viewModel.hasPendingExport {
            return "Export Files"
        }
        return "Process Files"
    }

    private var generatedFilesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Generated Files")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.generatedFiles.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.generatedFiles, id: \.path) { fileURL in
                    generatedFileRow(fileURL)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func generatedFileRow(_ fileURL: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: fileURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(fileURL.lastPathComponent)
                    .font(.callout.weight(.medium))
                Text(fileURL.path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let tag = generatedFileTag(for: fileURL) {
                Text(tag)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func generatedFileTag(for fileURL: URL) -> String? {
        let name = fileURL.lastPathComponent.lowercased()
        if fileURL.pathExtension.lowercased() == "pdf" {
            return "Searchable PDF"
        }
        if name.contains("with_harakat") {
            return "With Harakat"
        }
        if name.contains("without_harakat") {
            return "Without Harakat"
        }
        if name.contains("translated_english") {
            return "Translated: English"
        }
        if name.contains("translated_french") {
            return "Translated: French"
        }
        if name.contains("translated_spanish") {
            return "Translated: Spanish"
        }
        if name.contains("translated_german") {
            return "Translated: German"
        }
        return nil
    }

    private func checkpointReviewPanel(_ report: OCRReviewReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review Checkpoint")
                        .font(.headline)
                    Text("Check the suspicious lines first, then either export now or continue into the full reading desk for page-by-page review.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.hasPendingExport {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            pageCountBadge(title: "Critical", count: report.criticalCount, color: Color.red.opacity(0.9))
                            pageCountBadge(title: "Warnings", count: report.warningCount, color: Color.orange.opacity(0.9))
                            pageCountBadge(title: "Pages", count: affectedPageCount(report), color: .secondary)
                        }

                        HStack(spacing: 8) {
                            Button("Use All Suggestions") {
                                viewModel.useSuggestedTextForAll()
                            }
                            .buttonStyle(.bordered)

                            Button("Use Critical Only") {
                                viewModel.useSuggestedTextForCritical()
                            }
                            .buttonStyle(.bordered)

                            Button("Jump to First Flagged") {
                                viewModel.jumpToFirstFlaggedReviewPage()
                            }
                            .buttonStyle(.bordered)

                            Button("Restore All OCR") {
                                viewModel.restoreAllOCRText()
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            Button("Export Now") {
                                viewModel.exportPendingOutputs()
                            }
                            .buttonStyle(.bordered)

                            Button("Continue To Full Review") {
                                viewModel.openFullReview()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(report.issues) { issue in
                    checkpointIssueRow(issue)
                }
            }

            checkpointUtilitiesPanel
        }
        .padding(18)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var fullReviewWorkspace: some View {
        Group {
            if let fullReviewState = viewModel.fullReviewState,
               let selectedPage = viewModel.selectedReviewPage {
                VStack(alignment: .leading, spacing: 18) {
                    fullReviewToolbar(fullReviewState: fullReviewState, selectedPage: selectedPage)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(fullReviewState.pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    viewModel.selectReviewPage(index: index)
                                } label: {
                                    reviewPageChip(
                                        page: page,
                                        index: index,
                                        isSelected: index == fullReviewState.selectedPageIndex
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 28)
                    }

                    fullReviewWorkspaceBody(selectedPage)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.top, 24)
            }
        }
    }

    private func fullReviewToolbar(fullReviewState: FullDocumentReviewState, selectedPage: ReviewedPage) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Full Review Workspace")
                    .font(.headline)
                Text(reviewPageTitle(selectedPage))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Back To Checkpoint") {
                    viewModel.returnToCheckpointReview()
                }
                .buttonStyle(.bordered)

                Button("Previous") {
                    viewModel.goToPreviousReviewPage()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToPreviousReviewPage)

                Text("Page \(fullReviewState.selectedPageIndex + 1) of \(fullReviewState.pages.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Picker("Review Mode", selection: Binding(
                    get: { viewModel.fullReviewMode },
                    set: { viewModel.selectFullReviewMode($0) }
                )) {
                    ForEach(FullReviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)

                Button("Next") {
                    viewModel.goToNextReviewPage()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToNextReviewPage)

                Button("Reveal Source") {
                    viewModel.revealSource(for: selectedPage)
                }
                .buttonStyle(.bordered)

                Button("Export Reviewed Files") {
                    viewModel.exportPendingOutputs()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func fullReviewWorkspaceBody(_ page: ReviewedPage) -> some View {
        switch viewModel.fullReviewMode {
        case .page:
            HStack(alignment: .top, spacing: 16) {
                reviewPagePreviewCard(page)
                reviewPageTextEditorCard(page)
            }
        case .line:
            reviewLineReviewCard(page)
        }
    }

    private func checkpointIssueRow(_ issue: OCRReviewIssue) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CheckpointIssuePreview(issue: issue)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issueLocation(issue))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                        Text(issueFilename(issue))
                            .font(.callout.weight(.medium))
                    }

                    Spacer()

                    Text(issue.severity.displayName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(issue.severity == .critical ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current OCR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(issue.originalText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text To Export")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        "Edit the final text for export",
                        text: Binding(
                            get: { viewModel.reviewText(for: issue) },
                            set: { viewModel.setReviewText($0, for: issue) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                }

                HStack(spacing: 8) {
                    if issue.suggestedText != nil {
                        Button("Use Suggestion") {
                            viewModel.useSuggestedText(for: issue)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Restore OCR") {
                        viewModel.restoreOriginalText(for: issue)
                    }
                    .buttonStyle(.bordered)

                    Button(viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) ? "Asking Apple Intelligence..." : "Ask Apple Intelligence") {
                        viewModel.suggestWithAppleIntelligence(for: issue)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUseAppleIntelligence || viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue))

                    if viewModel.appleIntelligenceSuggestion(for: issue) != nil {
                        Button("Use AI Suggestion") {
                            viewModel.useAppleIntelligenceSuggestion(for: issue)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let suggestedText = issue.suggestedText {
                    Label(suggestedText, systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let aiSuggestion = viewModel.appleIntelligenceSuggestion(for: issue) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aiSuggestion.correctedText)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Text(aiSuggestion.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(issue.reasons.joined(separator: " "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var checkpointUtilitiesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.canUseAppleIntelligence ? "sparkles" : "sparkles.slash")
                        .foregroundStyle(viewModel.canUseAppleIntelligence ? Color.accentColor : .secondary)

                    Text("Apple Intelligence")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button(viewModel.isGeneratingAppleIntelligenceForAllFlaggedLines ? "Generating Suggestions..." : "Suggest All Flagged Lines") {
                        viewModel.suggestWithAppleIntelligenceForAllFlaggedLines()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUseAppleIntelligence || viewModel.isGeneratingAppleIntelligenceForAllFlaggedLines)
                }

                Text(viewModel.appleIntelligenceAvailability.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            checkpointTranslationPanel
        }
    }

    private var checkpointTranslationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Export Options")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: $viewModel.translateReviewedDocument)
                    .labelsHidden()
                    .disabled(viewModel.isProcessing)
            }

            HStack {
                Text("Provider")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Provider", selection: $viewModel.translationProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isProcessing)
            }

            HStack {
                Text("Target Language")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Target Language", selection: $viewModel.translationTarget) {
                    ForEach(DocumentTranslationTarget.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isProcessing)
            }

            if viewModel.translationProvider == .openAI {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OpenAI Model")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("OpenAI Model", selection: $viewModel.openAITranslationModel) {
                            ForEach(OpenAITranslationModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(viewModel.isProcessing)
                    }

                    SecureField("OpenAI API key", text: $viewModel.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isProcessing)

                    HStack(spacing: 10) {
                        Button("Save API Key") {
                            viewModel.saveOpenAIAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing)

                        Button("Remove API Key") {
                            viewModel.clearOpenAIAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing || viewModel.openAIAPIKey.isEmpty)
                    }
                }
            }

            Text(viewModel.translationAvailability.message)
                .font(.footnote)
                .foregroundStyle(viewModel.canTranslateReviewedDocument ? .secondary : Color.orange.opacity(0.95))

            if let translationErrorMessage = viewModel.translationErrorMessage {
                Text(translationErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.orange.opacity(0.95))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reviewPagePreviewCard(_ page: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source Preview")
                        .font(.subheadline.weight(.semibold))
                    Text(URL(fileURLWithPath: page.sourcePath).lastPathComponent)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Whole page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ReviewPagePreview(page: page)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewPageTextEditorCard(_ page: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OCR Text")
                        .font(.subheadline.weight(.semibold))
                    Text("Edit the whole page as one text block")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                pageIssueBadge(page)
            }

            TextEditor(text: Binding(
                get: { viewModel.pageReviewText(for: page) },
                set: { viewModel.setPageReviewText($0, for: page) }
            ))
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Text("\(page.lineCount) OCR line\(page.lineCount == 1 ? "" : "s") on this page")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if let selectedLine = viewModel.selectedReviewLine,
                   selectedLine.hasChanges {
                    Text("Line review edits are already included here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewLineReviewCard(_ page: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Line Review")
                        .font(.subheadline.weight(.semibold))
                    Text("Inspect every line on this page with its cropped source")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                pageIssueBadge(page)
            }

            HStack {
                Text("\(page.lineCount) line\(page.lineCount == 1 ? "" : "s") on this page")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !page.lines.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(page.lines) { line in
                            compactLineReviewRow(line)
                        }
                    }
                    .padding(.trailing, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2)
                    Text("No lines available on this page")
                        .font(.callout.weight(.medium))
                    Text("Switch back to Page Review to edit the full page text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func compactLineReviewRow(_ line: ReviewedLine) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CompactReviewLinePreview(line: line)

            selectedLineEditorBody(line)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func reviewLineRow(_ line: ReviewedLine) -> some View {
        let issue = line.issue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Line \(line.lineIndex)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if line.hasChanges {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if let issue {
                    Text(issue.severity.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(issue.severity == .critical ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let issue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current OCR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(issue.originalText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OCR Line")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(line.originalText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Text To Export")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        "Edit the final text for export",
                        text: Binding(
                            get: { viewModel.reviewText(for: line) },
                            set: { viewModel.setReviewText($0, for: line) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                }

                if let issue {
                    HStack(spacing: 10) {
                        if issue.suggestedText != nil {
                            Button("Use Suggestion") {
                                viewModel.useSuggestedText(for: issue)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Restore OCR") {
                            viewModel.restoreOriginalText(for: issue)
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Button(viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) ? "Asking Apple Intelligence..." : "Ask Apple Intelligence") {
                                viewModel.suggestWithAppleIntelligence(for: issue)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.canUseAppleIntelligence || viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue))

                            if viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if viewModel.appleIntelligenceSuggestion(for: issue) != nil {
                                Button("Use AI Suggestion") {
                                    viewModel.useAppleIntelligenceSuggestion(for: issue)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let error = viewModel.appleIntelligenceError(for: issue) {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                    }

                    if let suggestedText = issue.suggestedText {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Suggested Review")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Label(suggestedText, systemImage: "wand.and.stars")
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    if let aiSuggestion = viewModel.appleIntelligenceSuggestion(for: issue) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Intelligence Suggestion")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(aiSuggestion.correctedText)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Text(aiSuggestion.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(issue.reasons.joined(separator: " "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Restore OCR") {
                        viewModel.setReviewText(line.originalText, for: line)
                    }
                    .buttonStyle(.bordered)
                }

                if let confidence = line.confidence {
                    Text("Confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(issue == nil ? Color.clear : Color.white.opacity(0.025))
        .overlay(alignment: .leading) {
            if let issue {
                Rectangle()
                    .fill(issue.severity == .critical ? Color.red.opacity(0.75) : Color.orange.opacity(0.75))
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.12)
        }
    }

    private func selectedLineEditorBody(_ line: ReviewedLine) -> some View {
        let issue = line.issue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Line \(line.lineIndex)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if line.hasChanges {
                        Text("Edited")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if let issue {
                    Text(issue.severity.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(issue.severity == .critical ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(issue == nil ? "OCR Line" : "Current OCR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(issue?.originalText ?? line.originalText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Text To Export")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "Edit the final text for export",
                    text: Binding(
                        get: { viewModel.reviewText(for: line) },
                        set: { viewModel.setReviewText($0, for: line) }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
            }

            if let issue {
                HStack(spacing: 10) {
                    if issue.suggestedText != nil {
                        Button("Use Suggestion") {
                            viewModel.useSuggestedText(for: issue)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Restore OCR") {
                        viewModel.restoreOriginalText(for: issue)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button(viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) ? "Asking Apple Intelligence..." : "Ask Apple Intelligence") {
                            viewModel.suggestWithAppleIntelligence(for: issue)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canUseAppleIntelligence || viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue))

                        if viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if viewModel.appleIntelligenceSuggestion(for: issue) != nil {
                            Button("Use AI Suggestion") {
                                viewModel.useAppleIntelligenceSuggestion(for: issue)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if let error = viewModel.appleIntelligenceError(for: issue) {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.orange.opacity(0.95))
                    }
                }

                if let suggestedText = issue.suggestedText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested Review")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Label(suggestedText, systemImage: "wand.and.stars")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }

                if let aiSuggestion = viewModel.appleIntelligenceSuggestion(for: issue) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Intelligence Suggestion")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(aiSuggestion.correctedText)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Text(aiSuggestion.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(issue.reasons.joined(separator: " "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("Restore OCR") {
                    viewModel.setReviewText(line.originalText, for: line)
                }
                .buttonStyle(.bordered)
            }

            if let confidence = line.confidence {
                Text("Confidence: \(confidence.formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reviewPageChip(page: ReviewedPage, index: Int, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pageChipTitle(page, index: index))
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if page.criticalCount > 0 {
                    Text("\(page.criticalCount) critical")
                        .foregroundStyle(Color.red.opacity(0.95))
                }
                if page.warningCount > 0 {
                    Text("\(page.warningCount) warning")
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
                if page.issueCount == 0 {
                    Text("Clean")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func pageCountBadge(title: String, count: Int, color: Color) -> some View {
        Text("\(title): \(count)")
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
    }

    private func reviewPageTitle(_ page: ReviewedPage) -> String {
        if let pageNumber = page.pageNumber {
            return "\(URL(fileURLWithPath: page.sourcePath).lastPathComponent) page \(pageNumber)"
        }
        return URL(fileURLWithPath: page.sourcePath).lastPathComponent
    }

    @ViewBuilder
    private func pageIssueBadge(_ page: ReviewedPage) -> some View {
        if page.issueCount > 0 {
            Text("\(page.issueCount) flagged")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.orange.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
        }
    }

    private func pageChipTitle(_ page: ReviewedPage, index: Int) -> String {
        if let pageNumber = page.pageNumber {
            return "Page \(pageNumber)"
        }
        return "Item \(index + 1)"
    }

    private func affectedPageCount(_ report: OCRReviewReport) -> Int {
        Set(report.issues.map { "\($0.sourcePath)#\($0.pageNumber ?? 0)" }).count
    }

    private func issueFilename(_ issue: OCRReviewIssue) -> String {
        URL(fileURLWithPath: issue.sourcePath).lastPathComponent
    }

    private func issueLocation(_ issue: OCRReviewIssue) -> String {
        if let pageNumber = issue.pageNumber {
            return "page \(pageNumber), line \(issue.lineIndex)"
        }
        return "line \(issue.lineIndex)"
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            StatusIndicator(style: statusStyle)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusStyle.title)
                    .font(.callout.weight(.semibold))
                Text(viewModel.statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
            }

            if let estimate = viewModel.estimatedTimeRemaining {
                Text(estimate)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial.opacity(0.82))
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var sidebarPanelFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.07),
                Color.white.opacity(0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ReviewPagePreview: View {
    let page: ReviewedPage

    @State private var previewImage: NSImage?
    @State private var didLoad = false

    var body: some View {
        ZoomableReviewSurface(
            image: previewImage,
            didLoad: didLoad,
            unavailableTitle: "Preview unavailable",
            unavailableMessage: "The page image could not be rendered for this source.",
            viewportSize: nil,
            showsCompactControls: false
        )
        .task(id: page.id) {
            previewImage = ReviewPreviewRenderer.pageImage(sourcePath: page.sourcePath, pageNumber: page.pageNumber)
            didLoad = true
        }
    }
}

private struct ReviewLinePreview: View {
    let line: ReviewedLine?

    @State private var previewImage: NSImage?
    @State private var didLoad = false

    var body: some View {
        ZoomableReviewSurface(
            image: previewImage,
            didLoad: didLoad,
            unavailableTitle: unavailableTitle,
            unavailableMessage: unavailableMessage,
            viewportSize: nil,
            showsCompactControls: false
        )
        .task(id: line?.id) {
            guard let line else {
                previewImage = nil
                didLoad = true
                return
            }
            previewImage = ReviewPreviewRenderer.image(for: line)
            didLoad = true
        }
    }

    private var unavailableTitle: String {
        if line == nil {
            return "No line selected"
        }
        return "Line crop unavailable"
    }

    private var unavailableMessage: String {
        if let line, line.boundingBox == nil {
            return "This line has no crop geometry, likely because it came from embedded PDF text."
        }
        return "Select a line to inspect its cropped source."
    }
}

private struct CompactReviewLinePreview: View {
    let line: ReviewedLine

    @State private var previewImage: NSImage?
    @State private var didLoad = false

    var body: some View {
        ZoomableReviewSurface(
            image: previewImage,
            didLoad: didLoad,
            unavailableTitle: line.boundingBox == nil ? "No crop" : "Preview unavailable",
            unavailableMessage: line.boundingBox == nil
                ? "This line has no crop geometry."
                : "The crop preview could not be rendered.",
            viewportSize: CGSize(width: 360, height: 156),
            showsCompactControls: true
        )
        .task(id: line.id) {
            previewImage = ReviewPreviewRenderer.image(for: line)
            didLoad = true
        }
    }
}

private struct CheckpointIssuePreview: View {
    let issue: OCRReviewIssue

    @State private var previewImage: NSImage?
    @State private var didLoad = false

    var body: some View {
        ZoomableReviewSurface(
            image: previewImage,
            didLoad: didLoad,
            unavailableTitle: "Preview unavailable",
            unavailableMessage: "The checkpoint crop could not be rendered.",
            viewportSize: CGSize(width: 280, height: 130),
            showsCompactControls: true
        )
        .task(id: issue.id) {
            previewImage = ReviewPreviewRenderer.image(for: issue)
            didLoad = true
        }
    }
}

private struct ZoomableReviewSurface: View {
    let image: NSImage?
    let didLoad: Bool
    let unavailableTitle: String
    let unavailableMessage: String
    let viewportSize: CGSize?
    let showsCompactControls: Bool

    @State private var zoomScale: CGFloat = 1.0
    @State private var committedOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    zoomScale = max(1.0, zoomScale - 0.25)
                    if zoomScale == 1.0 {
                        committedOffset = .zero
                        dragOffset = .zero
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(image == nil)
                .controlSize(showsCompactControls ? .small : .regular)

                Text("\(Int(zoomScale * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42)

                Button {
                    zoomScale = min(4.0, zoomScale + 0.25)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(image == nil)
                .controlSize(showsCompactControls ? .small : .regular)

                Button("Fit") {
                    zoomScale = 1.0
                    committedOffset = .zero
                    dragOffset = .zero
                }
                .buttonStyle(.bordered)
                .disabled(image == nil)
                .controlSize(showsCompactControls ? .small : .regular)

                Spacer()
            }

            GeometryReader { geometry in
                let viewport = resolvedViewportSize(in: geometry.size)
                Group {
                    if let image {
                        let baseSize = fittedImageSize(for: image, in: viewport)
                        let totalOffset = clampedOffset(
                            proposed: CGSize(
                                width: committedOffset.width + dragOffset.width,
                                height: committedOffset.height + dragOffset.height
                            ),
                            imageSize: baseSize,
                            viewportSize: viewport,
                            zoomScale: zoomScale
                        )

                        ZStack {
                            Color.clear

                            Image(nsImage: image)
                                .resizable()
                                .frame(width: baseSize.width, height: baseSize.height)
                                .scaleEffect(zoomScale, anchor: .center)
                                .offset(x: totalOffset.width, y: totalOffset.height)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard zoomScale > 1 else { return }
                                            isDragging = true
                                            dragOffset = value.translation
                                        }
                                        .onEnded { value in
                                            guard zoomScale > 1 else {
                                                isDragging = false
                                                dragOffset = .zero
                                                return
                                            }
                                            committedOffset = clampedOffset(
                                                proposed: CGSize(
                                                    width: committedOffset.width + value.translation.width,
                                                    height: committedOffset.height + value.translation.height
                                                ),
                                                imageSize: baseSize,
                                                viewportSize: viewport,
                                                zoomScale: zoomScale
                                            )
                                            dragOffset = .zero
                                            isDragging = false
                                        }
                                )
                        }
                        .frame(width: viewport.width, height: viewport.height)
                        .contentShape(Rectangle())
                        .clipped()
                        .onHover { hovering in
                            isHovering = hovering
                            updateCursor(canPan: zoomScale > 1, hovering: hovering, dragging: isDragging)
                        }
                        .onChange(of: isDragging) { dragging in
                            updateCursor(canPan: zoomScale > 1, hovering: isHovering, dragging: dragging)
                        }
                        .onChange(of: zoomScale) { scale in
                            committedOffset = clampedOffset(
                                proposed: committedOffset,
                                imageSize: baseSize,
                                viewportSize: viewport,
                                zoomScale: scale
                            )
                            if scale <= 1 {
                                dragOffset = .zero
                            }
                            updateCursor(canPan: scale > 1, hovering: isHovering, dragging: isDragging)
                        }
                    } else if didLoad {
                        VStack(spacing: showsCompactControls ? 4 : 6) {
                            Image(systemName: "viewfinder")
                                .font(showsCompactControls ? .callout : .title3)
                            Text(unavailableTitle)
                                .font(showsCompactControls ? .caption.weight(.medium) : .callout.weight(.medium))
                            Text(unavailableMessage)
                                .font(showsCompactControls ? .caption2 : .caption)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .controlSize(showsCompactControls ? .small : .regular)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: viewport.width, height: viewport.height)
            }
            .frame(
                width: viewportSize?.width,
                height: viewportSize?.height,
                alignment: .center
            )
            .frame(maxWidth: viewportSize == nil ? .infinity : nil, maxHeight: .infinity)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .onChange(of: image == nil) { _ in
            zoomScale = 1.0
            committedOffset = .zero
            dragOffset = .zero
        }
        .onDisappear {
            NSCursor.arrow.set()
        }
    }

    private func resolvedViewportSize(in availableSize: CGSize) -> CGSize {
        if let viewportSize {
            return viewportSize
        }
        return CGSize(
            width: max(availableSize.width, 1),
            height: max(availableSize.height, 1)
        )
    }

    private func fittedImageSize(for image: NSImage, in viewport: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0, viewport.width > 0, viewport.height > 0 else {
            return viewport
        }

        let widthRatio = viewport.width / image.size.width
        let heightRatio = viewport.height / image.size.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }

    private func clampedOffset(
        proposed: CGSize,
        imageSize: CGSize,
        viewportSize: CGSize,
        zoomScale: CGFloat
    ) -> CGSize {
        guard zoomScale > 1 else {
            return .zero
        }

        let scaledWidth = imageSize.width * zoomScale
        let scaledHeight = imageSize.height * zoomScale
        let maxX = max(0, (scaledWidth - viewportSize.width) / 2)
        let maxY = max(0, (scaledHeight - viewportSize.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func updateCursor(canPan: Bool, hovering: Bool, dragging: Bool) {
        guard hovering else {
            NSCursor.arrow.set()
            return
        }

        guard canPan else {
            NSCursor.arrow.set()
            return
        }

        if dragging {
            NSCursor.closedHand.set()
        } else {
            NSCursor.openHand.set()
        }
    }
}

private enum ViewStatusStyle {
    case idle
    case ready
    case processing
    case success
    case error

    var title: String {
        switch self {
        case .idle:
            return "Waiting for Files"
        case .ready:
            return "Ready to Process"
        case .processing:
            return "Processing Files"
        case .success:
            return "Export Complete"
        case .error:
            return "Attention Needed"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "clock"
        case .ready:
            return "checkmark.circle"
        case .processing:
            return "waveform.path.ecg"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .ready:
            return .accentColor
        case .processing:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}

private struct SelectionPill: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: isSelected ? .trailing : .leading) {
            Capsule()
                .fill(isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.12))
                .frame(width: 42, height: 24)

            Circle()
                .fill(.white.opacity(isSelected ? 0.95 : 0.75))
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
        }
    }
}

private struct StatusIndicator: View {
    let style: ViewStatusStyle

    var body: some View {
        ZStack {
            Circle()
                .fill(style.color.opacity(0.14))
                .frame(width: 34, height: 34)

            Image(systemName: style.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.color)
        }
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct ReviewedTranslationTaskModifier: ViewModifier {
    let descriptor: TranslationSessionConfigurationDescriptor?
    let sourceText: String?
    let onSuccess: (String) -> Void
    let onFailure: (Error) -> Void

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onAppear {
                updateConfiguration()
            }
            .onChange(of: descriptor) { _, _ in
                updateConfiguration()
            }
            .translationTask(configuration) { session in
                guard let sourceText else {
                    configuration = nil
                    return
                }

                do {
                    let translatedText = try await AppleIntelligenceTranslationService.shared.translateDocument(
                        text: sourceText,
                        using: session
                    )
                    onSuccess(translatedText)
                } catch {
                    onFailure(error)
                }

                configuration = nil
            }
    }

    private func updateConfiguration() {
        guard let descriptor else {
            configuration = nil
            return
        }

        configuration = AppleIntelligenceTranslationService.configuration(for: descriptor.target)
    }
}
#endif
