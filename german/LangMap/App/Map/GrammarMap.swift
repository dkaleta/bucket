import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GrammarTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let colorIndex: Int
    let children: [GrammarTopic]

    static let branches: [GrammarTopic] = [
        branch("structure", "Sentence structure", 0, ["Statements", "Questions", "Verb position", "Subordinate clauses"]),
        branch("verbs", "Verbs", 1, ["Conjugation", "Strong and weak verbs", "Separable prefixes", "Reflexive verbs", "Auxiliary verbs"]),
        branch("tenses", "Tenses and moods", 2, ["Present", "Past", "Future", "Indicative", "Imperative", "Subjunctive"]),
        branch("nouns", "Nouns and articles", 3, ["Gender", "Plurals", "Definite articles", "Indefinite articles"]),
        branch("cases", "Cases and agreement", 4, ["Nominative", "Accusative", "Dative", "Genitive", "Adjective endings"]),
        branch("connections", "Connecting ideas", 5, ["Prepositions", "Coordinating conjunctions", "Subordinating conjunctions", "Negation"])
    ]

    private static func branch(_ id: String, _ title: String, _ color: Int, _ children: [String]) -> Self {
        Self(id: id, title: title, colorIndex: color, children: children.enumerated().map {
            Self(id: "\(id).\($0.offset)", title: $0.element, colorIndex: color, children: [])
        })
    }
}

struct MapCamera: Equatable {
    var scale: CGFloat = 1
    var offset = CGPoint.zero

    func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
    }

    func world(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    mutating func zoom(to newScale: CGFloat, around anchor: CGPoint) {
        let fixedPoint = world(anchor)
        scale = newScale
        offset = CGPoint(x: anchor.x - fixedPoint.x * scale, y: anchor.y - fixedPoint.y * scale)
    }

    mutating func pan(by delta: CGSize) {
        offset.x += delta.width
        offset.y += delta.height
    }
}

struct MapNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let colorIndex: Int
    let center: CGPoint
    let size: CGSize
    let unitScale: CGFloat
    let isRoot: Bool

    var bounds: CGRect {
        CGRect(x: center.x - size.width * unitScale / 2,
               y: center.y - size.height * unitScale / 2,
               width: size.width * unitScale, height: size.height * unitScale)
    }
}

enum MapLayout {
    static let palette: [Color] = [.teal, .orange, .indigo, .pink, .blue, .purple]

    static func textWidth(_ text: String, fontSize: CGFloat, bold: Bool = false) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .medium)
        #else
        let font = UIFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .medium)
        #endif
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func nodes(branch: GrammarTopic? = nil, origin: CGPoint = .zero, unit: CGFloat = 1) -> [MapNode] {
        let topics = branch?.children ?? GrammarTopic.branches
        let rootTitle = branch?.title ?? "German"
        let rootSubtitle = branch == nil ? "GRAMMAR MAP" : "\(topics.count) TOPICS"
        let subtitleWidth = textWidth(rootSubtitle, fontSize: 10) + CGFloat(rootSubtitle.count - 1) * 1.7
        var result = [MapNode(id: branch?.id ?? "german", title: rootTitle,
                              subtitle: rootSubtitle,
                              colorIndex: branch?.colorIndex ?? -1, center: origin,
                              size: CGSize(width: max(textWidth(rootTitle, fontSize: 23, bold: true) + 64,
                                                      subtitleWidth + 40), height: 94),
                              unitScale: unit, isRoot: true)]
        // Two balanced columns keep longer labels readable and connectors separate.
        let leftCount = (topics.count + 1) / 2
        for (index, topic) in topics.enumerated() {
            let isLeft = index < leftCount
            let row = isLeft ? index : index - leftCount
            let count = isLeft ? leftCount : topics.count - leftCount
            let y = (CGFloat(row) - CGFloat(count - 1) / 2) * 205
            result.append(MapNode(id: topic.id, title: topic.title,
                                  subtitle: topic.children.isEmpty ? "" : "\(topic.children.count) topics",
                                  colorIndex: topic.colorIndex,
                                  center: CGPoint(x: origin.x + (isLeft ? -365 : 365) * unit, y: origin.y + y * unit),
                                  size: CGSize(width: max(166, textWidth(topic.title, fontSize: 17) + 48),
                                               height: topic.children.isEmpty ? 60 : 76),
                                  unitScale: unit, isRoot: false))
        }
        return result
    }

    static func bounds(of nodes: [MapNode]) -> CGRect {
        nodes.reduce(CGRect.null) { $0.union($1.bounds) }
    }

    static func fitScale(nodes: [MapNode], viewport: CGSize) -> CGFloat {
        let bounds = bounds(of: nodes)
        return max(0.05, min((max(viewport.width, 200) - 100) / bounds.width,
                            (max(viewport.height, 200) - 100) / bounds.height, 1.2))
    }

    static func hit(at screenPoint: CGPoint, camera: MapCamera, nodes: [MapNode]) -> MapNode? {
        let point = camera.world(screenPoint)
        return nodes.reversed().first { $0.bounds.contains(point) }
    }
}
