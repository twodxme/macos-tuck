import AppKit
import SwiftUI

// Renders docs/privacy-light.png and docs/privacy-dark.png: the README's
// "privacy at a glance" card. Every line on it is a fact you can check in
// the README's Privacy and trust section. Run: scripts/make-trust-card.sh

struct Fact: Identifiable {
  let id = UUID()
  let symbol: String
  let title: String
  let detail: String
}

let facts = [
  Fact(symbol: "network.slash", title: "No network", detail: "Never connects to anything"),
  Fact(symbol: "eye.slash", title: "No tracking", detail: "No analytics or crash reports"),
  Fact(symbol: "lock.open", title: "No permissions", detail: "Accessibility only if you opt in"),
  Fact(symbol: "chevron.left.forwardslash.chevron.right", title: "Open source", detail: "MIT, zero dependencies"),
]

let pink = Color(red: 0xE0 / 255, green: 0x15 / 255, blue: 0x6B / 255)

struct Card: View {
  let dark: Bool
  var fg: Color { dark ? .white : Color(white: 0.1) }
  var sub: Color { dark ? Color(white: 0.62) : Color(white: 0.42) }
  var surface: Color { dark ? Color(white: 0.11) : .white }
  var tile: Color { dark ? Color(white: 0.16) : Color(white: 0.965) }
  var line: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07) }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 46, height: 46)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.44, blue: 0.68), pink], startPoint: .top, endPoint: .bottom)))
        VStack(alignment: .leading, spacing: 3) {
          Text("Data Not Collected")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(fg)
          Text("Tuck doesn't collect, store, or send any data.")
            .font(.system(size: 13))
            .foregroundStyle(sub)
        }
      }
      Grid(horizontalSpacing: 10, verticalSpacing: 10) {
        GridRow { tileView(facts[0]); tileView(facts[1]) }
        GridRow { tileView(facts[2]); tileView(facts[3]) }
      }
    }
    .padding(22)
    .frame(width: 520)
    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(surface))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(line, lineWidth: 1))
    .padding(14)
    .environment(\.colorScheme, dark ? .dark : .light)
  }

  func tileView(_ f: Fact) -> some View {
    HStack(spacing: 11) {
      Image(systemName: f.symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(pink)
        .frame(width: 30, height: 30)
        .background(Circle().fill(pink.opacity(dark ? 0.2 : 0.1)))
      VStack(alignment: .leading, spacing: 2) {
        Text(f.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(fg)
        Text(f.detail).font(.system(size: 11)).foregroundStyle(sub)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tile))
  }
}

@MainActor
func render(dark: Bool, to path: String) {
  let r = ImageRenderer(content: Card(dark: dark))
  r.scale = 2
  guard let cg = r.cgImage else { fatalError("render failed") }
  let rep = NSBitmapImageRep(cgImage: cg)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
MainActor.assumeIsolated {
  render(dark: false, to: "\(dir)/privacy-light.png")
  render(dark: true, to: "\(dir)/privacy-dark.png")
}
print("wrote \(dir)/privacy-light.png and \(dir)/privacy-dark.png")
