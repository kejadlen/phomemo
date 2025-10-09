import Foundation
import CoreGraphics
import ImageIO

public struct PhomemoImage {
    public let cgImage: CGImage
    public var width: Int = 384 // This is specific to the T02 printer
    
    public init?(url: URL, width: Int = 384) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        self.cgImage = img
        self.width = width
    }

    public func toMonochrome(dithered: Bool = true) -> CGImage? {
        guard let rotated = cgImage.width > cgImage.height ? cgImage.rotated(by: .pi / 2) : self.cgImage else {
            return nil
        }
        
        
        let targetWidth = self.width
        let aspectRatio = CGFloat(rotated.height) / CGFloat(rotated.width)
        let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)
        
        guard let resized = rotated.resized(to: CGSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))) else { return nil
        }
        
        let mono = dithered ? resized.toDitheredMonochrome() : resized.toMonochrome()
        guard let gray = mono else { return nil }
        
        return gray
    }

    public func toPhomemoData(dithered: Bool = true) -> Data? {
        guard let rotated = cgImage.width > cgImage.height ? cgImage.rotated(by: .pi / 2) : self.cgImage else {
            return nil
        }
        
        let targetWidth = self.width
        let aspectRatio = CGFloat(rotated.height) / CGFloat(rotated.width)
        let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)
        
        guard let resized = rotated.resized(to: CGSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))) else { return nil
        }

        let mono = dithered ? resized.toDitheredMonochrome() : resized.toMonochrome()
        
        guard let gray = mono else { return nil }
        let width = gray.width
        let height = gray.height

        guard let buf = gray.dataProvider?.data,
              let pixels = CFDataGetBytePtr(buf) else { return nil }
        
        var remaining = height
        var y = 0

        var data = Data()
        data.append(header())

        while remaining > 0 {
            var lines = remaining
            if lines > 256 { lines = 256 }
            data.append(marker(lines: UInt8(lines - 1)))
            remaining -= lines
            while lines > 0 {
                data.append(line(pixels: pixels, width: width, row: y))
                lines -= 1
                y += 1
            }
        }
        data.append(footer())

        return data
    }
    
    private func header() -> Data {
        return Data([0x1b, 0x40, 0x1b, 0x61, 0x01, 0x1f, 0x11, 0x02, 0x04])
    }
    
    private func marker(lines: UInt8) -> Data {
        // All little endian
        return Data([
            0x1d, 0x76,
            0x30, 0x00,
            0x30, 0x00,
            lines, 0x00
        ])
    }
    
    private func line(pixels: UnsafePointer<UInt8>, width: Int, row: Int) -> Data {
        var data = Data()
        for x in 0..<(width) / 8 {
            var byte: UInt8 = 0
            for bit in 0..<8 {
                let pixelX = x * 8 + bit
                if pixels[row * width + pixelX] == 0 {
                    byte |= 1 << (7 - bit)
                }
            }
            if byte == 0x0a {
                byte = 0x14
            }
            data.append(byte)
        }
        return data
    }

    private func footer() -> Data {
        return Data([
            0x1b, 0x64, 0x02,
            0x1b, 0x64, 0x02,
            0x1f, 0x11, 0x08,
            0x1f, 0x11, 0x0e,
            0x1f, 0x11, 0x07,
            0x1f, 0x11, 0x09
        ])
    }
}

private extension CGImage {
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
                if x + 1 < width { pixels[i + 1] = clampToByte(Float(pixels[i + 1]) + 7/16 * err) }
                if y + 1 < height {
                    if x > 0 { pixels[i + width - 1] = clampToByte(Float(pixels[i + width - 1]) + 3/16 * err) }
                    pixels[i + width] = clampToByte(Float(pixels[i + width]) + 5/16 * err)
                    if x + 1 < width { pixels[i + width + 1] = clampToByte(Float(pixels[i + width + 1]) + 1/16 * err) }
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
                let idx = y * width + x
                let oldPixel = gray[idx]
                let newPixel = (oldPixel < 128.0) ? 0.0 : 255.0
                let err = oldPixel - newPixel
                gray[idx] = newPixel

                if x + 1 < width {
                    gray[idx + 1] += err * 7.0 / 16.0
                }
                if y + 1 < height {
                    if x > 0 { gray[idx + width - 1] += err * 3.0 / 16.0 }
                    gray[idx + width] += err * 5.0 / 16.0
                    if x + 1 < width { gray[idx + width + 1] += err * 1.0 / 16.0 }
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
