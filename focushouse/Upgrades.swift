import SwiftUI

/// Furniture bought with bricks. Sprites are 24×24 grids from `Art/furniture*.json`,
/// drawn at runtime, so the JSON is the only copy of the art.
struct Furniture: Decodable, Identifiable, Hashable {
    let name, tag, description: String
    let hobby: String?
    let level, cost: Int
    let grid: [String]
    var id: String { name }
    /// A Lv 2 item upgrades the Lv 1 item in the same group.
    var group: String { hobby ?? name }
}

/// The catalogue and the plain rules for buying. Bought items are saved by name
/// in UserDefaults ("owned"); spending is their total cost, taken off earned bricks.
enum Shop {
    enum State: Equatable { case owned, buy, needs(String), short(Int) }

    private struct File: Decodable { var palette: [String: String]?; var items: [Furniture] }

    static let catalog: (items: [Furniture], palette: [Character: Color]) = {
        let files = ["furniture", "furniture_hobbies"].compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode(File.self, from: $0) }
        }
        var palette: [Character: Color] = [:]
        for (k, v) in files.compactMap(\.palette).joined() {
            let n = UInt32(v.dropFirst(), radix: 16) ?? 0
            palette[Character(k)] = Color(red: Double(n >> 16 & 255) / 255, green: Double(n >> 8 & 255) / 255, blue: Double(n & 255) / 255)
        }
        return (files.flatMap(\.items), palette)
    }()
    static var items: [Furniture] { catalog.items }

    static func owned(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }

    static func spent(_ owned: Set<String>, in items: [Furniture] = items) -> Int {
        items.filter { owned.contains($0.name) }.reduce(0) { $0 + $1.cost }
    }

    static func state(_ item: Furniture, owned: Set<String>, balance: Int, in items: [Furniture] = items) -> State {
        if owned.contains(item.name) { return .owned }
        if let base = items.first(where: { $0.group == item.group && $0.level == item.level - 1 }),
           !owned.contains(base.name) { return .needs(base.name) }
        return balance >= item.cost ? .buy : .short(item.cost - balance)
    }

    /// What's in the room: the highest level bought in each group.
    static func room(_ owned: Set<String>) -> [Furniture] {
        Dictionary(grouping: items.filter { owned.contains($0.name) }, by: \.group).values
            .compactMap { $0.max { $0.level < $1.level } }
            .sorted { $0.name < $1.name }
    }

    /// How many things fit inside the house at once.
    static let roomCap = 4

    /// The house's spots, `roomCap` of them, each a furniture group or "" when empty.
    /// Saved one per line in UserDefaults ("placed"), by group so upgrading
    /// Lv 1 → Lv 2 keeps its spot.
    static func slots(_ raw: String) -> [String] {
        let s = raw.components(separatedBy: "\n")
        return Array((s + Array(repeating: "", count: roomCap)).prefix(roomCap))
    }

    /// What stands in each spot (nil = empty).
    static func placed(_ raw: String, owned: Set<String>) -> [Furniture?] {
        let room = room(owned)
        return slots(raw).map { g in room.first { $0.group == g } }
    }

    /// Drops a group on spot `i`. Moving within the house swaps with whatever is
    /// there; bringing something new in replaces it.
    static func put(_ group: String, at i: Int, in raw: String) -> String {
        var s = slots(raw)
        if let from = s.firstIndex(of: group) { s.swapAt(from, i) } else { s[i] = group }
        return s.joined(separator: "\n")
    }

    /// Takes a group out, or puts it in the first empty spot.
    static func toggle(_ group: String, in raw: String) -> String {
        var s = slots(raw)
        if let i = s.firstIndex(of: group) { s[i] = "" }
        else if let i = s.firstIndex(of: "") { s[i] = group }
        return s.joined(separator: "\n")
    }
}

/// Inside the house: a pixel room (wallpaper, window, plank floor) drawn at the
/// furniture sprites' own pixel size, with furniture standing in `roomCap` spots.
/// Long-press and drag to move things between spots, or drop something from
/// "Your things" onto a spot. Opens from the house's door on Home.
struct RoomView: View {
    @AppStorage("owned") private var ownedRaw = ""
    @AppStorage("placed") private var placedRaw = ""
    @State private var target: Int?

    /// The room in sprite pixels: 4 spots of 24, a pixel apart, with a margin.
    static let size = CGSize(width: 106, height: 64)
    static func spotX(_ i: Int) -> Int { 4 + i * 25 }
    static let spotY = 29          // a sprite's bottom row lands on floor row 52

