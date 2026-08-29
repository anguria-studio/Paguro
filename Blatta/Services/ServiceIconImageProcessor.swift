import AppKit

enum ServiceIconImageError: LocalizedError {
    case fileTooLarge
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "Choose an image smaller than 20 MB."
        case .invalidImage:
            return "Blatta could not read that image."
        case .encodingFailed:
            return "Blatta could not prepare that image for use as an icon."
        }
    }
}

/// Prepares user-selected and downloaded images for compact SwiftData storage.
@MainActor
enum ServiceIconImageProcessor {
    static let maximumInputBytes = 20 * 1024 * 1024
    static let maximumDimension: CGFloat = 256

    static func displayImage(from data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        guard let largest = image.representations.max(by: {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }), largest.pixelsWide > Int(image.size.width) else {
            return image
        }
        image.size = NSSize(width: largest.pixelsWide, height: largest.pixelsHigh)
        return image
    }

    static func normalizedPNG(from data: Data) throws -> Data {
        guard data.count <= maximumInputBytes else {
            throw ServiceIconImageError.fileTooLarge
        }
        guard let image = displayImage(from: data), image.size.width > 0, image.size.height > 0 else {
            throw ServiceIconImageError.invalidImage
        }

        return try normalizedPNG(from: image)
    }

    static func normalizedPNG(from image: NSImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw ServiceIconImageError.invalidImage
        }

        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let pixelWidth = max(1, Int((image.size.width * scale).rounded()))
        let pixelHeight = max(1, Int((image.size.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ServiceIconImageError.encodingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ServiceIconImageError.encodingFailed
        }
        return png
    }
}
