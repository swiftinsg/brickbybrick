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
/// student's room on top. Opens from the brick counter on Home.
struct UpgradesView: View {
    let earned: Int
    @AppStorage("owned") private var ownedRaw = ""
    @State private var picked: Furniture?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let owned = Shop.owned(ownedRaw)
        let balance = earned - Shop.spent(owned)
        let room = Shop.room(owned)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Finish tasks to earn bricks, then spend them here. Bricks never repair the house: only rest does.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if room.isEmpty {
                        Text("Your room is empty. Pick something from the shelves below.")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            .padding().pixelBox()
                    } else {
                        shelf("Your room", room, owned: owned, balance: balance)
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
                FurnitureDetail(item: item, state: Shop.state(item, owned: owned, balance: balance)) {
                    ownedRaw = (owned.union([item.name])).sorted().joined(separator: "\n")
                }
            }
            .sensoryFeedback(.success, trigger: ownedRaw)
        }
    }

    /// A titled wooden shelf with items standing on the plank.
    private func shelf(_ title: String, _ items: [Furniture], owned: Set<String>, balance: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixel(20, relativeTo: .headline).weight(.bold))   // pixel caps B reads as G
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(items) { item in
                        Button { picked = item } label: {
                            tile(item, Shop.state(item, owned: owned, balance: balance))
                        }
                        .buttonStyle(.plain)
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

    private func tile(_ item: Furniture, _ state: Shop.State) -> some View {
        VStack(spacing: 6) {
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(2)
                .multilineTextAlignment(.center).frame(width: 92, height: 32, alignment: .bottom)
            PixelSprite(grid: item.grid).frame(width: 84)
                .opacity(state == .owned || state == .buy ? 1 : 0.55)
            PriceTag(item: item, state: state)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(PriceTag.text(item, state))")
    }
}

/// The brick icon and a pixel number, as on Home's toolbar.
struct BrickCount: View {
    let value: Int
    var body: some View {
        HStack(spacing: 6) {
            Image("icon.brick").pixelArt().frame(width: 28)
            PixelNumber(value: value).foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) bricks")
    }
}

private struct PriceTag: View {
    let item: Furniture
    let state: Shop.State

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
                Image(systemName: "checkmark").font(.caption2.weight(.heavy))
                Text("Owned").font(.caption2.weight(.bold))
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
    let buy: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                buy()
                dismiss()
            } label: {
                Group {
                    switch state {
                    case .owned: Text("In your room")
                    case .needs(let base): Text("Buy \(base) first")
                    case .short(let n): Text("\(n) more bricks needed")
                    case .buy: Text("\(item.level > 1 ? "Upgrade" : "Buy") for \(item.cost) bricks")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity).padding()
                .pixelBox(state == .buy ? Color.gold : Color.track)
            }
            .buttonStyle(.plain)
            .disabled(state != .buy)
        }
        .padding(20)
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .presentationDetents([.medium, .large])
    }
}