    var body: some View {
        let owned = Shop.owned(ownedRaw)
        let slots = Shop.placed(placedRaw, owned: owned)
        let items = slots.compactMap { $0 }

        GeometryReader { geo in
            let px = geo.size.width / Self.size.width
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in Self.draw(ctx, px: px, filled: slots.map { $0 != nil }) }
                ForEach(slots.indices, id: \.self) { i in
                    spot(slots[i], px: px)
                        .overlay { if target == i { Rectangle().strokeBorder(Color.gold, lineWidth: 3) } }
                        .dropDestination(for: String.self) { groups, _ in
                            // only things the student owns, not any text dragged in from elsewhere
                            guard let g = groups.first, Shop.room(owned).contains(where: { $0.group == g }) else { return false }
                            withAnimation(.snappy) { placedRaw = Shop.put(g, at: i, in: placedRaw) }
                            return true
                        } isTargeted: { on in
                            if on { target = i } else if target == i { target = nil }
                        }
                        .frame(width: 24 * px, height: 24 * px)
                        .position(x: (CGFloat(Self.spotX(i)) + 12) * px, y: (CGFloat(Self.spotY) + 12) * px)
                }
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .pixelBox(Color.wall)
        .sensoryFeedback(.selection, trigger: placedRaw)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.isEmpty ? "Inside your house: empty" : "Inside your house: " + items.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder private func spot(_ item: Furniture?, px: CGFloat) -> some View {
        if let item {
            PixelSprite(grid: item.grid)
                .draggable(item.group) { PixelSprite(grid: item.grid).frame(width: 72) }
        } else {
            // an empty spot: a dashed footprint on the floor
            Rectangle().strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(height: 8 * px)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, -1 * px)
                .contentShape(Rectangle())
        }
    }

    /// The room itself, in fixed pixel-art colours like the house sprites.
    static func draw(_ ctx: GraphicsContext, px: CGFloat, filled: [Bool]) {
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: UInt32, _ opacity: Double = 1) {
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px + 0.5, height: CGFloat(h) * px + 0.5)),
                     with: .color(Color(light: hex, dark: hex).opacity(opacity)))
        }
        let w = Int(size.width), h = Int(size.height)
        fill(0, 0, w, 45, 0xF4E7CE)                                          // wallpaper
        for x in stride(from: 3, to: w, by: 6) { fill(x, 2, 1, 40, 0xE6D3AF) } // stripes
        fill(0, 0, w, 2, 0x553A22)                                           // ceiling beam
        fill(40, 6, 26, 18, 0x6A4426)                                        // window frame
        for (x, y, c) in [(42, 8, 0x8ECFE6), (54, 8, 0x8ECFE6), (42, 15, 0x4D93B0), (54, 15, 0x4D93B0)] as [(Int, Int, UInt32)] {
            fill(x, y, 10, 6, c)
        }
        fill(43, 9, 1, 3, 0xF4FBFF); fill(55, 9, 1, 3, 0xF4FBFF)             // glints
        fill(39, 24, 28, 1, 0xE8F0FB)                                        // sill
        fill(0, 42, w, 3, 0x6A4426); fill(0, 42, w, 1, 0x91603A)             // skirting
        for (band, y) in stride(from: 45, to: h, by: 3).enumerated() {       // floor planks
            let rows = min(3, h - y)
            fill(0, y, w, rows, band % 2 == 0 ? 0x91603A : 0x7A5334)
            for x in stride(from: (band * 11) % 26, to: w, by: 26) { fill(x, y, 1, rows, 0x553A22) }
        }
        for (i, on) in filled.enumerated() where on {                       // soft shadow under furniture
            fill(spotX(i) + 2, spotY + 23, 20, 2, 0x2B2340, 0.25)
        }
    }
}

/// A furniture sprite, crisp at any size.
struct PixelSprite: View {
    let grid: [String]

