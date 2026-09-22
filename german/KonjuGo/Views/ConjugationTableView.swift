import SwiftUI

struct ConjugationTableView: View {
    let table: TenseTable
    @Binding var ruleExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var irregularColor: Color { colorScheme == .dark ? .orange : Color(red: 0.70, green: 0.29, blue: 0.02) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(table.tense.title).font(.title2.weight(.semibold))
                    Text(table.tense.english).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Irregular part", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(irregularColor)
                    .accessibilityLabel("Orange letters indicate an irregular part of the studied verb")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(table.rule).font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        ruleExpanded.toggle()
                    } label: {
                        Image(systemName: ruleExpanded ? "info.circle.fill" : "info.circle").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ruleExpanded ? "Hide conjugation rule" : "Explain conjugation rule")
                    .accessibilityValue(ruleExpanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("ruleInfo")
                }
                if ruleExpanded {
                    Text(table.explanation).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled).accessibilityIdentifier("ruleExplanation")
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 0) {
                ForEach(table.orderedRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.person.title).font(.body).foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Text(attributed(row)).font(.title3.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityDescription)
                    .accessibilityIdentifier("row_\(row.person.rawValue)")
                    .help(row.irregularExplanation ?? "Regular form in this tense")
                    if row.person != table.tense.persons.last { Divider().padding(.horizontal, 16) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
        }
    }

    private func attributed(_ row: ConjugationRow) -> AttributedString {
        var text = AttributedString()
        for segment in row.segments {
            var part = AttributedString(segment.text)
            part.foregroundColor = segment.isIrregular ? irregularColor : .primary
            text.append(part)
        }
        return text
    }
}
