import Foundation

/// Bounded Qt6.8.3 ISODateWithMs comparison adapter. Raw storage stays unchanged.
/// Explicit zones and full HH:mm:ss only; local timezone/DST and other accepted
/// Qt forms are unsupported, never silently treated as an invalid date.
enum ReferenceDateMetadata {
    enum Failure: Error, Equatable { case unsupportedSyntax, resourceLimit }
    /// Empty output means invalid within the supported syntax (as vendor helper).
    static func normalize(_ input: String) throws -> String {
        guard input.utf8.count <= 64 else { throw Failure.resourceLimit }
        let regex = try NSRegularExpression(pattern: #"^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:[.,]([0-9]{1,9}))?([Zz]|[+-][0-9]{2}(?::?[0-9]{2})?)$"#)
        let range = NSRange(input.startIndex..<input.endIndex,in: input)
        guard let match = regex.firstMatch(in: input,range: range), match.range == range else { throw Failure.unsupportedSyntax }
        func text(_ i: Int) -> String {
            guard let range = Range(match.range(at: i),in: input) else { return "" }; return String(input[range])
        }
        var year = Int(text(1))!, month = Int(text(2))!, day = Int(text(3))!
        var hour = Int(text(4))!, minute = Int(text(5))!, second = Int(text(6))!
        func days(_ y: Int,_ m: Int) -> Int {
            if m == 2 { return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 29 : 28 }
            return [4,6,9,11].contains(m) ? 30 : 31
        }
        guard year > 0, (1...12).contains(month), day > 0, day <= days(year,month),
              hour <= 24, minute < 60, second < 60 else { return "" }
        let zone = text(8)
        var offset = 0
        if zone.lowercased() != "z" {
            let digits = String(zone.dropFirst()).replacingOccurrences(of: ":",with: "")
            let zh = Int(digits.prefix(2))!, zm = digits.count == 4 ? Int(digits.suffix(2))! : 0
            guard zh <= 23, zm < 60 else { return "" }
            offset = (zh * 60 + zm) * (zone.first == "-" ? -1 : 1)
            // Installed QTimeZone(int) actual oracle bounds, distinct from parser23h bound.
            guard abs(offset) <= 16 * 60 else { return "" }
        }
        let fraction = text(7)
        var millis = fraction.isEmpty ? 0 : Int((Double(fraction)! * pow(0.1,Double(fraction.count)) * 1000).rounded(.toNearestOrAwayFromZero))
        if millis == 1000 {
            millis = 0; second += 1
            if second == 60 { second = 0; minute += 1; if minute == 60 { minute = 0; hour += 1 } }
        }
        if hour == 24 && minute == 0 && second == 0 && millis == 0 {
            hour = 0; day += 1
            if day > days(year,month) { day = 1; month += 1; if month == 13 { month = 1; year += 1 } }
        }
        guard hour < 24, year <= 9999 else { return "" }
        let sign = offset < 0 ? "-" : "+", absolute = abs(offset)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d%@%02d:%02d",year,month,day,hour,minute,second,millis,sign,absolute / 60,absolute % 60)
    }
}
