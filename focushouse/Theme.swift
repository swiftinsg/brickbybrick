import SwiftUI
import CoreText

/// The pixel look: Pixelify Sans for headings and labels, chunky square borders,
/// brick meters. Body text stays the system font so it reads well at any size.
enum Theme {
    /// Registers the bundled pixel font (no Info.plist entry needed).
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Pixelify Sans, scaling with Dynamic Type like `style`.
    static func pixel(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Pixelify Sans", size: size, relativeTo: style)
    }
}

extension Color {
    static let ink = Color(light: 0x2B2340, dark: 0xF3EBDD)
    static let paper = Color(light: 0xFFF3DC, dark: 0x1C1826)
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2436)
    static let track = Color(light: 0xEDE6DA, dark: 0x3A3348)
    static let brick = Color(light: 0xB34A34, dark: 0xD9664D)
    static let grass = Color(light: 0x417A3A, dark: 0x74B463)
    static let gold = Color(light: 0xFFE8B0, dark: 0x8A6A2C)
    static let wall = Color(light: 0xF6EFE2, dark: 0x332C40)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A square card with a thick pixel outline.
    func pixelBox(_ fill: Color = .card) -> some View {
        background(fill).overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 3))
    }
}

extension View {
    /// The paper behind a list or form, as on Home.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.paper)
    }

    /// Home's look for a screen: an inline title in the pixel font, on paper.
    func pixelTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.pixel(22, relativeTo: .headline).weight(.bold))
                }
            }
            .paperBackground()
    }
}

extension Image {
    /// A pixel-art asset scaled up without blurring.
    func pixelArt() -> some View {
        resizable().interpolation(.none).aspectRatio(contentMode: .fit)
    }
}

/// A row of 10 bricks that fills up, with a label and a value on the right.
struct BrickMeter: View {
    let title: String
    let detail: String
    let filled: Int
    let color: Color
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.pixel(16, relativeTo: .subheadline).weight(.bold))
                Spacer()
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle().fill(Color.track).frame(height: 18)
                        .overlay {
                            Rectangle().fill(color)
                                .scaleEffect(i < shown ? 1 : 0.2)
                                .opacity(i < shown ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.5).delay(Double(i) * 0.06), value: shown)
                        }
                }
            }
            .padding(5)
            .pixelBox()
        }
        .onAppear { shown = filled }
        .onChange(of: filled) { shown = filled }
        .accessibilityElement(children: .combine)
    }
}

/// A number drawn as bold 5×7 pixel blocks: pixel style, but every digit is
/// unmistakable (Pixelify Sans's 8 looks like an S at small sizes).
struct PixelNumber: View {
    let value: Int
    @ScaledMetric private var px: CGFloat

    /// `size`: points per pixel block at the default text size.
    init(value: Int, size: CGFloat = 3) {
        self.value = value
        _px = ScaledMetric(wrappedValue: size, relativeTo: .title3)
    }

    private static let glyphs = [
        "01110100011000110001100011000101110", "00100011000010000100001000010001110",
        "01110100010000100010001000100011111", "11110000010000101110000010000111110",
        "00010001100101010010111110001000010", "11111100001111000001000011000101110",
        "00110010001000011110100011000101110", "11111000010001000100010000100001000",
        "01110100011000101110100011000101110", "01110100011000101111000010001001100",
    ]

    var body: some View {
        let digits = String(value).compactMap(\.wholeNumberValue)
        Canvas { ctx, _ in
            for (i, d) in digits.enumerated() {
                for (j, c) in Self.glyphs[d].enumerated() where c == "1" {
                    // 2 px wide = bold, like classic bitmap fonts
                    ctx.fill(Path(CGRect(x: CGFloat(i * 7 + j % 5) * px, y: CGFloat(j / 5) * px, width: 2 * px, height: px)),
                             with: .foreground)
                }
            }
        }
        .frame(width: CGFloat(digits.count * 7 - 1) * px, height: 7 * px)
        .accessibilityLabel("\(value)")
    }
}

extension House.State {
    var title: String { rawValue.capitalized }

    var message: String {
        switch self {
        case .calm: "Stress is low. Keep it steady."
        case .stressed: "A few busy days in a row. Plan some rest."
        case .overloaded: "Carrying too much for too long. Take a real break."
        case .crumbling: "Too many high-stress days. Rest to repair."
        case .resting: "You rested today. Rebuilding one step."
        }
    }

    /// Sky behind the sprite, darker as stress builds.
    var sky: Color {
        switch self {
        case .calm: Color(red: 0.80, green: 0.91, blue: 1.0)
        case .stressed: Color(red: 0.89, green: 0.91, blue: 0.93)
        case .overloaded: Color(red: 0.73, green: 0.76, blue: 0.81)
        case .crumbling: Color(red: 0.60, green: 0.64, blue: 0.70)
        case .resting: Color(red: 0.18, green: 0.21, blue: 0.35)
        }
    }
}
