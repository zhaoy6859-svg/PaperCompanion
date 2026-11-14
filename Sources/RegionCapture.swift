import AppKit
import PDFKit
import Vision

// MARK: - Region rendering & OCR

enum RegionCapture {
    /// Renders a crop of the page (in page coordinates) into an NSImage.
    static func crop(page: PDFPage, rectInPage: CGRect, scale: CGFloat = 2.4) -> NSImage? {
        let rect = rectInPage.intersection(page.bounds(for: .cropBox))
        guard rect.width > 4, rect.height > 4 else { return nil }
        let pixelSize = NSSize(width: ceil(rect.width * scale), height: ceil(rect.height * scale))
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(pixelSize.width),
                                         pixelsHigh: Int(pixelSize.height),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = NSMakeSize(pixelSize.width, pixelSize.height)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        let cg = context.cgContext

        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(origin: .zero, size: pixelSize))

        // PDFPage.draw expects the page's own coordinate space: translate & scale so the crop lands in the bitmap.
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -rect.minX, y: -rect.minY)
        page.draw(with: .cropBox, to: cg)
        cg.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return image
    }

    /// JPEG payload capped to a sane size (the API downsizes anyway, but uploads stay snappy).
    static func jpegData(from image: NSImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else { return nil }
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let longest = max(width, height)
        let factor = longest > maxDimension ? maxDimension / longest : 1

        let targetSize = NSSize(width: max(1, (width * factor).rounded()), height: max(1, (height * factor).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(targetSize.width),
                                         pixelsHigh: Int(targetSize.height),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 3,
                                         hasAlpha: false,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            NSColor.white.setFill()
            NSRect(origin: .zero, size: targetSize).fill()
            source.draw(in: NSRect(origin: .zero, size: targetSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Renders a page in two overlapping halves so formulas stay legible after the
    /// API downscales images (~1300x1300). Returns JPEG payloads, top first.
    static func pageHalves(page: PDFPage, width: CGFloat = 1500) -> [Data] {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 10, bounds.height > 10 else { return [] }
        let scale = width / bounds.width
        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        guard let full = context.makeImage() else { return [] }

        let height = CGFloat(full.height)
        let half = Int(height * 0.55)
        let topRect = CGRect(x: 0, y: full.height - half, width: full.width, height: half)
        let bottomRect = CGRect(x: 0, y: 0, width: full.width, height: half)

        var result: [Data] = []
        for rect in [topRect, bottomRect] {
            guard let cropped = full.cropping(to: rect) else { continue }
            let rep = NSBitmapImageRep(cgImage: cropped)
            rep.size = NSSize(width: cropped.width, height: cropped.height)
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) {
                result.append(data)
            }
        }
        return result
    }

    /// Vision OCR for formula / figure regions that may contain text.
    static func ocrText(in image: NSImage) -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        guard let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Text of the caption closest to the region (above or below it).
    static func caption(page: PDFPage, near rectInPage: CGRect) -> String? {
        let pageBounds = page.bounds(for: .cropBox)
        var bands: [CGRect] = []
        // below the region (most captions sit under figures)
        let belowTop = max(pageBounds.minY, rectInPage.minY - 120)
        bands.append(CGRect(x: pageBounds.minX, y: belowTop, width: pageBounds.width, height: rectInPage.minY - belowTop))
        // above the region (tables sometimes have captions on top)
        let aboveTop = min(pageBounds.maxY, rectInPage.maxY + 120)
        bands.append(CGRect(x: pageBounds.minX, y: rectInPage.maxY, width: pageBounds.width, height: aboveTop - rectInPage.maxY))

        let pattern = try! NSRegularExpression(pattern: "^(?:Figure|Fig\\.?|Table|图|表)\\s*[0-9]+", options: [.caseInsensitive])
        for band in bands where band.height > 6 && band.width > 20 {
            guard let selection = page.selection(for: band), let text = selection.string else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let range = NSRange(location: 0, length: (trimmed as NSString).length)
                guard pattern.firstMatch(in: trimmed, options: [], range: range) != nil else { continue }
                var caption = trimmed
                if index + 1 < lines.count {
                    let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if next.count > 15, caption.count < 180 { caption += " " + next }
                }
                return caption
            }
        }
        return nil
    }
}
