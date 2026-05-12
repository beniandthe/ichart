import Foundation

enum ChordGlyphTemplateLibrary {
    static let initialTemplates: [GestureTemplate] = [
        template("A", [
            stroke([(10, 60), (25, 12), (42, 60)]),
            stroke([(17, 39), (35, 39)])
        ]),
        template("B", [
            stroke([(10, 12), (10, 35), (10, 60)]),
            stroke([(10, 12), (38, 18), (25, 35), (39, 48), (10, 60)])
        ]),
        template("C", [
            stroke([(34, 12), (21, 15), (12, 28), (15, 44), (28, 55), (43, 51)])
        ]),
        template("D", [
            stroke([(10, 12), (10, 60)]),
            stroke([(10, 12), (42, 20), (39, 50), (10, 60)])
        ]),
        template("E", [
            stroke([(38, 12), (10, 12), (10, 35), (10, 60), (40, 60)]),
            stroke([(10, 35), (33, 35)])
        ]),
        template("F", [
            stroke([(10, 12), (10, 60)]),
            stroke([(10, 13), (36, 13)]),
            stroke([(10, 34), (29, 34)])
        ]),
        template("G", [
            stroke([(40, 16), (18, 14), (10, 36), (24, 58), (45, 48), (33, 40)])
        ]),
        template("#", [
            stroke([(56, 20), (54, 56)]),
            stroke([(73, 20), (71, 56)]),
            stroke([(50, 33), (78, 30)]),
            stroke([(51, 45), (79, 42)])
        ]),
        template("b", [
            stroke([(58, 18), (58, 57), (70, 48), (61, 39)])
        ]),
        template("△", [
            stroke([(58, 52), (69, 24), (82, 52), (58, 52)])
        ]),
        template("°", [
            stroke([(62, 30), (68, 22), (77, 25), (79, 34), (72, 41), (63, 38), (62, 30)])
        ]),
        template("ø", [
            stroke([(62, 30), (68, 22), (77, 25), (79, 34), (72, 41), (63, 38), (62, 30)]),
            stroke([(61, 43), (81, 20)])
        ]),
        template("+", [
            stroke([(68, 23), (68, 51)]),
            stroke([(55, 37), (81, 37)])
        ]),
        template("m", [
            stroke([(10, 55), (10, 31), (19, 42), (27, 31), (36, 42), (45, 31), (45, 55)])
        ]),
        template("-", [
            stroke([(62, 36), (79, 36)])
        ]),
        template("6", [
            stroke([(107, 16), (91, 25), (88, 43), (101, 58), (119, 49), (113, 34), (95, 39)])
        ]),
        template("7", [
            stroke([(87, 16), (108, 16), (96, 57)])
        ]),
        template("9", [
            stroke([(160, 17), (179, 19), (178, 39), (160, 39), (177, 58)])
        ]),
        template("(", [
            stroke([(80, 15), (68, 28), (68, 48), (80, 61)])
        ]),
        template(")", [
            stroke([(92, 15), (104, 28), (104, 48), (92, 61)])
        ]),
        template("1", [
            stroke([(20, 18), (28, 12), (28, 58)])
        ]),
        template("3", [
            stroke([(12, 16), (36, 18), (24, 34), (39, 50), (12, 58)])
        ]),
        template("5", [
            stroke([(39, 16), (17, 16), (14, 34), (34, 35), (38, 50), (19, 58)])
        ]),
        template("/", [
            stroke([(71, 58), (87, 12)])
        ])
    ]

    private static func template(_ text: String, _ strokes: [InkStroke]) -> GestureTemplate {
        GestureTemplate(text: text, strokes: strokes)
    }

    private static func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(
            points: points.map { x, y in
                InkPoint(x: x, y: y, timeOffset: nil)
            }
        )
    }
}
