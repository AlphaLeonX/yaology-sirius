#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreImage

let args = CommandLine.arguments
let sourcePath = args.count > 1 ? args[1] : "/Users/leon/工程/Code/personal-projects/yaology/sirius/assets/icons/01_gravitational_eclipse.jpg"
let outputDir = args.count > 2 ? args[2] : "/Users/leon/工程/Code/personal-projects/yaology/sirius/assets/AppIcon.iconset"

let masterURL = URL(fileURLWithPath: sourcePath)
guard let nsImg = NSImage(contentsOf: masterURL),
      let tiff = nsImg.tiffRepresentation,
      let masterRep = NSBitmapImageRep(data: tiff),
      let masterCG = masterRep.cgImage else {
    fputs("Error: Unable to load master image at \(sourcePath)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(atPath: outputDir)
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let width = 1024
let height = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

let targetSquircleSize: CGFloat = 824.0
let targetSquircleCorner: CGFloat = 185.0
let targetSquircleOrigin = (1024.0 - targetSquircleSize) / 2.0

guard let masterCtx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

masterCtx.clear(CGRect(x: 0, y: 0, width: width, height: height))

// Soft Apple-standard squircle drop shadow
masterCtx.saveGState()
masterCtx.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))

let squircleRect = CGRect(x: targetSquircleOrigin, y: targetSquircleOrigin, width: targetSquircleSize, height: targetSquircleSize)
let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: targetSquircleCorner, cornerHeight: targetSquircleCorner, transform: nil)

masterCtx.addPath(squirclePath)
masterCtx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0))
masterCtx.fillPath()
masterCtx.restoreGState()

// Clip to squircle and draw scaled master image
masterCtx.saveGState()
masterCtx.addPath(squirclePath)
masterCtx.clip()

let scaleFactor = targetSquircleSize / 772.0
let scaledWidth = 1024.0 * scaleFactor
let scaledHeight = 1024.0 * scaleFactor
let scaledOriginX = (1024.0 - scaledWidth) / 2.0
let scaledOriginY = (1024.0 - scaledHeight) / 2.0

masterCtx.draw(masterCG, in: CGRect(x: scaledOriginX, y: scaledOriginY, width: scaledWidth, height: scaledHeight))
masterCtx.restoreGState()

guard let baseAlphaCG = masterCtx.makeImage() else { exit(1) }
let baseCI = CIImage(cgImage: baseAlphaCG)
let ciContext = CIContext(options: nil)

// Optical Sizing Filter
let maskFilter = CIFilter(name: "CIRadialGradient")!
maskFilter.setValue(CIVector(x: 512, y: 512), forKey: "inputCenter")
maskFilter.setValue(280, forKey: "inputRadius0")
maskFilter.setValue(380, forKey: "inputRadius1")
maskFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
maskFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
let innerMask = maskFilter.outputImage!.cropped(to: baseCI.extent)

func renderIcon(size: Int, boost: CGFloat, dilate: CGFloat) -> NSImage {
    let targetSize = CGFloat(size)
    let scale = targetSize / 1024.0
    var proc = baseCI
    
    if boost > 1.0 || dilate > 0 {
        let thresh = CIFilter(name: "CIColorControls")!
        thresh.setValue(proc, forKey: kCIInputImageKey)
        thresh.setValue(1.5, forKey: kCIInputContrastKey)
        thresh.setValue(0.08, forKey: kCIInputBrightnessKey)
        var h = thresh.outputImage!
        
        let maskedH = CIFilter(name: "CIBlendWithMask")!
        maskedH.setValue(h, forKey: kCIInputImageKey)
        maskedH.setValue(CIImage(color: CIColor.clear).cropped(to: proc.extent), forKey: kCIInputBackgroundImageKey)
        maskedH.setValue(innerMask, forKey: kCIInputMaskImageKey)
        h = maskedH.outputImage!
        
        if dilate > 0 {
            let m = CIFilter(name: "CIMorphologyMaximum")!
            m.setValue(h, forKey: kCIInputImageKey)
            m.setValue(dilate, forKey: kCIInputRadiusKey)
            h = m.outputImage ?? h
        }
        
        let exp = CIFilter(name: "CIExposureAdjust")!
        exp.setValue(h, forKey: kCIInputImageKey)
        exp.setValue(log2(boost), forKey: kCIInputEVKey)
        h = exp.outputImage ?? h
        
        let blend = CIFilter(name: "CIScreenBlendMode")!
        blend.setValue(h, forKey: kCIInputImageKey)
        blend.setValue(proc, forKey: kCIInputBackgroundImageKey)
        proc = blend.outputImage ?? proc
    }
    
    let lanczos = CIFilter(name: "CILanczosScaleTransform")!
    lanczos.setValue(proc, forKey: kCIInputImageKey)
    lanczos.setValue(scale, forKey: kCIInputScaleKey)
    lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
    let scaled = lanczos.outputImage ?? proc
    
    let cgImg = ciContext.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))!
    return NSImage(cgImage: cgImg, size: NSSize(width: targetSize, height: targetSize))
}

func saveIconPNG(img: NSImage, filename: String) {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    let path = "\(outputDir)/\(filename)"
    try? png.write(to: URL(fileURLWithPath: path))
}

// 1024px & 512px: Pure Master (zero boost, pure cinema fidelity)
saveIconPNG(img: renderIcon(size: 1024, boost: 1.0, dilate: 0), filename: "icon_512x512@2x.png")
saveIconPNG(img: renderIcon(size: 512, boost: 1.0, dilate: 0), filename: "icon_512x512.png")
saveIconPNG(img: renderIcon(size: 512, boost: 1.0, dilate: 0), filename: "icon_256x256@2x.png")

// 256px: Subtle optical preservation (1.15x)
saveIconPNG(img: renderIcon(size: 256, boost: 1.15, dilate: 0), filename: "icon_256x256.png")
saveIconPNG(img: renderIcon(size: 256, boost: 1.15, dilate: 0), filename: "icon_128x128@2x.png")

// 128px: Medium optical boost (1.35x)
saveIconPNG(img: renderIcon(size: 128, boost: 1.35, dilate: 0.5), filename: "icon_128x128.png")

// 64px: High optical boost (1.8x, dilate 1.0)
saveIconPNG(img: renderIcon(size: 64, boost: 1.8, dilate: 1.0), filename: "icon_32x32@2x.png")

// 32px: Retina small optical boost (2.2x, dilate 1.5)
saveIconPNG(img: renderIcon(size: 32, boost: 2.2, dilate: 1.5), filename: "icon_32x32.png")
saveIconPNG(img: renderIcon(size: 32, boost: 2.2, dilate: 1.5), filename: "icon_16x16@2x.png")

// 16px: Micro optical boost (2.8x, dilate 2.0)
saveIconPNG(img: renderIcon(size: 16, boost: 2.8, dilate: 2.0), filename: "icon_16x16.png")

print("Multi-scale optical icons successfully generated in \(outputDir)")
