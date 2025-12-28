import Foundation
import CoreGraphics
import ImageIO

private let printerWidth = 384 // This is specific to the T02 printer

public struct PhomemoImage {
    public let cgImage: CGImage
    public let dithered: CGImage

    public init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let prepared = Self.prepare(img),
              let dithered = prepared.toDitheredMonochrome()
        else { return nil }

        self.cgImage = prepared
        self.dithered = dithered
    }

    private static func prepare(_ image: CGImage) -> CGImage? {
        guard let normalized = try? image.normalized() else { return nil }

        let rotated = normalized.width > normalized.height ? normalized.rotated(by: .pi / 2) : normalized
        guard let rotated else { return nil }

        let aspectRatio = CGFloat(rotated.height) / CGFloat(rotated.width)
        let targetHeight = Int(CGFloat(printerWidth) * aspectRatio)
        let targetSize = CGSize(width: CGFloat(printerWidth), height: CGFloat(targetHeight))

        return rotated.resized(to: targetSize)
    }
}

private extension CGImage {
    func normalized() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw NSError(domain: "ImageError", code: 2)
        }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let normalized = ctx.makeImage() else { throw NSError(domain: "ImageError", code: 3) }
        return normalized
    }

    func resized(to target: CGSize) -> CGImage? {
        guard let colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: nil,
                                  width: Int(target.width),
                                  height: Int(target.height),
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(origin: .zero, size: target))
        return ctx.makeImage()
    }

    func rotated(by radians: CGFloat) -> CGImage? {
        let width = CGFloat(self.width)
        let height = CGFloat(self.height)
        let ctx = CGContext(data: nil,
                            width: Int(height),
                            height: Int(width),
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: 0,
                            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: bitmapInfo.rawValue)!
        ctx.translateBy(x: height / 2, y: width / 2)
        ctx.rotate(by: radians)
        ctx.draw(self, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        return ctx.makeImage()
    }

    func toMonochrome() -> CGImage? {
        let width = self.width
        let height = self.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width

        // Allocate our own mutable pixel buffer
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        // Draw the source image into our grayscale context
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Apply a simple threshold
        for i in 0..<(width * height) {
            pixels[i] = pixels[i] < 128 ? 0 : 255
        }

        // Create a new CGImage from the modified pixels
        guard let outCtx = CGContext(data: &pixels,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: bytesPerRow,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        return outCtx.makeImage()
    }

    func toClassicDitheredMonochrome() -> CGImage? {
        let width = self.width, height = self.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Floyd–Steinberg dithering
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let old = Float(pixels[i])
                let new: Float = old < 128 ? 0 : 255
                pixels[i] = UInt8(new)
                let err = old - new
                if x + 1 < width {
                    pixels[i + 1] = clampToByte(Float(pixels[i + 1]) + 7/16 * err)
                }
                if y + 1 < height {
                    if x > 0 {
                        pixels[i + width - 1] = clampToByte(Float(pixels[i + width - 1]) + 3/16 * err)
                    }
                    pixels[i + width] = clampToByte(Float(pixels[i + width]) + 5/16 * err)
                    if x + 1 < width {
                        pixels[i + width + 1] = clampToByte(Float(pixels[i + width + 1]) + 1/16 * err)
                    }
                }
            }
        }

        guard let outCtx = CGContext(data: &pixels,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: width,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        return outCtx.makeImage()
    }

    // swiftlint:disable:next function_body_length
    func toDitheredMonochrome() -> CGImage? {
        let width = self.width
        let height = self.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Prepare luminance buffer
        var gray = [Double](repeating: 0.0, count: width * height)
        for i in 0..<width*height {
            let base = i * 4
            let r = Double(pixels[base + 0]) / 255.0
            let g = Double(pixels[base + 1]) / 255.0
            let b = Double(pixels[base + 2]) / 255.0
            // sRGB → linear
            let linear = pow(0.2126 * pow(r, 2.2) +
                             0.7152 * pow(g, 2.2) +
                             0.0722 * pow(b, 2.2), 1.0 / 2.2)
            gray[i] = linear * 255.0
        }

        // Floyd–Steinberg error diffusion (Pillow-style)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let oldPixel = gray[i]
                let newPixel = (oldPixel < 128.0) ? 0.0 : 255.0
                let err = oldPixel - newPixel
                gray[i] = newPixel

                if x + 1 < width {
                    gray[i + 1] += err * 7.0 / 16.0
                }
                if y + 1 < height {
                    if x > 0 { gray[i + width - 1] += err * 3.0 / 16.0 }
                    gray[i + width] += err * 5.0 / 16.0
                    if x + 1 < width { gray[i + width + 1] += err * 1.0 / 16.0 }
                }
            }
        }

        // Build 8-bit grayscale output buffer
        var out = [UInt8](repeating: 0, count: width * height)
        for i in 0..<width * height {
            out[i] = gray[i] < 128.0 ? 0 : 255
        }

        let graySpace = CGColorSpaceCreateDeviceGray()
        guard let outCtx = CGContext(data: &out,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: width,
                                     space: graySpace,
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        return outCtx.makeImage()
    }
}

private func clampToByte(_ v: Float) -> UInt8 {
    return UInt8(max(0, min(255, v)))
}
