import Foundation

public enum ZoneSchedule {
    private static let milan: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    /// Area B e Area C sono attive nei feriali (lun-ven) dalle 7:30 alle 19:30, ora di Milano.
    /// I giorni festivi non sono ancora gestiti.
    public static func isAreaActive(at date: Date) -> Bool {
        let components = milan.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, (2...6).contains(weekday),
              let hour = components.hour, let minute = components.minute else { return false }
        let minutes = hour * 60 + minute
        return minutes >= 7 * 60 + 30 && minutes < 19 * 60 + 30
    }
}
