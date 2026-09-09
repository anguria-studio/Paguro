/// Pure rules for a daily quiet-hours schedule.
public enum QuietHoursPolicy {
    /// Returns whether a minute of the day is inside the scheduled window.
    /// The start is inclusive and the end is exclusive.
    public static func contains(
        nowMinutes: Int,
        start: Int,
        end: Int
    ) -> Bool {
        let minutesInDay = 24 * 60
        guard (0..<minutesInDay).contains(nowMinutes),
              (0..<minutesInDay).contains(start),
              (0..<minutesInDay).contains(end),
              start != end else {
            return false
        }

        if start < end {
            return nowMinutes >= start && nowMinutes < end
        }
        return nowMinutes >= start || nowMinutes < end
    }
}
