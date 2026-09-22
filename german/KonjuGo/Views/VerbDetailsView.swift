import SwiftUI

struct VerbDetailsView: View {
    let verb: VerbProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verb.infinitive).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .textSelection(.enabled).accessibilityIdentifier("verbTitle")
                Text(verb.meaning).font(.title3).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { badges }
                VStack(alignment: .leading, spacing: 8) { badges }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("VERB PARTS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Text(verb.components.joined(separator: " + "))
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(componentLabels).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 14) {
                part("Present · er/sie/es", verb.principalParts.present)
                part("Simple past · er/sie/es", verb.principalParts.past)
                part("Past participle", verb.principalParts.participle)
                part("Perfect auxiliary", verb.principalParts.auxiliary.rawValue)
            }
            if let note = verb.usageNote, !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var badges: some View {
        badge(verb.inflection.title)
        badge(verb.reflexivity.title + (verb.reflexiveCase.map { " · \($0.rawValue)" } ?? ""))
        if verb.prefixBehavior != .none { badge(verb.prefixBehavior.title) }
    }
    private func badge(_ title: String) -> some View {
        Text(title).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.7), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
    private func part(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var componentLabels: String {
        ((verb.usesReflexivePronoun ? ["reflexive pronoun"] : [])
         + (verb.prefix == nil ? [] : ["prefix"]) + ["stem", "infinitive ending"]).joined(separator: " + ")
    }
}
