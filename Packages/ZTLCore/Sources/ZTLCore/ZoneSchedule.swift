import Foundation

public enum ZoneSchedule {
    private static let milan: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    /// Area B e Area C sono attive nei feriali (lun-ven, festivi esclusi) dalle 7:30 alle 19:30, ora di Milano.
    public static func isAreaActive(at date: Date) -> Bool {
        guard !isHoliday(date) else { return false }
        let window = WeeklyWindow(days: [1, 2, 3, 4, 5], from: 7 * 60 + 30, to: 19 * 60 + 30)
        return isWithin([window], at: date)
    }

    public static func isWithin(_ windows: [WeeklyWindow], at date: Date) -> Bool {
        let components = milan.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute else {
            return false
        }
        // Calendar: 1 = domenica; qui 1 = lunedì ... 7 = domenica.
        let day = weekday == 1 ? 7 : weekday - 1
        let previousDay = day == 1 ? 7 : day - 1
        let minutes = hour * 60 + minute

        return windows.contains { window in
            if window.from < window.to {
                return window.days.contains(day) && minutes >= window.from && minutes < window.to
            }
            return (window.days.contains(day) && minutes >= window.from)
                || (window.days.contains(previousDay) && minutes < window.to)
        }
    }

    /// Festività nazionali più Sant'Ambrogio (7 dicembre), patrono di Milano.
    public static func isHoliday(_ date: Date) -> Bool {
        let components = milan.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }
        let fixed = [(1, 1), (1, 6), (4, 25), (5, 1), (6, 2), (8, 15), (11, 1), (12, 7), (12, 8), (12, 25), (12, 26)]
        if fixed.contains(where: { $0 == (month, day) }) {
            return true
        }
        guard let easter = easterSunday(year: year),
              let easterMonday = milan.date(byAdding: .day, value: 1, to: easter) else { return false }
        return milan.isDate(date, inSameDayAs: easterMonday)
    }

    /// Algoritmo gregoriano anonimo (Meeus/Jones/Butcher).
    static func easterSunday(year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return milan.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}
