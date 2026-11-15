import AppKit

// Draws Tuck's app icon at 1024 px with CoreGraphics: a white glass chevron
// on a pink gradient, with two frosted "menu bar icon" tiles tucking in.
// Writes <outdir>/icon.png (rounded, for the README), icon-app.png and
// icon-app-small.png (full-bleed, for the .icns; small = 16/32 px, no tiles). Run scripts/make-icon.sh rather than this.

let out = CommandLine.arguments[1]
let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Apple's icon shape is close to a superellipse (n ≈ 5).
func squircle(_ r: CGRect, n: CGFloat = 4.3) -> CGPath {
  let p = CGMutablePath()
  let cx = r.midX, cy = r.midY, a = r.width / 2, b = r.height / 2
  let steps = 720
  for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
    let c = cos(t), s = sin(t)
    let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
    let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
  }
  p.closeSubpath()
  return p
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locs: [CGFloat]? = nil) {
  let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
  ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
  let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
  ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

struct Style {
  var name: String
  var bg: [CGColor]          // top -> bottom
  var glow: CGColor          // soft top light
  var glyphTop: CGColor, glyphBottom: CGColor
  var glyphShadow: CGColor
  var tile: CGColor, tileRim: CGColor
  var rim: CGColor
}

func chevronPath(width w: CGFloat, dx: CGFloat = 0) -> CGPath {
  // y up in CG: vertex left-middle, arms open to the right.
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 590 + dx, y: 742))
  p.addLine(to: CGPoint(x: 392 + dx, y: 512))
  p.addLine(to: CGPoint(x: 590 + dx, y: 282))
  return p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized()
}

func draw(_ st: Style, simple: Bool = false, fullBleed: Bool = false) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  let ns = NSGraphicsContext(bitmapImageRep: rep)!
  let ctx = ns.cgContext
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  // macOS 26+ masks app icons itself and boxes any icon that brings its own
  // shape and margins into a grey plate. So the app gets full-bleed square
  // art (the body scaled up to fill the canvas); the rounded, shadowed
  // version is only for the README.
  if fullBleed {
    ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: S / body.width, y: S / body.height); ctx.translateBy(x: -512, y: -512)
  }
  let shape = fullBleed ? CGPath(rect: body, transform: nil) : squircle(body)

  if !fullBleed {
  // Drop shadow under the whole icon.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.32))
  ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
  ctx.restoreGState()
  }

  // Background.
  ctx.saveGState()
  ctx.addPath(shape); ctx.clip()
  linear(ctx, st.bg, from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
  radial(ctx, [st.glow, st.glow.copy(alpha: 0)!], center: CGPoint(x: 400, y: 900), radius: 620)

  // Two "menu bar icons" tucking in behind the chevron: frosted glass tiles.
  // Small sizes drop the tiles, which would only be noise there.
  let tiles = simple ? [] : [CGRect(x: 600, y: 452, width: 120, height: 120), CGRect(x: 742, y: 466, width: 92, height: 92)]
  for (i, r) in tiles.enumerated() {
    let tp = CGPath(roundedRect: r, cornerWidth: r.width * 0.28, cornerHeight: r.width * 0.28, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: st.glyphShadow.copy(alpha: 0.35)!)
    ctx.addPath(tp); ctx.setFillColor(st.tile.copy(alpha: i == 0 ? st.tile.alpha : st.tile.alpha * 0.7)!); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tp); ctx.clip()
    linear(ctx, [rgb(0xffffff, 0.35), rgb(0xffffff, 0)], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.midY))
    ctx.restoreGState()
    ctx.addPath(tp); ctx.setStrokeColor(st.tileRim); ctx.setLineWidth(3); ctx.strokePath()
  }

  // The chevron: a thick glass stroke with a soft shadow, gradient body,
  // specular highlight along its top edge and a darker lower lip.
  let chev = simple ? chevronPath(width: 160, dx: 22) : chevronPath(width: 132)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: st.glyphShadow)
  ctx.addPath(chev); ctx.setFillColor(st.glyphBottom); ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(chev); ctx.clip()
  linear(ctx, [st.glyphTop, st.glyphBottom], from: CGPoint(x: 420, y: 760), to: CGPoint(x: 560, y: 270))
  // specular: a light sheet across the upper half
  radial(ctx, [rgb(0xffffff, 0.55), rgb(0xffffff, 0)], center: CGPoint(x: 470, y: 700), radius: 260)
  // inner rim: stroke the outline inside the clip, light on top, dark below
  ctx.addPath(chev); ctx.setLineWidth(10)
  ctx.replacePathWithStrokedPath(); ctx.clip()
  linear(ctx, [rgb(0xffffff, 0.75), rgb(0xffffff, 0.05), rgb(0x000000, 0.18)], from: CGPoint(x: 512, y: 760),
         to: CGPoint(x: 512, y: 270), locs: [0, 0.55, 1])
  ctx.restoreGState()

  // Glass edge on the icon itself (macOS draws its own on the masked app icon).
  if !fullBleed {
    ctx.addPath(shape); ctx.setLineWidth(4); ctx.replacePathWithStrokedPath(); ctx.clip()
    linear(ctx, [st.rim, st.rim.copy(alpha: 0)!, st.rim.copy(alpha: st.rim.alpha * 0.4)!],
           from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100), locs: [0, 0.5, 1])
  }
  ctx.restoreGState()

  ns.flushGraphics()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(st.name)\(fullBleed ? "-app" : "")\(simple ? "-small" : "").png"))
}

let tuck = Style(name: "icon", bg: [rgb(0xFF6FAE), rgb(0xE0156B)], glow: rgb(0xFFFFFF, 0.35),
                 glyphTop: rgb(0xFFFFFF), glyphBottom: rgb(0xFBE3EE), glyphShadow: rgb(0x7A0035, 0.45),
                 tile: rgb(0xFFFFFF, 0.38), tileRim: rgb(0xFFFFFF, 0.55), rim: rgb(0xFFFFFF, 0.6))
draw(tuck)                                  // README
draw(tuck, fullBleed: true)                 // app icon
draw(tuck, simple: true, fullBleed: true)   // app icon, 16 and 32 px
