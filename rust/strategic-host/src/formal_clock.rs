use crate::calendar::month_length;
use serde::{Deserialize, Serialize};
use std::io;

pub const MINUTES_PER_HOUR: i64 = 60;
pub const MINUTES_PER_DAY: i64 = 24 * MINUTES_PER_HOUR;
pub(crate) const FIXED_STEP_MILLIS: u64 = 50;
const MILLIS_PER_MINUTE: u64 = 60_000;
const STEPS_PER_MINUTE: u64 = MILLIS_PER_MINUTE / FIXED_STEP_MILLIS;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct GameClock {
    minutes: i64,
    subminute_millis: u16,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ClockSnapshot {
    pub total_minutes: i64,
    pub minute_remainder: i64,
    #[serde(default)]
    pub subminute_millis: u16,
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
        let millis = u64::from(snapshot.subminute_millis);
        if snapshot.total_minutes < 0 || snapshot.minute_remainder != snapshot.total_minutes % MINUTES_PER_HOUR
            || millis >= MILLIS_PER_MINUTE || millis % FIXED_STEP_MILLIS != 0
        {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "inconsistent formal clock snapshot"));
        }
        Ok(Self { minutes: snapshot.total_minutes, subminute_millis: snapshot.subminute_millis })
    }

    pub fn snapshot(self) -> ClockSnapshot {
        ClockSnapshot {
            total_minutes: self.minutes, minute_remainder: self.minutes % MINUTES_PER_HOUR,
            subminute_millis: self.subminute_millis,
        }
    }

    pub fn current_hour(self) -> i64 { self.minutes / MINUTES_PER_HOUR }

    pub fn current_day(self) -> i64 { self.minutes / MINUTES_PER_DAY }

    pub(crate) fn minute_boundary(self) -> Self {
        Self { subminute_millis: 0, ..self }
    }

    pub(crate) fn fixed_steps_since(self, earlier: Self) -> i128 {
        (i128::from(self.minutes) - i128::from(earlier.minutes)) * i128::from(STEPS_PER_MINUTE)
            + (i128::from(self.subminute_millis) - i128::from(earlier.subminute_millis))
                / i128::from(FIXED_STEP_MILLIS)
    }

    pub(crate) fn after_fixed_steps(mut self, steps: u64) -> io::Result<Self> {
        let partial = steps % STEPS_PER_MINUTE + u64::from(self.subminute_millis) / FIXED_STEP_MILLIS;
        self.advance_minutes((steps / STEPS_PER_MINUTE + partial / STEPS_PER_MINUTE) as i64)?;
        self.subminute_millis = (partial % STEPS_PER_MINUTE * FIXED_STEP_MILLIS) as u16;
        Ok(self)
    }

    pub fn advance_minutes(&mut self, minutes: i64) -> io::Result<()> {
        self.minutes = self.minutes.checked_add(minutes).filter(|_| minutes >= 0).ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, format!("invalid advance {minutes} at minute {}", self.minutes))
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
            hour: self.current_hour() % 24, minute: self.minutes % MINUTES_PER_HOUR,
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
