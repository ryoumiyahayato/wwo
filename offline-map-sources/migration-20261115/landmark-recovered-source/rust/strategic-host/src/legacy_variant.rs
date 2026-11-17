use crate::formal_save::invalid;
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::io;

// Godot 4.6 Variant wire tags. The formal snapshot uses value types only.
// https://github.com/godotengine/godot/blob/4.6-stable/core/io/marshalls.cpp
const WIDE: u32 = 1 << 16;
const MAX_DEPTH: usize = 128;

pub(crate) fn decode_snapshot(encoded: &str) -> io::Result<Value> {
    let bytes = STANDARD.decode(encoded).map_err(|_| invalid("invalid legacy snapshot base64"))?;
    let mut reader = Reader { remaining: &bytes };
    let snapshot = reader.value(0)?;
    if !reader.remaining.is_empty() {
        return Err(invalid("trailing bytes in legacy snapshot"));
    }
    Ok(snapshot)
}

pub(crate) fn encode_number(value: f64) -> Value {
    let mut bytes = Vec::with_capacity(12);
    bytes.extend((3 | WIDE).to_le_bytes());
    bytes.extend(value.to_le_bytes());
    json!(["variant_bytes", 3, STANDARD.encode(bytes)])
}

pub(crate) fn decode_number(payload: &str) -> io::Result<f64> {
    let bytes = STANDARD.decode(payload).map_err(|_| invalid("invalid legacy float payload"))?;
    match bytes.as_slice() {
        [3, 0, 0, 0, a, b, c, d] => Ok(f32::from_le_bytes([*a, *b, *c, *d]).into()),
        [3, 0, 1, 0, a, b, c, d, e, f, g, h] => Ok(f64::from_le_bytes([*a, *b, *c, *d, *e, *f, *g, *h])),
        _ => Err(invalid("invalid legacy float representation")),
    }
}

struct Reader<'a> {
    remaining: &'a [u8],
}

impl<'a> Reader<'a> {
    fn value(&mut self, depth: usize) -> io::Result<Value> {
        if depth >= MAX_DEPTH {
            return Err(invalid("legacy snapshot nesting limit exceeded"));
        }
        let start = self.remaining;
        let header = self.u32()?;
        let kind = header & 0xff;
        let flags = header & !0xff;
        match (kind, flags) {
            (0, 0) => return Ok(Value::Null),
            (1, 0) => return Ok(Value::Bool(self.u32()? != 0)),
            (2, 0) => return Ok(json!(["int", (self.u32()? as i32).to_string()])),
            (2, WIDE) => {
                let value = i64::from_le_bytes(self.take(8)?.try_into().unwrap());
                return Ok(json!(["int", value.to_string()]));
            }
            (4, 0) => return Ok(Value::String(self.string()?.to_owned())),
            (27, flags) if flags & !(0b1111 << 16) == 0 => {
                self.container_type((flags >> 16) & 3)?;
                self.container_type((flags >> 18) & 3)?;
                let count = self.count(8)?;
                let mut pairs = Vec::with_capacity(count);
                for _ in 0..count {
                    let key = self.value(depth + 1)?;
                    let value = self.value(depth + 1)?;
                    pairs.push(Value::Array(vec![key, value]));
                }
                return Ok(Value::Array(vec![Value::String("map".into()), Value::Array(pairs)]));
            }
            (28, flags) if flags & !(0b11 << 16) == 0 => {
                self.container_type(flags >> 16)?;
                let count = self.count(4)?;
                let mut entries = Vec::with_capacity(count);
                for _ in 0..count {
                    entries.push(self.value(depth + 1)?);
                }
                return Ok(Value::Array(vec![Value::String("array".into()), Value::Array(entries)]));
            }
            (3, 0) => { self.take(4)?; }
            (3, WIDE) => { self.take(8)?; }
            // Packed math values remain opaque to the typed transfer.
            (35 | 36, 0 | WIDE) => {
                let components = if kind == 35 { 2 } else { 3 };
                let width = components * if flags == WIDE { 8 } else { 4 };
                let count = self.count(width)?;
                self.take(count * width)?;
            }
            _ => return Err(invalid(format!("unsupported legacy snapshot Variant {kind} flags {flags}"))),
        }
        let raw = &start[..start.len() - self.remaining.len()];
        Ok(json!(["variant_bytes", kind, STANDARD.encode(raw)]))
    }

    fn container_type(&mut self, kind: u32) -> io::Result<()> {
        match kind {
            0 => Ok(()),
            1 if self.u32()? < 39 => Ok(()),
            _ => Err(invalid("unsupported typed legacy container")),
        }
    }

    fn count(&mut self, width: usize) -> io::Result<usize> {
        // Godot uses the top bit for a shared-array/map marker.
        let count = (self.u32()? & 0x7fff_ffff) as usize;
        if count > self.remaining.len() / width {
            return Err(invalid("invalid legacy collection size"));
        }
        Ok(count)
    }

    fn string(&mut self) -> io::Result<&'a str> {
        let length = self.u32()? as usize;
        let padding = (4 - length % 4) % 4;
        let bytes = self.take(length)?;
        self.take(padding)?;
        std::str::from_utf8(bytes).map_err(|_| invalid("invalid legacy snapshot UTF-8"))
    }

    fn u32(&mut self) -> io::Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }

    fn take(&mut self, length: usize) -> io::Result<&'a [u8]> {
        let (head, rest) = self.remaining.split_at_checked(length)
            .ok_or_else(|| invalid("truncated legacy snapshot"))?;
        self.remaining = rest;
        Ok(head)
    }
}
