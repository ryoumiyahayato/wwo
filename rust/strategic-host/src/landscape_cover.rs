use std::{
    collections::HashMap,
    fs::File,
    io::{self, Read, Seek, SeekFrom},
    path::Path,
    sync::Arc,
};

use crate::terrain::Key;

const WIDTH: u32 = 256;
const HEIGHT: u32 = 128;
const PARENT_COUNT: u32 = WIDTH * HEIGHT / 4;

pub const REGIONAL_BANKS: u32 = 3;
pub const REGIONAL_SLOTS: u32 = 80;
// Twelve display channels and the source water share. Rendered water remains
// authoritative in the existing QPK / vector layers.
const REGIONAL_CHANNELS: usize = 13;

pub struct RegionalCover {
    file: File,
    frames: Arc<HashMap<Key, RegionalFrame>>,
    decoder: zstd::bulk::Decompressor<'static>,
}

pub struct RegionalFrame {
    offset: u64,
    length: usize,
    pub near_only: bool,
}

impl RegionalCover {
    pub const FILE_NAME: &'static str = "regional-land-cover.qsc";

    pub fn open(path: &Path, page: u32) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let file_len = file.metadata()?.len();
        let mut header = [0; 16];
        file.read_exact(&mut header)?;
        let pages = u32::from_le_bytes(header[12..16].try_into().unwrap());
        let invalid = || io::Error::other(format!("Invalid regional landscape cover pack: {}", path.display()));
        let mut offset = 16 + u64::from(pages) * 8;
        let tagged = &header[..8] == b"WWOREGC5";
        if (!tagged && &header[..8] != b"WWOREGC4") || header[8..12] != page.to_le_bytes()
            || pages > PARENT_COUNT + WIDTH * HEIGHT || offset > file_len
        {
            return Err(invalid());
        }
        let mut directory = vec![0; pages as usize * 8];
        file.read_exact(&mut directory)?;
        let mut frames = HashMap::with_capacity(pages as usize);
        let max_frame = zstd::zstd_safe::compress_bound(page as usize * page as usize * REGIONAL_CHANNELS);
        for record in directory.chunks_exact(8) {
            let near_only = tagged && record[0] & 0x80 != 0;
            let z = u32::from(if tagged { record[0] & 0x7f } else { record[0] });
            let x = u32::from(record[1]);
            let y = u32::from(u16::from_le_bytes(record[2..4].try_into().unwrap()));
            let len = u32::from_le_bytes(record[4..8].try_into().unwrap()) as usize;
            if !(6..=7).contains(&z) || x >= 2 << z || y >= 1 << z || !(1..=max_frame).contains(&len)
                || frames.insert(Key(z, x, y), RegionalFrame { offset, length: len, near_only }).is_some()
            {
                return Err(invalid());
            }
            offset += len as u64;
        }
        if offset != file_len {
            return Err(invalid());
        }
        Ok(Self { file, frames: Arc::new(frames), decoder: zstd::bulk::Decompressor::new()? })
    }

    pub fn index(&self) -> Arc<HashMap<Key, RegionalFrame>> {
        Arc::clone(&self.frames)
    }

    pub fn read(&mut self, key: Key, width: usize) -> io::Result<Vec<u8>> {
        let &RegionalFrame { offset, length, .. } = self.frames.get(&key).ok_or(io::ErrorKind::NotFound)?;
        self.file.seek(SeekFrom::Start(offset))?;
        let mut frame = vec![0; length];
        self.file.read_exact(&mut frame)?;
        let size = width * width;
        let mut banks = self.decoder.decompress(&frame, size * REGIONAL_CHANNELS)?;
        if banks.len() != size * REGIONAL_CHANNELS {
            let Key(z, x, y) = key;
            return Err(io::Error::other(format!("Invalid regional landscape page: {z}/{x}/{y}")));
        }
        banks.truncate(size * 4 * REGIONAL_BANKS as usize);
        Ok(banks)
    }
}

pub struct CoverPack {
    file: File,
    offsets: Vec<u64>,
    decoder: zstd::bulk::Decompressor<'static>,
    legacy: bool,
}

impl CoverPack {
    pub const FILE_NAMES: [&'static str; 2] = ["landscape-cover-v2.qsc", "landscape-cover-v1.qsc"];

    pub fn open(path: &Path, page: u32) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let mut header = [0; 20];
        file.read_exact(&mut header)?;
        let legacy = &header[..8] == b"WWOZ7LC1";
        let parent_count = if legacy { 0 } else { PARENT_COUNT };
        let mut raw = vec![0; ((WIDTH * HEIGHT + parent_count + 1) * 8) as usize];
        file.read_exact(&mut raw)?;
        let offsets: Vec<_> = raw
            .chunks_exact(8)
            .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        if (!legacy && &header[..8] != b"WWOZ7LC2")
            || header[8..12] != WIDTH.to_le_bytes()
            || header[12..16] != HEIGHT.to_le_bytes()
            || header[16..20] != page.to_le_bytes()
            || offsets[0] != (raw.len() + header.len()) as u64
            || offsets.last() != Some(&file.metadata()?.len())
            || offsets.windows(2).any(|pair| {
                pair[1]
                    .checked_sub(pair[0])
                    .is_none_or(|size| size > u64::from(page * page) + 256)
            })
        {
            return Err(io::Error::other(format!(
                "Invalid landscape cover pack: {}",
                path.display()
            )));
        }
        Ok(Self {
            file,
            offsets,
            decoder: zstd::bulk::Decompressor::new()?,
            legacy,
        })
    }

    pub fn read(&mut self, level: u32, x: u32, y: u32, size: usize) -> io::Result<Vec<u8>> {
        let index = match level {
            6 if !self.legacy => y * (WIDTH / 2) + x,
            7 => y * WIDTH + x + if self.legacy { 0 } else { PARENT_COUNT },
            _ => return Ok(vec![0; size]),
        } as usize;
        let start = self.offsets[index];
        let count = (self.offsets[index + 1] - start) as usize;
        if count == 0 {
            return Ok(vec![0; size]);
        }
        let mut compressed = vec![0; count];
        self.file.seek(SeekFrom::Start(start))?;
        self.file.read_exact(&mut compressed)?;
        let mut cover = self.decoder.decompress(&compressed, size)?;
        let max_class = if self.legacy { 4 } else { 11 };
        if cover.len() != size || cover.iter().any(|&class| class > max_class) {
            return Err(io::Error::other(format!(
                "Invalid landscape cover page: {level}/{x}/{y}"
            )));
        }
        if self.legacy {
            for class in &mut cover {
                *class = [0, 1, 6, 3, 7][usize::from(*class)];
            }
        }
        Ok(cover)
    }
}
