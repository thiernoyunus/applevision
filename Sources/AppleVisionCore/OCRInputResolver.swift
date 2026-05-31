import Foundation

public struct InputResolver {
    private let fileManager = FileManager.default
    private let recursive: Bool

    private static let supportedImageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp",
    ]

    public init(recursive: Bool) {
        self.recursive = recursive
    }

    public func resolve(paths: [String]) throws -> [URL] {
        try resolve(urls: paths.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) })
    }

    public func resolve(urls: [URL]) throws -> [URL] {
        var resolvedURLs: [URL] = []

        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                throw AppleVisionError.fileNotFound(url.path)
            }

            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if resourceValues.isDirectory == true {
                resolvedURLs.append(contentsOf: try collectFiles(in: url))
            } else if resourceValues.isRegularFile == true {
                guard Self.isSupported(url: url) else {
                    throw AppleVisionError.unsupportedInput(url.path)
                }

                resolvedURLs.append(url)
            }
        }

        let uniqueSortedURLs = Array(Set(resolvedURLs)).sorted(by: InputOrdering.isNaturalPageBefore)

        guard !uniqueSortedURLs.isEmpty else {
            throw AppleVisionError.noSupportedInputs("No supported image or PDF files were found in the provided input paths.")
        }

        return uniqueSortedURLs
    }

    private func collectFiles(in directoryURL: URL) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: options
        ) else {
            return []
        }

        var discoveredURLs: [URL] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            guard resourceValues.isRegularFile == true, Self.isSupported(url: fileURL) else {
                continue
            }

            discoveredURLs.append(fileURL)
        }

        return discoveredURLs
    }

    public static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || supportedImageExtensions.contains(ext)
    }
}
