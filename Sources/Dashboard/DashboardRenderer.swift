import Foundation

enum DashboardPage: String, CaseIterable, Identifiable, Sendable {
    case date, time, alarm, weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: "Data"
        case .time: "Hora"
        case .alarm: "Alarme"
        case .weather: "Clima"
        }
    }
}

struct DashboardValues: Sendable {
    let date: Date
    let timeZone: TimeZone
    let twentyFourHour: Bool
    let alarmEnabled: Bool
    let alarmHour: Int
    let alarmMinute: Int
    let temperature: Double?
    let weatherCode: Int?
    var alarmConfigured: Bool = true
}

enum DashboardRenderer {
    static func render(page: DashboardPage, values: DashboardValues) -> [UInt8] {
        var frame = Frame()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = values.timeZone

        switch page {
        case .date:
            let date = calendar.dateComponents([.day, .month], from: values.date)
            frame.icon(.calendar, x: 4, color: .yellow)
            frame.pair(date.day ?? 1, date.month ?? 1, separator: .dash, color: .yellow)
        case .time:
            let time = calendar.dateComponents([.hour, .minute], from: values.date)
            let hour = time.hour ?? 0
            frame.icon(.clock, x: values.twentyFourHour ? 4 : 0, color: .cyan)
            frame.clockPair(hour, time.minute ?? 0, twentyFourHour: values.twentyFourHour, color: .cyan)
        case .alarm:
            guard values.alarmConfigured else {
                frame.icon(.bellOff, x: 4, color: .muted)
                frame.pair("--", "--", separator: .colon, color: .muted)
                break
            }
            let hour = min(23, max(0, values.alarmHour))
            let minute = min(59, max(0, values.alarmMinute))
            let color: Color = values.alarmEnabled ? .pink : .muted
            frame.icon(values.alarmEnabled ? .bell : .bellOff, x: values.twentyFourHour ? 4 : 0, color: color)
            frame.clockPair(hour, minute, twentyFourHour: values.twentyFourHour, color: color)
        case .weather:
            let weather = weatherIcon(for: values.weatherCode)
            frame.icon(weather.icon, x: 4, color: weather.color)
            let temperature = formattedTemperature(values.temperature)
            frame.text(temperature, x: (16 - Frame.textWidth(temperature)) / 2, y: 10, color: .sky)
        }
        return frame.rgb
    }

