import Foundation

/// An array decoded one element at a time: an element that fails to decode is skipped, so one bad
/// entry in the config file costs only itself.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    /// Takes any value at all, so the container always moves past the bad element.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.elements = elements
    }
}
