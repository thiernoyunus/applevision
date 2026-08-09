import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppleVisionCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var droppedURLs: [URL] = []
    @Published var outputDirectory: URL
    @Published var outputMode: ArabicOutputMode = .both
    @Published var exportChoice: DocumentExportChoice = .text
    @Published var pdfTextMode: PDFTextMode = .preferEmbeddedText
    @Published var reviewBeforeExport = true
    @Published var isProcessing = false
    @Published var statusMessage = "Drop images or folders to begin."
    @Published var statusDetail = "Drop images or folders to begin."
    @Published var generatedFiles: [URL] = []
    @Published var reviewReport: OCRReviewReport?
    @Published var fullReviewState: FullDocumentReviewState?
    @Published var reviewMode: ReviewMode?
    @Published var fullReviewMode: FullReviewMode = .page
    @Published var appleIntelligenceAvailability = AppleIntelligenceReviewService.availability()
    @Published var appleIntelligenceSuggestions: [String: AppleIntelligenceReviewSuggestion] = [:]
    @Published var appleIntelligenceErrors: [String: String] = [:]
    @Published var appleIntelligenceLoadingIssueIDs: Set<String> = []
    @Published var isGeneratingAppleIntelligenceForAllFlaggedLines = false
    @Published var translateReviewedDocument = false
    @Published var translationProvider: TranslationProvider = .apple {
        didSet {
            saveTranslationPreferences()
        }
    }
    @Published var translationTarget: DocumentTranslationTarget = .english {
        didSet {
            saveTranslationPreferences()
        }
    }
    @Published var openAITranslationModel: OpenAITranslationModel = .gpt5Mini {
        didSet {
            saveTranslationPreferences()
        }
    }
    @Published var openAIAPIKey = ""
    @Published var translationAvailability = AppleIntelligenceTranslationService.defaultAvailability()
    @Published var translationErrorMessage: String?
    @Published var isTranslatingReviewedDocument = false
    @Published var progressValue: Double = 0
    @Published var completedUnitCount = 0
    @Published var totalUnitCount = 0
    @Published var currentProcessingLabel: String?
    @Published var estimatedTimeRemaining: String?

    private var pendingExportPayload: PendingExportPayload?
    private var pendingTranslationExport: PendingTranslationExport?
    private let defaults = UserDefaults.standard

    var hasPendingExport: Bool {
        pendingExportPayload != nil
    }

    var isCheckpointReviewActive: Bool {
        reviewMode == .checkpoint
    }

    var isFullReviewActive: Bool {
        reviewMode == .fullReview
    }

    var hasFullReview: Bool {
        fullReviewState != nil
    }

    var selectedReviewPage: ReviewedPage? {
        fullReviewState?.selectedPage
    }

    var selectedReviewLine: ReviewedLine? {
        guard let fullReviewState,
              let page = fullReviewState.selectedPage,
              let lineIndex = selectedReviewLineIndex(in: page, state: fullReviewState),
              page.lines.indices.contains(lineIndex)
        else {
            return nil
        }
        return page.lines[lineIndex]
    }

    var canGoToPreviousReviewPage: Bool {
        guard let fullReviewState else {
            return false
        }
        return fullReviewState.selectedPageIndex > 0
    }

    var canGoToNextReviewPage: Bool {
        guard let fullReviewState else {
            return false
        }
        return fullReviewState.selectedPageIndex + 1 < fullReviewState.pages.count
    }

    var canGoToPreviousReviewLine: Bool {
        guard let fullReviewState,
              let page = fullReviewState.selectedPage,
              let lineIndex = selectedReviewLineIndex(in: page, state: fullReviewState)
        else {
            return false
        }
        return lineIndex > 0
    }

    var canGoToNextReviewLine: Bool {
        guard let fullReviewState,
              let page = fullReviewState.selectedPage,
              let lineIndex = selectedReviewLineIndex(in: page, state: fullReviewState)
        else {
            return false
        }
        return lineIndex + 1 < page.lines.count
    }

    var canUseAppleIntelligence: Bool {
        appleIntelligenceAvailability.isAvailable
    }

    var canTranslateReviewedDocument: Bool {
        translationAvailability.isAvailable
    }

    var pendingTranslationConfiguration: TranslationSessionConfigurationDescriptor? {
        guard translationProvider == .apple else {
            return nil
        }
        return pendingTranslationExport.map { TranslationSessionConfigurationDescriptor(target: $0.target) }
    }

    var pendingTranslationText: String? {
        pendingTranslationExport?.reviewedPlainText
    }

    init() {
        self.outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        restoreTranslationPreferences()
        Task {
            await refreshTranslationAvailability()
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let dispatchGroup = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { dispatchGroup.leave() }

                if let data = item as? Data,
                   let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                    accumulator.append(url)
                } else if let url = item as? URL {
                    accumulator.append(url)
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.setInputURLs(accumulator.urls)
        }

        return true
    }

    func chooseDocuments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = "Choose images, PDFs, or folders to read."
        panel.prompt = "Choose Documents"

        if panel.runModal() == .OK {
            setInputURLs(panel.urls)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func openOutputDirectory() {
        NSWorkspace.shared.open(outputDirectory)
    }

    func revealSource(for issue: OCRReviewIssue) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: issue.sourcePath)])
    }

    func openSource(for issue: OCRReviewIssue) {
        NSWorkspace.shared.open(URL(fileURLWithPath: issue.sourcePath))
    }

    func openLogs() {
        let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: consoleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.statusMessage = "Unable to open Console: \(error.localizedDescription)"
                    self.statusDetail = "Console could not be opened."
                } else {
                    self.statusMessage = "Opened Console"
                    self.statusDetail = "Filter for com.thiernodiallo.AppleVisionApp."
                }
            }
        }
    }

    func processDroppedItems() {
        if pendingExportPayload != nil {
            exportPendingOutputs()
            return
        }

        guard !droppedURLs.isEmpty else {
            statusMessage = "No Files Selected"
            statusDetail = "Drop files or folders first."
            return
        }

        isProcessing = true
        ReviewPreviewRenderer.clearSourceImageCache()
        generatedFiles = []
        reviewReport = nil
        fullReviewState = nil
        reviewMode = nil
        appleIntelligenceSuggestions = [:]
        appleIntelligenceErrors = [:]
        appleIntelligenceLoadingIssueIDs = []
        isGeneratingAppleIntelligenceForAllFlaggedLines = false
        translationErrorMessage = nil
        isTranslatingReviewedDocument = false
        pendingTranslationExport = nil
        progressValue = 0
        completedUnitCount = 0
        totalUnitCount = 0
        currentProcessingLabel = nil
        estimatedTimeRemaining = nil
        statusMessage = "Preparing OCR"
        statusDetail = "Inspecting files and counting pages."

        let inputURLs = droppedURLs
        let outputDirectory = outputDirectory
        let outputMode = outputMode
        let exportChoice = exportChoice
        let pdfTextMode = pdfTextMode
        let reviewBeforeExport = reviewBeforeExport
        let startedAt = ContinuousClock.now

        Task.detached {
            do {
                let resolvedURLs = try InputResolver(recursive: true).resolve(urls: inputURLs)
                let requestOptions = OCRRequestOptions(
                    recursive: true,
                    recognitionLevel: .accurate,
                    recognitionLanguages: ["ar", "en-US"],
                    usesLanguageCorrection: true,
                    pdfTextMode: pdfTextMode
                )
                let results = try await OCRService(options: requestOptions).processStructured(urls: resolvedURLs) { update in
                    Task { @MainActor in
                        self.applyProgress(update, startedAt: startedAt)
                    }
                }
                let baseName = Self.makeBaseName(from: inputURLs)
                let reviewReport = OCRReviewService().review(results: results)

                if reviewBeforeExport, !reviewReport.issues.isEmpty {
                    let payload = PendingExportPayload(
                        outputDirectory: outputDirectory,
                        baseName: baseName,
                        outputMode: outputMode,
                        exportChoice: exportChoice,
                        results: results,
                        reviewIssues: reviewReport.issues
                    )

                    await MainActor.run {
                        self.pendingExportPayload = payload
                        self.reviewReport = reviewReport
                        self.fullReviewState = Self.makeFullReviewState(results: results, issues: reviewReport.issues)
                        self.reviewMode = .checkpoint
                        self.appleIntelligenceAvailability = AppleIntelligenceReviewService.availability()
                        self.appleIntelligenceSuggestions = [:]
                        self.appleIntelligenceErrors = [:]
                        self.appleIntelligenceLoadingIssueIDs = []
                        self.isGeneratingAppleIntelligenceForAllFlaggedLines = false
                        self.pendingTranslationExport = nil
                        self.translationErrorMessage = nil
                        self.isTranslatingReviewedDocument = false
                        self.progressValue = 1
                        self.completedUnitCount = self.totalUnitCount
                        self.currentProcessingLabel = nil
                        self.estimatedTimeRemaining = nil
                        self.statusMessage = "Review Suggested"
                        self.statusDetail = "Check \(reviewReport.issueCount) suspicious line(s) before exporting."
                        self.isProcessing = false
                    }
                } else {
                    let artifacts = try Self.makeExportArtifacts(
                        from: results,
                        outputMode: outputMode,
                        exportChoice: exportChoice
                    )
                    let writtenFiles = try Self.writeArtifacts(
                        artifacts,
                        baseName: baseName,
                        outputDirectory: outputDirectory
                    )

                    await MainActor.run {
                        self.generatedFiles = writtenFiles
                        self.reviewReport = reviewReport.issues.isEmpty ? nil : reviewReport
                        self.progressValue = 1
                        self.completedUnitCount = self.totalUnitCount
                        self.currentProcessingLabel = nil
                        self.estimatedTimeRemaining = nil
                        self.statusMessage = "Completed"
                        self.statusDetail = "Saved \(writtenFiles.count) file(s) to \(outputDirectory.path)."
                        self.isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.statusDetail = "Processing stopped before completion."
                    self.currentProcessingLabel = nil
                    self.estimatedTimeRemaining = nil
                    self.isProcessing = false
                }
            }
        }
    }

    func exportPendingOutputs() {
        guard let payload = pendingExportPayload else {
            return
        }
        let translateReviewedDocument = translateReviewedDocument
        let translationProvider = translationProvider
        let translationTarget = translationTarget
        let openAITranslationModel = openAITranslationModel

        isProcessing = true
        isTranslatingReviewedDocument = false
        translationErrorMessage = nil
        statusMessage = "Exporting Files"
        statusDetail = "Writing reviewed export output to disk."

        let reviewedResults = Self.makeReviewedResults(
            from: fullReviewState,
            fallback: payload.results
        )
        let artifacts: [PendingExportArtifact]
        do {
            artifacts = try Self.makeExportArtifacts(
                from: reviewedResults,
                outputMode: payload.outputMode,
                exportChoice: payload.exportChoice
            )
        } catch {
            pendingTranslationExport = nil
            isTranslatingReviewedDocument = false
            isProcessing = false
            statusMessage = error.localizedDescription
            statusDetail = "Unable to assemble export artifacts."
            return
        }

        if translateReviewedDocument {
            let openAIAPIKey: String
            if translationProvider == .openAI {
                guard let savedKey = loadOpenAIAPIKeyForTranslation() else {
                    completeReviewedExport(
                        using: artifacts,
                        payload: payload,
                        translationErrorMessage: translationErrorMessage ?? "OpenAI translation was unavailable."
                    )
                    return
                }
                openAIAPIKey = savedKey
            } else {
                openAIAPIKey = ""
            }

            if !canTranslateReviewedDocument {
                completeReviewedExport(
                    using: artifacts,
                    payload: payload,
                    translationErrorMessage: translationAvailability.message
                )
                return
            }

            let reviewedPlainText = Self.renderReviewedPlainText(from: reviewedResults)

            if translationProvider == .apple {
                pendingTranslationExport = PendingTranslationExport(
                    outputDirectory: payload.outputDirectory,
                    baseName: payload.baseName,
                    artifacts: artifacts,
                    reviewedPlainText: reviewedPlainText,
                    target: translationTarget
                )
                isTranslatingReviewedDocument = true
                statusDetail = "Writing reviewed OCR output and requesting Apple Translation."
                return
            }

            isTranslatingReviewedDocument = true
            statusDetail = "Writing reviewed OCR output and requesting OpenAI translation."

            Task {
                do {
                    let translatedText = try await OpenAITranslationService.shared.translateDocument(
                        text: reviewedPlainText,
                        to: translationTarget,
                        apiKey: openAIAPIKey,
                        model: openAITranslationModel
                    )
                    var translatedArtifacts = artifacts
                    translatedArtifacts.append(
                        PendingExportArtifact(
                            suffix: translationTarget.fileSuffix,
                            fileExtension: "txt",
                            content: .text(translatedText)
                        )
                    )
                    completeReviewedExport(using: translatedArtifacts, payload: payload, translationErrorMessage: nil)
                } catch {
                    completeReviewedExport(using: artifacts, payload: payload, translationErrorMessage: error.localizedDescription)
                }
            }
            return
        }

        completeReviewedExport(using: artifacts, payload: payload, translationErrorMessage: nil)
    }

    private func applyProgress(_ update: OCRProgressUpdate, startedAt: ContinuousClock.Instant) {
        totalUnitCount = update.totalUnitCount
        completedUnitCount = update.completedUnitCount
        progressValue = update.totalUnitCount > 0 ? Double(update.completedUnitCount) / Double(update.totalUnitCount) : 0
        currentProcessingLabel = Self.processingLabel(for: update)

        statusMessage = "Processing Files"
        statusDetail = "\(update.completedUnitCount) of \(update.totalUnitCount) steps completed"

        let elapsed = startedAt.duration(to: .now)
        if update.completedUnitCount > 0, update.completedUnitCount < update.totalUnitCount {
            let averagePerUnit = elapsed / update.completedUnitCount
            let remainingUnits = update.totalUnitCount - update.completedUnitCount
            let remaining = averagePerUnit * remainingUnits
            estimatedTimeRemaining = Self.formatted(duration: remaining)
        } else {
            estimatedTimeRemaining = nil
        }
    }

    func refreshTranslationAvailability() async {
        switch translationProvider {
        case .apple:
            translationAvailability = AppleIntelligenceTranslationService.defaultAvailability()
            translationAvailability = await AppleIntelligenceTranslationService.shared.availability(for: translationTarget)
        case .openAI:
            let normalizedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedKey.isEmpty {
                translationAvailability = .checking("Your saved OpenAI key will be checked when you choose export.")
            } else {
                translationAvailability = .available("OpenAI translation is ready using your saved API key.")
            }
        }
    }

    private func loadOpenAIAPIKeyForTranslation() -> String? {
        do {
            if let savedKey = try OpenAIKeychainStore().loadAPIKey() {
                openAIAPIKey = savedKey
            }
        } catch {
            let message = "Could not read the saved OpenAI API key. Your OCR files can still be saved without translation. \(error.localizedDescription)"
            translationAvailability = .unavailable(message)
            translationErrorMessage = message
            return nil
        }

        let normalizedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            let message = "No OpenAI API key is available. Your OCR files can still be saved without translation."
            translationAvailability = .unavailable(message)
            translationErrorMessage = message
            return nil
        }

        translationAvailability = .available("OpenAI translation is ready using your saved API key.")
        return normalizedKey
    }

    func saveOpenAIAPIKey() {
        let normalizedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if normalizedKey.isEmpty {
                try OpenAIKeychainStore().deleteAPIKey()
                translationErrorMessage = "Removed the saved OpenAI API key."
            } else {
                try OpenAIKeychainStore().save(apiKey: normalizedKey)
                openAIAPIKey = normalizedKey
                translationErrorMessage = "Saved the OpenAI API key in your macOS Keychain."
            }
        } catch {
            translationErrorMessage = error.localizedDescription
        }

        Task {
            await refreshTranslationAvailability()
        }
    }

    func clearOpenAIAPIKey() {
        do {
            try OpenAIKeychainStore().deleteAPIKey()
            openAIAPIKey = ""
            translationErrorMessage = "Removed the saved OpenAI API key."
        } catch {
            translationErrorMessage = error.localizedDescription
        }

        Task {
            await refreshTranslationAvailability()
        }
    }

    private func restoreTranslationPreferences() {
        if let storedProvider = defaults.string(forKey: Self.translationProviderDefaultsKey),
           let provider = TranslationProvider(rawValue: storedProvider) {
            translationProvider = provider
        }

        if let storedTarget = defaults.string(forKey: Self.translationTargetDefaultsKey),
           let target = DocumentTranslationTarget(rawValue: storedTarget) {
            translationTarget = target
        }

        if let storedModel = defaults.string(forKey: Self.openAITranslationModelDefaultsKey),
           let model = OpenAITranslationModel(rawValue: storedModel) {
            openAITranslationModel = model
        }
    }

    private func saveTranslationPreferences() {
        defaults.set(translationProvider.rawValue, forKey: Self.translationProviderDefaultsKey)
        defaults.set(translationTarget.rawValue, forKey: Self.translationTargetDefaultsKey)
        defaults.set(openAITranslationModel.rawValue, forKey: Self.openAITranslationModelDefaultsKey)
    }

    private static let translationProviderDefaultsKey = "translation.provider"
    private static let translationTargetDefaultsKey = "translation.target"
    private static let openAITranslationModelDefaultsKey = "translation.openaiModel"

    func finishPendingTranslation(with translatedText: String) {
        guard let pendingTranslationExport, let payload = pendingExportPayload else {
            return
        }

        var artifacts = pendingTranslationExport.artifacts
        artifacts.append(
            PendingExportArtifact(
                suffix: pendingTranslationExport.target.fileSuffix,
                fileExtension: "txt",
                content: .text(translatedText)
            )
        )
        completeReviewedExport(using: artifacts, payload: payload, translationErrorMessage: nil)
    }

    func failPendingTranslation(with error: Error) {
        guard let pendingTranslationExport, let payload = pendingExportPayload else {
            return
        }

        completeReviewedExport(
            using: pendingTranslationExport.artifacts,
            payload: payload,
            translationErrorMessage: error.localizedDescription
        )
    }

    nonisolated private static func makeBaseName(from urls: [URL]) -> String {
        if urls.count == 1 {
            return sanitizedBaseName(from: urls[0])
        }

        return "applevision_\(timestamp())"
    }

    nonisolated private static func sanitizedBaseName(from url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let rawName = (resourceValues?.isDirectory == true) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let sanitized = rawName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "applevision_output" : sanitized
    }

    nonisolated private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    nonisolated private static func processingLabel(for update: OCRProgressUpdate) -> String {
        let filename = URL(fileURLWithPath: update.sourcePath).lastPathComponent
        if let pageNumber = update.pageNumber {
            return "\(filename) • Page \(pageNumber)"
        }
        return filename
    }

    nonisolated private static func formatted(duration: Duration) -> String? {
        let seconds = Int(duration.components.seconds)
        guard seconds > 0 else {
            return "Less than 1s remaining"
        }

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m remaining"
        }

        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s remaining"
        }

        return "\(seconds)s remaining"
    }

    private func resetReviewState() {
        ReviewPreviewRenderer.clearSourceImageCache()
        pendingExportPayload = nil
        pendingTranslationExport = nil
        reviewReport = nil
        fullReviewState = nil
        reviewMode = nil
        fullReviewMode = .page
        appleIntelligenceSuggestions = [:]
        appleIntelligenceErrors = [:]
        appleIntelligenceLoadingIssueIDs = []
        isGeneratingAppleIntelligenceForAllFlaggedLines = false
        translationErrorMessage = nil
        isTranslatingReviewedDocument = false
        generatedFiles = []
    }

    private func setInputURLs(_ urls: [URL]) {
        resetReviewState()
        droppedURLs = urls.sorted(by: InputOrdering.isNaturalPageBefore)
        if droppedURLs.isEmpty {
            statusMessage = AppleVisionError.dropFailed.localizedDescription
            statusDetail = "Try dropping files again."
        } else {
            statusMessage = "Waiting for Files"
            statusDetail = "Ready to process \(droppedURLs.count) dropped item(s)."
        }
    }

    func reviewText(for issue: OCRReviewIssue) -> String {
        reviewText(forLineID: issue.id) ?? issue.originalText
    }

    func setReviewText(_ text: String, for issue: OCRReviewIssue) {
        setReviewText(text, forLineID: issue.id)
    }

    func useSuggestedText(for issue: OCRReviewIssue) {
        guard let suggestedText = issue.suggestedText else {
            return
        }
        setReviewText(suggestedText, forLineID: issue.id)
    }

    func restoreOriginalText(for issue: OCRReviewIssue) {
        restoreOriginalText(forLineID: issue.id)
    }

    func refreshAppleIntelligenceAvailability() {
        appleIntelligenceAvailability = AppleIntelligenceReviewService.availability()
    }

    func appleIntelligenceSuggestion(for issue: OCRReviewIssue) -> AppleIntelligenceReviewSuggestion? {
        appleIntelligenceSuggestions[issue.id]
    }

    func appleIntelligenceError(for issue: OCRReviewIssue) -> String? {
        appleIntelligenceErrors[issue.id]
    }

    func isGeneratingAppleIntelligenceSuggestion(for issue: OCRReviewIssue) -> Bool {
        appleIntelligenceLoadingIssueIDs.contains(issue.id)
    }

    func suggestWithAppleIntelligence(for issue: OCRReviewIssue) {
        refreshAppleIntelligenceAvailability()
        guard canUseAppleIntelligence else {
            appleIntelligenceErrors[issue.id] = appleIntelligenceAvailability.message
            return
        }
        guard !appleIntelligenceLoadingIssueIDs.contains(issue.id) else {
            return
        }

        Task {
            await requestAppleIntelligenceSuggestion(for: issue)
        }
    }

    func suggestWithAppleIntelligenceForAllFlaggedLines() {
        guard let report = reviewReport else {
            return
        }

        refreshAppleIntelligenceAvailability()
        guard canUseAppleIntelligence else {
            for issue in report.issues {
                appleIntelligenceErrors[issue.id] = appleIntelligenceAvailability.message
            }
            return
        }
        guard !isGeneratingAppleIntelligenceForAllFlaggedLines else {
            return
        }

        let issues = report.issues
        Task {
            isGeneratingAppleIntelligenceForAllFlaggedLines = true
            defer { isGeneratingAppleIntelligenceForAllFlaggedLines = false }

            for issue in issues {
                await requestAppleIntelligenceSuggestion(for: issue)
            }
        }
    }

    func useAppleIntelligenceSuggestion(for issue: OCRReviewIssue) {
        guard let suggestion = appleIntelligenceSuggestions[issue.id] else {
            return
        }
        setReviewText(suggestion.correctedText, forLineID: issue.id)
    }

    func useSuggestedTextForAll() {
        guard var state = fullReviewState else {
            return
        }

        for pageIndex in state.pages.indices {
            for lineIndex in state.pages[pageIndex].lines.indices {
                if let suggestedText = state.pages[pageIndex].lines[lineIndex].issue?.suggestedText {
                    state.pages[pageIndex].lines[lineIndex].editedText = suggestedText
                }
            }
        }
        fullReviewState = state
    }

    func useSuggestedTextForCritical() {
        guard var state = fullReviewState else {
            return
        }

        for pageIndex in state.pages.indices {
            for lineIndex in state.pages[pageIndex].lines.indices {
                let line = state.pages[pageIndex].lines[lineIndex]
                if line.issue?.severity == .critical, let suggestedText = line.issue?.suggestedText {
                    state.pages[pageIndex].lines[lineIndex].editedText = suggestedText
                }
            }
        }
        fullReviewState = state
    }

    func restoreAllOCRText() {
        guard var state = fullReviewState else {
            return
        }

        for pageIndex in state.pages.indices {
            for lineIndex in state.pages[pageIndex].lines.indices {
                state.pages[pageIndex].lines[lineIndex].editedText = state.pages[pageIndex].lines[lineIndex].originalText
            }
        }
        fullReviewState = state
    }

    func reviewText(for line: ReviewedLine) -> String {
        reviewText(forLineID: line.id) ?? line.editedText
    }

    func setReviewText(_ text: String, for line: ReviewedLine) {
        setReviewText(text, forLineID: line.id)
    }

    func pageReviewText(for page: ReviewedPage) -> String {
        guard let state = fullReviewState,
              let pageIndex = state.pages.firstIndex(where: { $0.id == page.id })
        else {
            return page.lines.map(\.editedText).joined(separator: "\n")
        }
        return state.pages[pageIndex].lines.map(\.editedText).joined(separator: "\n")
    }

    func setPageReviewText(_ text: String, for page: ReviewedPage) {
        guard var state = fullReviewState,
              let pageIndex = state.pages.firstIndex(where: { $0.id == page.id })
        else {
            return
        }

        let sourcePath = state.pages[pageIndex].sourcePath
        let pageNumber = state.pages[pageIndex].pageNumber
        let replacementTexts = Self.editorLines(from: text)
        let existingLines = state.pages[pageIndex].lines
        let rebuiltLines = replacementTexts.enumerated().map { index, replacementText in
            let lineIndex = index + 1
            if existingLines.indices.contains(index) {
                var line = existingLines[index]
                line.editedText = replacementText
                return line
            }

            return ReviewedLine(
                id: FullDocumentReviewState.lineID(sourcePath: sourcePath, pageNumber: pageNumber, lineIndex: lineIndex),
                sourcePath: sourcePath,
                pageNumber: pageNumber,
                lineIndex: lineIndex,
                originalText: replacementText,
                editedText: replacementText,
                confidence: nil,
                boundingBox: nil,
                candidates: [],
                words: [],
                issue: nil
            )
        }

        state.pages[pageIndex].lines = rebuiltLines.enumerated().map { index, line in
            var line = line
            line.id = FullDocumentReviewState.lineID(sourcePath: sourcePath, pageNumber: pageNumber, lineIndex: index + 1)
            line.lineIndex = index + 1
            return line
        }
        if rebuiltLines.count != existingLines.count {
            state.pages[pageIndex].structure = nil
        }
        state.selectedLineIndexByPageID[state.pages[pageIndex].id] = normalizedSelectedLineIndex(
            for: state.pages[pageIndex],
            requestedIndex: state.selectedLineIndexByPageID[state.pages[pageIndex].id]
        )
        fullReviewState = state
    }

    private func reviewText(forLineID lineID: String) -> String? {
        guard let location = locationForReviewedLine(withID: lineID),
              let state = fullReviewState
        else {
            return nil
        }
        return state.pages[location.pageIndex].lines[location.lineIndex].editedText
    }

    private func setReviewText(_ text: String, forLineID lineID: String) {
        updateReviewedLine(withID: lineID) { line in
            line.editedText = text
        }
    }

    private func restoreOriginalText(forLineID lineID: String) {
        updateReviewedLine(withID: lineID) { line in
            line.editedText = line.originalText
        }
    }

    func selectReviewPage(index: Int) {
        guard var state = fullReviewState, state.pages.indices.contains(index) else {
            return
        }
        state.selectedPageIndex = index
        let page = state.pages[index]
        state.selectedLineIndexByPageID[page.id] = normalizedSelectedLineIndex(
            for: page,
            requestedIndex: state.selectedLineIndexByPageID[page.id]
        )
        fullReviewState = state
    }

    func goToPreviousReviewPage() {
        guard let fullReviewState else {
            return
        }
        selectReviewPage(index: max(0, fullReviewState.selectedPageIndex - 1))
    }

    func goToNextReviewPage() {
        guard let fullReviewState else {
            return
        }
        selectReviewPage(index: min(fullReviewState.pages.count - 1, fullReviewState.selectedPageIndex + 1))
    }

    func jumpToFirstFlaggedReviewPage() {
        guard let fullReviewState,
              let pageIndex = fullReviewState.pages.firstIndex(where: { $0.issueCount > 0 })
        else {
            return
        }
        selectReviewPage(index: pageIndex)
    }

    func openFullReview() {
        if selectedReviewPage == nil {
            jumpToFirstFlaggedReviewPage()
        }
        reviewMode = .fullReview
    }

    func selectFullReviewMode(_ mode: FullReviewMode) {
        guard fullReviewMode != mode else {
            return
        }

        // SwiftUI's segmented Picker can call its setter during view reconciliation.
        // Defer the published change to the next main-run-loop turn to avoid
        // "Publishing changes from within view updates" warnings.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.fullReviewMode != mode else {
                return
            }
            self.fullReviewMode = mode
        }
    }

    func selectedReviewLineIndex(in page: ReviewedPage) -> Int? {
        guard let state = fullReviewState else {
            return nil
        }
        return selectedReviewLineIndex(in: page, state: state)
    }

    func selectReviewLine(index: Int) {
        guard var state = fullReviewState,
              let page = state.selectedPage
        else {
            return
        }

        let normalizedIndex = normalizedSelectedLineIndex(for: page, requestedIndex: index)
        state.selectedLineIndexByPageID[page.id] = normalizedIndex
        fullReviewState = state
    }

    func goToPreviousReviewLine() {
        guard let page = selectedReviewPage,
              let lineIndex = selectedReviewLineIndex(in: page)
        else {
            return
        }
        selectReviewLine(index: max(0, lineIndex - 1))
    }

    func goToNextReviewLine() {
        guard let page = selectedReviewPage,
              let lineIndex = selectedReviewLineIndex(in: page)
        else {
            return
        }
        selectReviewLine(index: min(page.lines.count - 1, lineIndex + 1))
    }

    func returnToCheckpointReview() {
        reviewMode = .checkpoint
    }

    func revealSource(for page: ReviewedPage) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: page.sourcePath)])
    }

    func openSource(for page: ReviewedPage) {
        NSWorkspace.shared.open(URL(fileURLWithPath: page.sourcePath))
    }

    private func updateReviewedLine(withID lineID: String, update: (inout ReviewedLine) -> Void) {
        guard var state = fullReviewState,
              let location = locationForReviewedLine(withID: lineID, in: state)
        else {
            return
        }
        update(&state.pages[location.pageIndex].lines[location.lineIndex])
        fullReviewState = state
    }

    private func selectedReviewLineIndex(in page: ReviewedPage, state: FullDocumentReviewState) -> Int? {
        normalizedSelectedLineIndex(
            for: page,
            requestedIndex: state.selectedLineIndexByPageID[page.id]
        )
    }

    private func normalizedSelectedLineIndex(for page: ReviewedPage, requestedIndex: Int?) -> Int? {
        guard !page.lines.isEmpty else {
            return nil
        }
        let candidate = requestedIndex ?? page.lines.firstIndex(where: \.isFlagged) ?? 0
        return min(max(candidate, 0), page.lines.count - 1)
    }

    private func locationForReviewedLine(withID lineID: String) -> (pageIndex: Int, lineIndex: Int)? {
        guard let state = fullReviewState else {
            return nil
        }
        return locationForReviewedLine(withID: lineID, in: state)
    }

    private func locationForReviewedLine(
        withID lineID: String,
        in state: FullDocumentReviewState
    ) -> (pageIndex: Int, lineIndex: Int)? {
        for pageIndex in state.pages.indices {
            if let lineIndex = state.pages[pageIndex].lines.firstIndex(where: { $0.id == lineID }) {
                return (pageIndex, lineIndex)
            }
        }
        return nil
    }

    private func requestAppleIntelligenceSuggestion(for issue: OCRReviewIssue) async {
        appleIntelligenceLoadingIssueIDs.insert(issue.id)
        appleIntelligenceErrors.removeValue(forKey: issue.id)

        do {
            let context = makeAppleIntelligenceContext(for: issue)
            let suggestion = try await AppleIntelligenceReviewService.shared.suggestCorrection(
                for: issue,
                currentText: reviewText(for: issue),
                context: context
            )
            appleIntelligenceSuggestions[issue.id] = suggestion
        } catch {
            appleIntelligenceErrors[issue.id] = error.localizedDescription
        }

        appleIntelligenceLoadingIssueIDs.remove(issue.id)
    }

    private func makeAppleIntelligenceContext(for issue: OCRReviewIssue) -> AppleIntelligenceReviewContext {
        guard let results = pendingExportPayload?.results ?? reviewReport.map({ _ in pendingExportPayload?.results }).flatMap({ $0 }),
              let result = results.first(where: { $0.sourcePath == issue.sourcePath && $0.pageNumber == issue.pageNumber }),
              issue.lineIndex > 0,
              issue.lineIndex <= result.lines.count
        else {
            return AppleIntelligenceReviewContext(
                previousLine: nil,
                nextLine: nil,
                documentExcerpt: issue.originalText
            )
        }

        let index = issue.lineIndex - 1
        let previousLine = index > 0 ? result.lines[index - 1].text : nil
        let nextLine = index + 1 < result.lines.count ? result.lines[index + 1].text : nil
        let excerptStart = max(0, index - 2)
        let excerptEnd = min(result.lines.count - 1, index + 2)
        let excerpt = result.lines[excerptStart...excerptEnd]
            .map(\.text)
            .joined(separator: "\n")

        return AppleIntelligenceReviewContext(
            previousLine: previousLine,
            nextLine: nextLine,
            documentExcerpt: excerpt
        )
    }

    nonisolated private static func makeExportArtifacts(
        from results: [OCRResult],
        outputMode: ArabicOutputMode,
        exportChoice: DocumentExportChoice
    ) throws -> [PendingExportArtifact] {
        var artifacts: [PendingExportArtifact] = []

        if exportChoice.includesTextFiles {
            let renderedOutputs = OutputRenderer.renderArabic(results: results, mode: outputMode)
            artifacts.append(contentsOf: renderedOutputs.map {
                PendingExportArtifact(
                    suffix: $0.suffix,
                    fileExtension: "txt",
                    content: .text($0.text)
                )
            })
        }

        if exportChoice.includesSearchablePDF {
            let pdfData = try SearchablePDFRenderer.render(results: results)
            artifacts.append(
                PendingExportArtifact(
                    suffix: "searchable",
                    fileExtension: "pdf",
                    content: .data(pdfData)
                )
            )
        }

        return artifacts
    }

    nonisolated private static func writeArtifacts(
        _ artifacts: [PendingExportArtifact],
        baseName: String,
        outputDirectory: URL
    ) throws -> [URL] {
        try artifacts.map { artifact in
            let fileURL = outputDirectory.appendingPathComponent("\(baseName)_\(artifact.suffix).\(artifact.fileExtension)")
            do {
                switch artifact.content {
                case let .text(text):
                    try text.write(to: fileURL, atomically: true, encoding: .utf8)
                case let .data(data):
                    try data.write(to: fileURL, options: .atomic)
                }
                return fileURL
            } catch {
                throw AppleVisionError.writeFailed(fileURL.path)
            }
        }
    }

    nonisolated private static func renderReviewedPlainText(from results: [OCRResult]) -> String {
        results
            .map { $0.structuredText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n"
    }

    nonisolated private static func makeFullReviewState(
        results: [OCRResult],
        issues: [OCRReviewIssue]
    ) -> FullDocumentReviewState {
        let issueLookup = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        let pages = results.map { result -> ReviewedPage in
            let lines = result.lines.enumerated().map { index, line in
                let lineIndex = index + 1
                let lineID = FullDocumentReviewState.lineID(
                    sourcePath: result.sourcePath,
                    pageNumber: result.pageNumber,
                    lineIndex: lineIndex
                )
                return ReviewedLine(
                    id: lineID,
                    sourcePath: result.sourcePath,
                    pageNumber: result.pageNumber,
                    lineIndex: lineIndex,
                    originalText: line.text,
                    editedText: line.text,
                    confidence: line.confidence,
                    boundingBox: line.boundingBox,
                    candidates: line.candidates,
                    words: line.words,
                    issue: issueLookup[lineID]
                )
            }
            return ReviewedPage(
                id: FullDocumentReviewState.pageID(sourcePath: result.sourcePath, pageNumber: result.pageNumber),
                sourcePath: result.sourcePath,
                pageNumber: result.pageNumber,
                lines: lines,
                structure: result.structure
            )
        }

        let selectedPageIndex = pages.firstIndex(where: { $0.issueCount > 0 }) ?? 0
        let selectedLineIndexByPageID = Dictionary(uniqueKeysWithValues: pages.map { page in
            (
                page.id,
                page.lines.firstIndex(where: \.isFlagged) ?? 0
            )
        })
        return FullDocumentReviewState(
            pages: pages,
            selectedPageIndex: selectedPageIndex,
            selectedLineIndexByPageID: selectedLineIndexByPageID
        )
    }

    nonisolated private static func makeReviewedResults(
        from fullReviewState: FullDocumentReviewState?,
        fallback results: [OCRResult]
    ) -> [OCRResult] {
        guard let fullReviewState else {
            return results
        }

        return fullReviewState.pages.map { page in
            return OCRResult(
                sourcePath: page.sourcePath,
                pageNumber: page.pageNumber,
                lines: page.lines.map { line in
                    OCRLine(
                        text: line.editedText,
                        confidence: line.confidence,
                        boundingBox: line.boundingBox,
                        candidates: line.candidates,
                        words: line.hasChanges ? [] : line.words
                    )
                },
                structure: page.structure
            )
        }
    }

    nonisolated private static func editorLines(from text: String) -> [String] {
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func completeReviewedExport(
        using artifacts: [PendingExportArtifact],
        payload: PendingExportPayload,
        translationErrorMessage: String?
    ) {
        do {
            let writtenFiles = try Self.writeArtifacts(
                artifacts,
                baseName: payload.baseName,
                outputDirectory: payload.outputDirectory
            )
            generatedFiles = writtenFiles
            ReviewPreviewRenderer.clearSourceImageCache()
            pendingExportPayload = nil
            pendingTranslationExport = nil
            fullReviewState = nil
            reviewMode = nil
            appleIntelligenceSuggestions = [:]
            appleIntelligenceErrors = [:]
            appleIntelligenceLoadingIssueIDs = []
            isGeneratingAppleIntelligenceForAllFlaggedLines = false
            self.translationErrorMessage = translationErrorMessage
            isTranslatingReviewedDocument = false
            isProcessing = false
            statusMessage = "Completed"
            if let translationErrorMessage {
                statusDetail = "Saved \(writtenFiles.count) file(s) to \(payload.outputDirectory.path). Translation was skipped: \(translationErrorMessage)"
            } else {
                statusDetail = "Saved \(writtenFiles.count) file(s) to \(payload.outputDirectory.path)."
            }
        } catch {
            pendingTranslationExport = nil
            self.translationErrorMessage = translationErrorMessage
            isTranslatingReviewedDocument = false
            isProcessing = false
            statusMessage = error.localizedDescription
            statusDetail = "Export stopped before completion."
        }
    }
}

private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

struct ReviewedLine: Identifiable, Sendable {
    var id: String
    let sourcePath: String
    let pageNumber: Int?
    var lineIndex: Int
    let originalText: String
    var editedText: String
    let confidence: Float?
    let boundingBox: OCRBoundingBox?
    let candidates: [OCRCandidate]
    let words: [OCRWord]
    let issue: OCRReviewIssue?

    var isFlagged: Bool {
        issue != nil
    }

    var hasChanges: Bool {
        editedText != originalText
    }
}

enum ReviewMode: Sendable {
    case checkpoint
    case fullReview
}

enum FullReviewMode: String, CaseIterable, Identifiable, Sendable {
    case page
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .page:
            return "Page Review"
        case .line:
            return "Line Review"
        }
    }
}