    private static func formattedTemperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        let rounded = Int(min(99, max(-99, value.rounded())))
        return "\(rounded)°"
    }

    private static func weatherIcon(for code: Int?) -> (icon: Icon, color: Color) {
        guard let code else { return (.unknown, .muted) }
        return switch code {
        case 0, 1: (.sun, .yellow)
        case 2, 3, 45, 48: (.cloud, .sky)
        case 51...67, 80...82: (.rain, .sky)
        case 71...77, 85, 86: (.snow, .sky)
        case 95, 96, 99: (.storm, .yellow)
        default: (.unknown, .muted)
        }
    }

    private enum Separator {
        case dash, colon
    }

    private struct Color {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        static let yellow = Color(red: 255, green: 204, blue: 57)
        static let cyan = Color(red: 48, green: 230, blue: 214)
        static let pink = Color(red: 255, green: 103, blue: 164)
        static let sky = Color(red: 105, green: 185, blue: 255)
        static let muted = Color(red: 137, green: 145, blue: 163)
    }

    private enum Icon {
        case calendar, clock, bell, bellOff, sun, cloud, rain, snow, storm, unknown

        var rows: [String] {
            switch self {
            case .calendar:
                [".#...#.", "#######", "#.....#", "#######", "#.#.#.#", "#.....#", "#######"]
            case .clock:
                ["..###..", ".#...#.", "#..#..#", "#..##.#", "#.....#", ".#...#.", "..###.."]
            case .bell:
                ["...#...", "..###..", ".#...#.", ".#...#.", ".#...#.", "#######", "...#..."]
            case .bellOff:
                ["...#...", "..####.", ".#..##.", ".#.###.", ".##..#.", "#######", ".#.#..."]
            case .sun:
                ["...#...", ".#...#.", "..###..", "#.#.#.#", "..###..", ".#...#.", "...#..."]
            case .cloud:
                [".......", "..###..", ".#...#.", "#.....#", "#.....#", ".#####.", "......."]
            case .rain:
                ["..###..", ".#...#.", "#.....#", ".#####.", ".#.#.#.", "#.#.#..", "......."]
            case .snow:
                ["...#...", "#..#..#", ".#.#.#.", "..###..", ".#.#.#.", "#..#..#", "...#..."]
            case .storm:
                ["..###..", ".#...#.", "#.....#", ".#####.", "..##...", "...##..", "...#..."]
            case .unknown:
                ["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."]
            }
        }
    }

    private struct Frame {
        var rgb = [UInt8](repeating: 0, count: 16 * 16 * 3)

        private static let glyphs: [Character: [String]] = [
            "0": ["###", "#.#", "#.#", "#.#", "###"],
            "1": [".#.", "##.", ".#.", ".#.", "###"],
            "2": ["###", "..#", "###", "#..", "###"],
            "3": ["###", "..#", "###", "..#", "###"],
            "4": ["#.#", "#.#", "###", "..#", "..#"],
            "5": ["###", "#..", "###", "..#", "###"],
            "6": ["###", "#..", "###", "#.#", "###"],
            "7": ["###", "..#", "..#", "..#", "..#"],
            "8": ["###", "#.#", "###", "#.#", "###"],
            "9": ["###", "#.#", "###", "..#", "###"],
            "A": [".#.", "#.#", "###", "#.#", "#.#"],
            "M": ["#.#", "###", "###", "#.#", "#.#"],
            "P": ["##.", "#.#", "##.", "#..", "#.."],
            "-": ["..", "..", "##", "..", ".."],
            "°": ["##", "##", "..", "..", ".."]
        ]

        private static func glyphWidth(_ character: Character) -> Int {
            glyphs[character]?.first?.count ?? 0
        }

        static func textWidth(_ text: String) -> Int {
            text.reduce(0) { $0 + glyphWidth($1) } + max(0, text.count - 1)
        }

        mutating func clockPair(_ hour: Int, _ minute: Int, twentyFourHour: Bool, color: Color) {
            let displayHour = twentyFourHour ? hour : (hour % 12 == 0 ? 12 : hour % 12)
            if !twentyFourHour {
                text(hour < 12 ? "AM" : "PM", x: 9, y: 2, color: color)
            }
            pair(displayHour, minute, separator: .colon, color: color)
        }

        mutating func pair(_ first: Int, _ second: Int, separator: Separator, color: Color) {
            pair(twoDigits(first), twoDigits(second), separator: separator, color: color)
        }

        mutating func pair(_ first: String, _ second: String, separator: Separator, color: Color) {
            text(first, x: (7 - Self.textWidth(first)) / 2, y: 10, color: color)
            text(second, x: 9 + (7 - Self.textWidth(second)) / 2, y: 10, color: color)
            switch separator {
            case .dash:
                pixel(x: 7, y: 12, color: color)
                pixel(x: 8, y: 12, color: color)
            case .colon:
                pixel(x: 7, y: 11, color: color)
                pixel(x: 7, y: 13, color: color)
            }
        }

        private func twoDigits(_ number: Int) -> String {
            number < 10 ? "0\(number)" : "\(number)"
        }

        mutating func icon(_ icon: Icon, x: Int, color: Color) {
            draw(icon.rows, x: x, y: 1, color: color)
        }

        mutating func text(_ text: String, x: Int, y: Int, color: Color) {
            var column = x
            for character in text {
                guard let glyph = Self.glyphs[character] else { continue }
                draw(glyph, x: column, y: y, color: color)
                column += Self.glyphWidth(character) + 1
            }
        }

        private mutating func draw(_ rows: [String], x: Int, y: Int, color: Color) {
            for (row, pattern) in rows.enumerated() {
                for (column, mark) in pattern.enumerated() where mark == "#" {
                    pixel(x: x + column, y: y + row, color: color)
                }
            }
        }

        private mutating func pixel(x: Int, y: Int, color: Color) {
            guard (0..<16).contains(x), (0..<16).contains(y) else { return }
            let index = (y * 16 + x) * 3
            rgb[index] = color.red
            rgb[index + 1] = color.green
            rgb[index + 2] = color.blue
        }
    }
}
