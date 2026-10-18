import CidreBridge
import SwiftUI

/// La barre d'un disque de jeux : les jeux Cidre, le reste de ce qui est
/// occupe, le libre ; et, en dessous, les valeurs.
struct DiskUsageBar: View {
    let usage: DiskUsage
    var height: CGFloat = 10
    var showsLegend = true

    static let gamesColor = Color.accentColor
    static let otherColor = Color.secondary.opacity(0.55)
    static let freeColor = Color.secondary.opacity(0.15)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(Self.gamesColor)
                        .frame(width: geometry.size.width * usage.gamesFraction)
                    Rectangle().fill(Self.otherColor)
                        .frame(width: geometry.size.width * usage.otherFraction)
                    Rectangle().fill(usage.isNearlyFull ? Color.orange.opacity(0.25) : Self.freeColor)
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: usage.summary))
            if showsLegend {
                legend
            }
        }
        .help(Text(verbatim: usage.summary))
    }

    /// En entier si la place le permet ; sinon les seules valeurs, a cote de
    /// leur couleur (une fenetre etroite, comme les Reglages).
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            fullLegend
            HStack(spacing: 10) {
                item(Self.gamesColor, L10n.bytes(usage.gamesBytes))
                item(Self.otherColor, L10n.bytes(usage.otherBytes))
                item(Self.freeColor, L10n.format("%@ libres", L10n.bytes(usage.freeBytes)))
                    .foregroundStyle(usage.isNearlyFull ? Color.orange : Color.secondary)
                Spacer(minLength: 0)
                Text(verbatim: L10n.format("sur %@", L10n.bytes(usage.totalBytes)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var fullLegend: some View {
        HStack(spacing: 12) {
            item(Self.gamesColor, L10n.format("Jeux Cidre : %@", L10n.bytes(usage.gamesBytes)))
            item(Self.otherColor, L10n.format("Autres : %@", L10n.bytes(usage.otherBytes)))
            item(Self.freeColor, L10n.format("Libre : %@", L10n.bytes(usage.freeBytes)))
                .foregroundStyle(usage.isNearlyFull ? Color.orange : Color.secondary)
            Spacer(minLength: 0)
            Text(verbatim: L10n.format("sur %@", L10n.bytes(usage.totalBytes)))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: text)
        }
    }
}
