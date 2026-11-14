pub(crate) fn year_start_day(year: i64) -> i64 {
    let previous = year - 1;
    previous * 365 + previous / 4 - previous / 100 + previous / 400
}

pub fn month_length(year: i32, month: u32) -> u32 {
    match month {
        2 => 28 + u32::from(year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)),
        4 | 6 | 9 | 11 => 30,
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        _ => 0,
    }
}