struct ReviewedPage: Identifiable, Sendable {
    let id: String
    let sourcePath: String
    let pageNumber: Int?
    var lines: [ReviewedLine]
    var structure: OCRDocumentStructure?

    var lineCount: Int {
        lines.count
    }

    var issueCount: Int {
        lines.filter(\.isFlagged).count
    }

    var criticalCount: Int {
        lines.filter { $0.issue?.severity == .critical }.count
    }

    var warningCount: Int {
        lines.filter { $0.issue?.severity == .warning }.count
    }
}

struct FullDocumentReviewState: Sendable {
    var pages: [ReviewedPage]
    var selectedPageIndex: Int
    var selectedLineIndexByPageID: [String: Int]

    var selectedPage: ReviewedPage? {
        guard pages.indices.contains(selectedPageIndex) else {
            return nil
        }
        return pages[selectedPageIndex]
    }

    static func pageID(sourcePath: String, pageNumber: Int?) -> String {
        "\(sourcePath)#\(pageNumber ?? 0)"
    }

    static func lineID(sourcePath: String, pageNumber: Int?, lineIndex: Int) -> String {
        "\(sourcePath)#\(pageNumber ?? 0)#\(lineIndex)"
    }
}

private struct PendingExportArtifact: Sendable {
    let suffix: String
    let fileExtension: String
    let content: ExportArtifactContent
}

private struct PendingExportPayload: Sendable {
    let outputDirectory: URL
    let baseName: String
    let outputMode: ArabicOutputMode
    let exportChoice: DocumentExportChoice
    let results: [OCRResult]
    let reviewIssues: [OCRReviewIssue]
}

struct TranslationSessionConfigurationDescriptor: Identifiable, Sendable, Equatable {
    let target: DocumentTranslationTarget

    var id: String {
        target.rawValue
    }
}

private struct PendingTranslationExport: Sendable {
    let outputDirectory: URL
    let baseName: String
    let artifacts: [PendingExportArtifact]
    let reviewedPlainText: String
    let target: DocumentTranslationTarget
}

private enum ExportArtifactContent: Sendable {
    case text(String)
    case data(Data)
}
