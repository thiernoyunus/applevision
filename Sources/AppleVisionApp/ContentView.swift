import AppleVisionCore
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isTargeted = false
    @State private var advancedOptionsExpanded = false
    @State private var fullReviewTextScale: CGFloat = 1
    @State private var hoveredReviewLineID: String?
    @ScaledMetric(relativeTo: .body) private var fullReviewTextBaseSize: CGFloat = 18

    private var fullReviewTextSize: CGFloat {
        fullReviewTextBaseSize * fullReviewTextScale
    }

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

    private var isReviewActive: Bool {
        viewModel.hasPendingExport && viewModel.reviewReport?.issues.isEmpty == false
    }

    var body: some View {
        translationManagedContent {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if !isReviewActive {
                        sidebar
                        Divider()
                    }
                    workspace
                }
                footerBar
            }
        }
        .background(windowBackground)
        .frame(minWidth: 900, idealWidth: 1240, minHeight: 620, idealHeight: 820)
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
        Color(nsColor: .windowBackgroundColor)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    outputFolderSection

                    DisclosureGroup(isExpanded: $advancedOptionsExpanded) {
                        VStack(alignment: .leading, spacing: 20) {
                            sidebarSection(title: "Output Mode", footnote: "Choose which Arabic text version to save when text files are included.") {
                                modeOptionRow(title: "Both Versions", subtitle: "With and without vowel marks", symbol: "square.grid.2x2", isSelected: viewModel.outputMode == .both) {
                                    viewModel.outputMode = .both
                                }
                                modeOptionRow(title: "With Vowel Marks", subtitle: "Keep vowel marks in the text", symbol: "text.line.first.and.arrowtriangle.forward", isSelected: viewModel.outputMode == .withHarakat) {
                                    viewModel.outputMode = .withHarakat
                                }
                                modeOptionRow(title: "Without Vowel Marks", subtitle: "Remove vowel marks after reading", symbol: "eye.slash", isSelected: viewModel.outputMode == .withoutHarakat) {
                                    viewModel.outputMode = .withoutHarakat
                                }
                            }

                            sidebarSection(title: "File Type", footnote: "Choose text files, a searchable PDF, or both.") {
                                modeOptionRow(title: "Text Files", subtitle: "Save text files only", symbol: "doc.text", isSelected: viewModel.exportChoice == .text) {
                                    viewModel.exportChoice = .text
                                }
                                modeOptionRow(title: "Searchable PDF", subtitle: "Save a PDF you can search", symbol: "doc.richtext", isSelected: viewModel.exportChoice == .searchablePDF) {
                                    viewModel.exportChoice = .searchablePDF
                                }
                                modeOptionRow(title: "Both", subtitle: "Save text files and a searchable PDF", symbol: "square.stack.3d.up", isSelected: viewModel.exportChoice == .both) {
                                    viewModel.exportChoice = .both
                                }
                            }

                            sidebarSection(title: "PDF Reading", footnote: "Use this only when a PDF's existing text is wrong.") {
                                modeOptionRow(title: "Use PDF Text First", subtitle: "Read existing PDF text when available", symbol: "doc.text", isSelected: viewModel.pdfTextMode == .preferEmbeddedText) {
                                    viewModel.pdfTextMode = .preferEmbeddedText
                                }
                                modeOptionRow(title: "Read Every Page", subtitle: "Read each PDF page as an image", symbol: "exclamationmark.circle", isSelected: viewModel.pdfTextMode == .ocrOnly) {
                                    viewModel.pdfTextMode = .ocrOnly
                                }
                            }

                            sidebarSection(title: "Review Before Saving", footnote: "Pause when the app finds text it is less sure about.") {
                                Toggle("Review uncertain lines", isOn: $viewModel.reviewBeforeExport)
                                    .toggleStyle(.switch)
                            }

                            Button("Open Logs") {
                                viewModel.openLogs()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.top, 14)
                    } label: {
                        Label("Advanced Options", systemImage: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                    }
                    .padding(16)
                    .background(sidebarPanelFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Text("Read Documents")
                .font(.system(size: 26, weight: .semibold))

            Text("Turn images and PDFs into text you can save.")
                .font(.body)
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
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
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
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var outputFolderSection: some View {
        sidebarSection(title: "Save Folder", footnote: "Your text files and searchable PDFs will be saved here.") {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.outputDirectory.path)
                    .textSelection(.enabled)
                    .font(.body)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Choose Save Folder") {
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
        Color(nsColor: .windowBackgroundColor)
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: viewModel.isProcessing ? "waveform.path.ecg" : "doc.text.viewfinder")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)

            VStack(spacing: 10) {
                Text(viewModel.isProcessing ? "Reading Documents" : "Drop Documents Here")
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
            } else {
                Button("Choose Documents") {
                    viewModel.chooseDocuments()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 720)
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(nsColor: .separatorColor)))
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    private var processingSubtitle: String {
        if let label = viewModel.currentProcessingLabel {
            return label
        }
        return "Reading your documents with Arabic support."
    }

    private var buttonTitle: String {
        if viewModel.isProcessing {
            return "Processing..."
        }
        if viewModel.hasPendingExport {
            return "Export Files"
        }
        return "Read Documents"
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
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
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
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review Checkpoint")
                        .font(.title2.weight(.semibold))
                    Text("Check the marked lines, then continue reviewing or save your work now.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.hasPendingExport {
                    VStack(alignment: .trailing, spacing: 12) {
                        HStack(spacing: 8) {
                            pageCountBadge(title: "Critical", count: report.criticalCount, color: .red)
                            pageCountBadge(title: "Warnings", count: report.warningCount, color: .orange)
                            pageCountBadge(title: "Pages", count: affectedPageCount(report), color: .secondary)
                        }

                        HStack(spacing: 8) {
                            Menu("More Actions") {
                                Button("Use All Suggestions") {
                                    viewModel.useSuggestedTextForAll()
                                }
                                Button("Use Critical Suggestions") {
                                    viewModel.useSuggestedTextForCritical()
                                }
                                Button("Jump to First Marked Page") {
                                    viewModel.jumpToFirstFlaggedReviewPage()
                                }
                                Divider()
                                Button("Restore All OCR Text") {
                                    viewModel.restoreAllOCRText()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(minHeight: 44)

                            Button("Export Now") {
                                viewModel.exportPendingOutputs()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                            .disabled(viewModel.isProcessing)

                            Button("Continue Review") {
                                viewModel.openFullReview()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.issues) { issue in
                    checkpointIssueRow(issue)
                }
            }

            checkpointUtilitiesPanel
        }
        .padding(24)
        .frame(maxWidth: 1240)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    private var fullReviewWorkspace: some View {
        Group {
            if let fullReviewState = viewModel.fullReviewState,
               let selectedPage = viewModel.selectedReviewPage {
                VStack(alignment: .leading, spacing: 14) {
                    fullReviewToolbar(fullReviewState: fullReviewState, selectedPage: selectedPage)

                    fullReviewWorkspaceBody(selectedPage)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.top, 20)
            }
        }
    }

    private func fullReviewToolbar(fullReviewState: FullDocumentReviewState, selectedPage: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review")
                        .font(.title2.weight(.semibold))
                    Text(reviewPageTitle(selectedPage))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Back") {
                    viewModel.returnToCheckpointReview()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Menu("More") {
                    Button("Reveal Source") {
                        viewModel.revealSource(for: selectedPage)
                    }
                }
                .buttonStyle(.bordered)

                Button("Export") {
                    viewModel.exportPendingOutputs()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isProcessing)
            }

            HStack(spacing: 10) {
                Button("Previous") {
                    hoveredReviewLineID = nil
                    viewModel.goToPreviousReviewPage()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToPreviousReviewPage)

                Picker("Page", selection: Binding(
                    get: { fullReviewState.selectedPageIndex },
                    set: {
                        hoveredReviewLineID = nil
                        viewModel.selectReviewPage(index: $0)
                    }
                )) {
                    ForEach(Array(fullReviewState.pages.enumerated()), id: \.element.id) { index, page in
                        Text("\(pageChipTitle(page, index: index)) · \(page.issueCount) marked").tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                Button("Next") {
                    hoveredReviewLineID = nil
                    viewModel.goToNextReviewPage()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToNextReviewPage)

                Text("\(fullReviewState.selectedPageIndex + 1) of \(fullReviewState.pages.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Picker("Review mode", selection: Binding(
                    get: { viewModel.fullReviewMode },
                    set: {
                        hoveredReviewLineID = nil
                        viewModel.selectFullReviewMode($0)
                    }
                )) {
                    Text("Page").tag(FullReviewMode.page)
                    Text("Line").tag(FullReviewMode.line)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)

                Divider()
                    .frame(height: 28)

                HStack(spacing: 4) {
                    Button {
                        fullReviewTextScale = max(0.75, fullReviewTextScale - 0.25)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(fullReviewTextScale <= 0.75)
                    .accessibilityLabel("Decrease review text size")
                    .help("Makes Full Review text smaller, down to 75 percent.")

                    Button("\(Int(fullReviewTextScale * 100))%") {
                        fullReviewTextScale = 1
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 56, minHeight: 44)
                    .accessibilityLabel("Reset review text size to 100 percent")
                    .help("Restores the default Full Review text size.")

                    Button {
                        fullReviewTextScale += 0.25
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Increase review text size")
                    .help("Makes Full Review text larger.")
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func fullReviewWorkspaceBody(_ page: ReviewedPage) -> some View {
        switch viewModel.fullReviewMode {
        case .page:
            HSplitView {
                reviewPagePreviewCard(page)
                    .frame(minWidth: 360, idealWidth: 520)
                reviewPageTextEditorCard(page)
                    .frame(minWidth: 420, idealWidth: 620)
            }
        case .line:
            HSplitView {
                reviewLineSourcePreviewCard(page, highlightBox: highlightedReviewLineBoundingBox(in: page))
                    .frame(minWidth: 360, idealWidth: 520)
                reviewLineReviewCard(page)
                    .frame(minWidth: 420, idealWidth: 620)
                    .id(page.id)
            }
        }
    }

    private func checkpointIssueRow(_ issue: OCRReviewIssue) -> some View {
        HStack(alignment: .top, spacing: 20) {
            CheckpointIssuePreview(issue: issue)
                .frame(width: 300)

            VStack(alignment: .leading, spacing: 14) {
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
                        .foregroundStyle(issue.severity == .critical ? Color.red : Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current OCR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(issue.originalText)
                        .font(.system(size: 18))
                        .lineSpacing(4)
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
                    .font(.system(size: 18))
                    .lineLimit(1...4)
                }

                Menu("Line Actions") {
                    if issue.suggestedText != nil {
                        Button("Use Suggested Text") {
                            viewModel.useSuggestedText(for: issue)
                        }
                    }
                    Button("Restore OCR Text") {
                        viewModel.restoreOriginalText(for: issue)
                    }
                    Button(viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue) ? "Asking Apple Intelligence..." : "Ask Apple Intelligence") {
                        viewModel.suggestWithAppleIntelligence(for: issue)
                    }
                    .disabled(!viewModel.canUseAppleIntelligence || viewModel.isGeneratingAppleIntelligenceSuggestion(for: issue))
                    if viewModel.appleIntelligenceSuggestion(for: issue) != nil {
                        Button("Use AI Suggestion") {
                            viewModel.useAppleIntelligenceSuggestion(for: issue)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 44)

                if let suggestedText = issue.suggestedText {
                    Label(suggestedText, systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let aiSuggestion = viewModel.appleIntelligenceSuggestion(for: issue) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aiSuggestion.correctedText)
                            .font(.system(size: 18))
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
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor)))
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
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor)))

            DisclosureGroup("Translation") {
                checkpointTranslationPanel
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var checkpointTranslationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
            Text("Translate the saved text")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Translate the saved text", isOn: $viewModel.translateReviewedDocument)
                    .labelsHidden()
                    .disabled(viewModel.isProcessing)
                    .accessibilityLabel("Translate the saved text")
                    .help("Adds a translated version when you export.")
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    private func reviewLineSourcePreviewCard(_ page: ReviewedPage, highlightBox: OCRBoundingBox?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Source Preview")
                    .font(.subheadline.weight(.semibold))
                Text(URL(fileURLWithPath: page.sourcePath).lastPathComponent)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ReviewPagePreview(page: page, highlightBox: highlightBox)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    private func reviewPageTextEditorCard(_ page: ReviewedPage) -> some View {
        let isArabic = containsArabic(viewModel.pageReviewText(for: page))

        return VStack(alignment: .leading, spacing: 12) {
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

            if let structure = page.structure, !structure.tables.isEmpty {
                detectedTables(structure.tables, for: page)
            }

            TextEditor(text: Binding(
                get: { viewModel.pageReviewText(for: page) },
                set: { viewModel.setPageReviewText($0, for: page) }
            ))
            .font(.system(size: fullReviewTextSize))
            .scrollContentBackground(.hidden)
            .lineSpacing(6 * fullReviewTextScale)
            .multilineTextAlignment(isArabic ? .trailing : .leading)
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor)))

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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    private func detectedTables(_ tables: [OCRTable], for page: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tables.count == 1 ? "Detected Table" : "Detected Tables")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach(Array(tables.enumerated()), id: \.offset) { index, table in
                ScrollView([.horizontal, .vertical]) {
                    detectedTableGrid(table, for: page)
                        .padding(1)
                }
                .frame(maxHeight: 220)
                .accessibilityLabel("Detected Table \(index + 1)")
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }

    private func detectedTableGrid(_ table: OCRTable, for page: ReviewedPage) -> some View {
        let rowCount = table.cells.map { $0.row + $0.rowSpan }.max() ?? 0
        let columnCount = table.cells.map { $0.column + $0.columnSpan }.max() ?? 0

        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        if let cell = table.cells.first(where: { $0.row == row && $0.column == column }) {
                            detectedTableCell(cell, for: page)
                                .gridCellColumns(cell.columnSpan)
                        } else if !table.cells.contains(where: { cell in
                            cell.row == row && cell.column < column && cell.column + cell.columnSpan > column
                        }) {
                            Color.clear
                                .frame(minWidth: 120, minHeight: 44)
                                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
                        }
                    }
                }
            }
        }
    }

    private func detectedTableCell(_ cell: OCRTableCell, for page: ReviewedPage) -> some View {
        let editedText = cell.lineIndices.compactMap { lineIndex in
            page.lines.indices.contains(lineIndex) ? page.lines[lineIndex].editedText : nil
        }
        let text = editedText.isEmpty ? cell.fallbackText : editedText.joined(separator: " ")
        let isArabic = containsArabic(text)

        return Text(text)
            .font(.system(size: fullReviewTextSize))
            .lineSpacing(4 * fullReviewTextScale)
            .multilineTextAlignment(isArabic ? .trailing : .leading)
            .frame(minWidth: 120, maxWidth: .infinity, minHeight: 44, alignment: isArabic ? .trailing : .leading)
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
    }

    private func reviewLineReviewCard(_ page: ReviewedPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Line Review")
                        .font(.subheadline.weight(.semibold))
                    Text("Edit every line on this page")
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
                        ForEach(page.lines.indices, id: \.self) { index in
                            let line = page.lines[index]
                            compactLineReviewRow(
                                line,
                                index: index,
                                isSelected: viewModel.selectedReviewLineIndex(in: page) == index
                            )
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(nsColor: .separatorColor)))
        .onDisappear {
            hoveredReviewLineID = nil
        }
    }

    private func compactLineReviewRow(_ line: ReviewedLine, index: Int, isSelected: Bool) -> some View {
        let isHovered = hoveredReviewLineID == line.id
        let fill = isSelected
            ? Color.accentColor.opacity(0.18)
            : isHovered ? Color.accentColor.opacity(0.09) : Color(nsColor: .textBackgroundColor)
        let border = isSelected
            ? Color.accentColor.opacity(0.72)
            : isHovered ? Color.accentColor.opacity(0.42) : Color(nsColor: .separatorColor)

        return VStack(alignment: .leading, spacing: 8) {
            selectedLineEditorBody(line)

            if line.boundingBox == nil {
                Text("Source location unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { isHovering in
                if isHovering {
                    hoveredReviewLineID = line.id
                } else if hoveredReviewLineID == line.id {
                    hoveredReviewLineID = nil
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.selectReviewLine(index: index)
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Line \(line.lineIndex)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Selects this line and highlights its source.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Select line") {
                viewModel.selectReviewLine(index: index)
            }
    }

    private func highlightedReviewLineBoundingBox(in page: ReviewedPage) -> OCRBoundingBox? {
        if let hoveredReviewLineID,
           let hoveredLine = page.lines.first(where: { $0.id == hoveredReviewLineID }) {
            return hoveredLine.boundingBox
        }

        guard let selectedIndex = viewModel.selectedReviewLineIndex(in: page),
              page.lines.indices.contains(selectedIndex)
        else {
            return nil
        }
        return page.lines[selectedIndex].boundingBox
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
                        .background(Color.secondary.opacity(0.12))
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
                            .font(.system(size: 18))
                            .textSelection(.enabled)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OCR Line")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(line.originalText)
                            .font(.system(size: 18))
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
        .background(issue == nil ? Color.clear : Color.secondary.opacity(0.06))
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
        let originalText = issue?.originalText ?? line.originalText
        let exportText = viewModel.reviewText(for: line)
        let originalTextIsArabic = containsArabic(originalText)
        let exportTextIsArabic = containsArabic(exportText)

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
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(issue == nil ? "OCR Line" : "Current OCR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(originalText)
                    .font(.system(size: fullReviewTextSize))
                    .multilineTextAlignment(originalTextIsArabic ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: originalTextIsArabic ? .trailing : .leading)
                    .environment(\.layoutDirection, originalTextIsArabic ? .rightToLeft : .leftToRight)
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
                .font(.system(size: fullReviewTextSize))
                .lineLimit(1...6)
                .multilineTextAlignment(exportTextIsArabic ? .trailing : .leading)
                .environment(\.layoutDirection, exportTextIsArabic ? .rightToLeft : .leftToRight)
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
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func pageCountBadge(title: String, count: Int, color: Color) -> some View {
        Text("\(title): \(count)")
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
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
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func pageChipTitle(_ page: ReviewedPage, index: Int) -> String {
        if let pageNumber = page.pageNumber {
            return "Page \(pageNumber)"
        }
        return "Item \(index + 1)"
    }

    private func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0600...0x06FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                true
            default:
                false
            }
        }
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
        Color(nsColor: .controlBackgroundColor)
    }
}

private struct ReviewPagePreview: View {
    let page: ReviewedPage
    let highlightBox: OCRBoundingBox?

    @State private var previewImage: NSImage?
    @State private var didLoad = false

    init(page: ReviewedPage, highlightBox: OCRBoundingBox? = nil) {
        self.page = page
        self.highlightBox = highlightBox
    }

    var body: some View {
        ZoomableReviewSurface(
            image: previewImage,
            didLoad: didLoad,
            unavailableTitle: "Preview unavailable",
            unavailableMessage: "The page image could not be rendered for this source.",
            viewportSize: nil,
            showsCompactControls: false,
            highlightBox: highlightBox
        )
        .task(id: page.id) {
            previewImage = nil
            didLoad = false
            let image = await Task.detached(priority: .userInitiated) {
                ReviewPreviewRenderer.pageImage(sourcePath: page.sourcePath, pageNumber: page.pageNumber)
            }.value
            guard !Task.isCancelled else {
                return
            }
            previewImage = image
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
            previewImage = nil
            didLoad = false
            let image = await Task.detached(priority: .userInitiated) {
                ReviewPreviewRenderer.image(for: line)
            }.value
            guard !Task.isCancelled else {
                return
            }
            previewImage = image
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
            previewImage = nil
            didLoad = false
            let image = await Task.detached(priority: .userInitiated) {
                ReviewPreviewRenderer.image(for: issue)
            }.value
            guard !Task.isCancelled else {
                return
            }
            previewImage = image
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
    let highlightBox: OCRBoundingBox?

    init(
        image: NSImage?,
        didLoad: Bool,
        unavailableTitle: String,
        unavailableMessage: String,
        viewportSize: CGSize?,
        showsCompactControls: Bool,
        highlightBox: OCRBoundingBox? = nil
    ) {
        self.image = image
        self.didLoad = didLoad
        self.unavailableTitle = unavailableTitle
        self.unavailableMessage = unavailableMessage
        self.viewportSize = viewportSize
        self.showsCompactControls = showsCompactControls
        self.highlightBox = highlightBox
    }

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
                .accessibilityLabel("Zoom out")
                .help("Makes the source preview smaller.")

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
                .accessibilityLabel("Zoom in")
                .help("Makes the source preview larger.")

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
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: baseSize.width, height: baseSize.height)

                            if let highlightBox {
                                let highlightRect = highlightBox.rect(in: CGRect(origin: .zero, size: baseSize))

                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.16))
                                    .overlay {
                                        Rectangle()
                                            .stroke(Color.accentColor, lineWidth: 2 / zoomScale)
                                    }
                                    .frame(width: highlightRect.width, height: highlightRect.height)
                                    .position(x: highlightRect.midX, y: highlightRect.midY)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
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
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor)))
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
                .fill(isSelected ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.3))
                .frame(width: 42, height: 24)

            Circle()
                .fill(isSelected ? Color.white.opacity(0.95) : Color.primary.opacity(0.75))
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
