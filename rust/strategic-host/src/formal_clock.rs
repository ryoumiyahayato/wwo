use crate::calendar::month_length;
use serde::{Deserialize, Serialize};
use std::io;

pub const MINUTES_PER_HOUR: i64 = 60;
pub const MINUTES_PER_DAY: i64 = 24 * MINUTES_PER_HOUR;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct GameClock(i64);

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ClockSnapshot {
    pub total_minutes: i64,
    pub minute_remainder: i64,
}

#[derive(Clone, Copy, Debug, Serialize)]
pub struct CalendarTime {
    pub year: i64,
    pub month: u32,
    pub day: u32,
    pub hour: i64,
    pub minute: i64,
    pub weekday: i64,
}

impl GameClock {
    pub fn restore(snapshot: ClockSnapshot) -> io::Result<Self> {
        if snapshot.total_minutes < 0 || snapshot.minute_remainder != snapshot.total_minutes % MINUTES_PER_HOUR {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "inconsistent formal clock snapshot"));
        }
        Ok(Self(snapshot.total_minutes))
    }

    pub fn snapshot(self) -> ClockSnapshot {
        ClockSnapshot { total_minutes: self.0, minute_remainder: self.0 % MINUTES_PER_HOUR }
    }

    pub fn current_hour(self) -> i64 { self.0 / MINUTES_PER_HOUR }

    pub fn current_day(self) -> i64 { self.0 / MINUTES_PER_DAY }

    pub fn advance_minutes(&mut self, minutes: i64) -> io::Result<()> {
        self.0 = self.0.checked_add(minutes).filter(|_| minutes >= 0).ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, format!("invalid advance {minutes} at minute {}", self.0))
        })?;
        Ok(())
    }

    pub fn current_date(self) -> CalendarTime {
        const DAYS_PER_CYCLE: i64 = 146_097;
        let days = self.current_day();
        let cycle = days / DAYS_PER_CYCLE;
        let mut remaining = days % DAYS_PER_CYCLE;
        let mut year = 1900;
        loop {
            let days_in_year = 365 + i64::from(month_length(year, 2) - 28);
            if remaining < days_in_year { break; }
            remaining -= days_in_year;
            year += 1;
        }
        let mut month = 1;
        loop {
            let length = i64::from(month_length(year, month));
            if remaining < length { break; }
            remaining -= length;
            month += 1;
        }
        CalendarTime {
            year: i64::from(year) + cycle * 400, month, day: remaining as u32 + 1,
            hour: self.current_hour() % 24, minute: self.0 % MINUTES_PER_HOUR,
            weekday: days % 7, // R68's epoch is Monday, with Monday numbered zero.
        }
    }
}

pub struct TimeControl {
    pub paused: bool,
    pub speed: i64,
}

impl Default for TimeControl {
    fn default() -> Self { Self { paused: true, speed: 1 } }
}

impl TimeControl {
    pub fn toggle_pause(&mut self) { self.paused = !self.paused; }

    pub fn set_speed(&mut self, speed: i64) {
        if matches!(speed, 1 | 2 | 4) {
            self.speed = speed;
            self.paused = false;
        }
    }

    pub fn tick(&self) -> Option<i64> { (!self.paused).then_some(15 * self.speed) }
}
