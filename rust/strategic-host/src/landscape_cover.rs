use std::{
    fs::File,
    io::{self, Read, Seek, SeekFrom},
    path::Path,
};

const WIDTH: u32 = 256;
const HEIGHT: u32 = 128;

pub struct CoverPack {
    file: File,
    offsets: Vec<u64>,
    decoder: zstd::bulk::Decompressor<'static>,
}

impl CoverPack {
    pub const FILE_NAME: &'static str = "landscape-cover-v1.qsc";

    pub fn open(path: &Path, page: u32) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let mut header = [0; 20];
        file.read_exact(&mut header)?;
        let mut raw = vec![0; (WIDTH as usize * HEIGHT as usize + 1) * 8];
        file.read_exact(&mut raw)?;
        let offsets: Vec<_> = raw
            .chunks_exact(8)
            .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        if &header[..8] != b"WWOZ7LC1"
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
                "Invalid Z7 landscape cover pack: {}",
                path.display()
            )));
        }
        Ok(Self {
            file,
            offsets,
            decoder: zstd::bulk::Decompressor::new()?,
        })
    }

    pub fn read(&mut self, x: u32, y: u32, size: usize) -> io::Result<Vec<u8>> {
        let index = (y * WIDTH + x) as usize;
        let start = self.offsets[index];
        let count = (self.offsets[index + 1] - start) as usize;
        if count == 0 {
            return Ok(vec![0; size]);
        }
        let mut compressed = vec![0; count];
        self.file.seek(SeekFrom::Start(start))?;
        self.file.read_exact(&mut compressed)?;
        let cover = self.decoder.decompress(&compressed, size)?;
        if cover.len() != size || cover.iter().any(|&class| class > 4) {
            return Err(io::Error::other(format!(
                "Invalid Z7 landscape cover page: {x}/{y}"
            )));
        }
        Ok(cover)
    }
}