    var body: some View {
        Canvas { ctx, size in
            let px = size.width / 24
            for (y, row) in grid.enumerated() {
                for (x, c) in row.enumerated() where c != "." {
                    guard let color = Shop.catalog.palette[c] else { continue }
                    // a hair wider so neighbouring pixels never show a seam
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.5, height: px + 0.5)), with: .color(color))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The furniture shop: wooden shelves of things to buy with bricks, and the
/// student's room on top. Opens from "Decorate with bricks" inside the house.
struct UpgradesView: View {
    let earned: Int
    @AppStorage("owned") private var ownedRaw = ""
    @AppStorage("placed") private var placedRaw = ""
    @State private var picked: Furniture?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let owned = Shop.owned(ownedRaw)
        let balance = earned - Shop.spent(owned)
        let room = Shop.room(owned)
        let placed = Shop.placed(placedRaw, owned: owned).compactMap { $0 }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Finish tasks to earn bricks, then spend them here. Bricks never repair the house: only rest does.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inside your house \(placed.count)/\(Shop.roomCap)").font(.pixel(20, relativeTo: .headline).weight(.bold))
                        RoomView()
                        Text(room.isEmpty ? "Buy something from the shelves below, then put it inside."
                                          : "Hold and drag your things onto a spot, or tap one to put it in or take it out.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !room.isEmpty {
                        shelf("Your things", room, owned: owned, balance: balance, placed: placed)
                    }
                    ForEach(["Work", "Hobbies", "Rest"], id: \.self) { tag in
                        shelf(tag, Shop.items.filter { $0.tag == tag }, owned: owned, balance: balance)
                    }
                }
                .padding()
            }
            .background(Color.paper)
            .navigationTitle("Upgrades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Upgrades").font(.pixel(22, relativeTo: .headline).weight(.bold))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BrickCount(value: max(0, balance))
                }
            }
            .sheet(item: $picked) { item in
                FurnitureDetail(item: item, state: Shop.state(item, owned: owned, balance: balance),
                                isPlaced: placed.contains { $0.group == item.group },
                                roomFull: placed.count >= Shop.roomCap) {
                    ownedRaw = (owned.union([item.name])).sorted().joined(separator: "\n")
                    // new things go straight inside while there's space
                    if item.level == 1, !placed.contains(where: { $0.group == item.group }) {
                        placedRaw = Shop.toggle(item.group, in: placedRaw)
                    }
                } place: {
                    placedRaw = Shop.toggle(item.group, in: placedRaw)
                }
            }
            .sensoryFeedback(.success, trigger: ownedRaw)
        }
    }

    /// A titled wooden shelf with items standing on the plank.
    private func shelf(_ title: String, _ items: [Furniture], owned: Set<String>, balance: Int, placed: [Furniture] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixel(20, relativeTo: .headline).weight(.bold))   // pixel caps B reads as G
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(items) { item in
                        let button = Button { picked = item } label: {
                            tile(item, Shop.state(item, owned: owned, balance: balance), placed: placed.contains(item))
                        }
                        .buttonStyle(.plain)
                        if owned.contains(item.name) {
                            button.draggable(item.group) { PixelSprite(grid: item.grid).frame(width: 72) }
                        } else {
                            button
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 18)   // items stand on the plank
            }
            .background(alignment: .bottom) { Plank() }
            .pixelBox(Color.wall)
        }
    }

    private func tile(_ item: Furniture, _ state: Shop.State, placed: Bool) -> some View {
        VStack(spacing: 6) {
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(2)
                .multilineTextAlignment(.center).frame(width: 92, height: 32, alignment: .bottom)
            PixelSprite(grid: item.grid).frame(width: 84)
                .opacity(state == .owned || state == .buy ? 1 : 0.55)
            PriceTag(item: item, state: state, placed: placed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(placed ? "in your house" : PriceTag.text(item, state))")
    }
}

/// The brick icon and a pixel number, as on Home's toolbar.
struct BrickCount: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image("icon.brick").pixelArt().frame(width: 28)
            PixelNumber(value: value).foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 6)
        .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : value) { $0.scaleEffect($1) } keyframes: { _ in
            SpringKeyframe(1.35, duration: 0.15)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) bricks")
    }
}

private struct PriceTag: View {
    let item: Furniture
    let state: Shop.State
    var placed = false

    static func text(_ item: Furniture, _ state: Shop.State) -> String {
        switch state {
        case .owned: "owned"
        case .needs(let base): "needs \(base) first"
        case .buy, .short: "\(item.cost) bricks"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            switch state {
            case .owned:
                Image(systemName: placed ? "house.fill" : "checkmark").font(.caption2.weight(.heavy))
                Text(placed ? "In house" : "Owned").font(.caption2.weight(.bold))
            case .needs:
                Image(systemName: "lock.fill").font(.caption2)
                Text("Lv 1 first").font(.caption2.weight(.bold))
            case .buy, .short:
                Image("icon.brick").pixelArt().frame(width: 14)
                PixelNumber(value: item.cost, size: 2)
            }
        }
        .foregroundStyle(state == .owned ? Color.white : Color.ink)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(state == .owned ? Color.grass : state == .buy ? Color.gold : Color.track)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
    }
}

/// A wooden shelf board along the bottom of a shelf.
private struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ink).frame(height: 3)
            Rectangle().fill(Color(red: 0.78, green: 0.56, blue: 0.33)).frame(height: 5)
            Rectangle().fill(Color(red: 0.60, green: 0.40, blue: 0.21)).frame(height: 7)
        }
    }
}

private struct FurnitureDetail: View {
    let item: Furniture
    let state: Shop.State
    let isPlaced: Bool
    let roomFull: Bool
    let buy: () -> Void
    let place: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var enabled: Bool { state == .buy || (state == .owned && (isPlaced || !roomFull)) }

    var body: some View {
        VStack(spacing: 16) {
            PixelSprite(grid: item.grid).frame(width: 168)
                .padding(16).frame(maxWidth: .infinity).pixelBox(Color.wall)
            VStack(spacing: 6) {
                Text(item.name).font(.pixel(26, relativeTo: .title2).weight(.bold))
                Text("\(item.tag) · \(item.hobby ?? item.name) · Lv \(item.level)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text(item.description).font(.subheadline).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Button {
                state == .owned ? place() : buy()
                dismiss()
            } label: {
                Group {
                    switch state {
                    case .owned: Text(isPlaced ? "Take out of house" : roomFull ? "House is full (\(Shop.roomCap)/\(Shop.roomCap))" : "Put in house")
                    case .needs(let base): Text("Buy \(base) first")
                    case .short(let n): Text("\(n) more bricks needed")
                    case .buy: Text("\(item.level > 1 ? "Upgrade" : "Buy") for \(item.cost) bricks")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity).padding()
                .pixelBox(enabled ? Color.gold : Color.track)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
        .padding(20)
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .presentationDetents([.medium, .large])
    }
}
