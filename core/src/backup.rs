use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;

use zip::write::SimpleFileOptions;
use zip::{ZipArchive, ZipWriter};

use crate::db::Database;
use crate::error::CoreResult;
use crate::models::{SyncReport, SyncSnapshot};

pub fn export_backup_zip<P: AsRef<Path>>(db: &Database, dest_zip: P) -> CoreResult<()> {
    let snapshot = db.export_snapshot(None)?;
    let snapshot_json = serde_json::to_vec_pretty(&snapshot)?;

    let file = File::create(dest_zip)?;
    let mut zip = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    zip.start_file("snapshot.json", options)?;
    zip.write_all(&snapshot_json)?;

    let media_dir = db.media_dir();
    if media_dir.exists() {
        for entry in std::fs::read_dir(&media_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    let archive_path = format!("media/{}", name);
                    zip.start_file(archive_path, options)?;
                    let bytes = std::fs::read(&path)?;
                    zip.write_all(&bytes)?;
                }
            }
        }
    }

    zip.finish()?;
    Ok(())
}

pub fn import_backup_zip<P: AsRef<Path>>(db: &Database, src_zip: P) -> CoreResult<SyncReport> {
    let file = File::open(src_zip)?;
    let mut archive = ZipArchive::new(file)?;

    let mut snapshot_bytes = Vec::new();
    {
        let mut snapshot_file = archive.by_name("snapshot.json")?;
        snapshot_file.read_to_end(&mut snapshot_bytes)?;
    }

    let snapshot: SyncSnapshot = serde_json::from_slice(&snapshot_bytes)?;
    let mut report = db.merge_snapshot(&snapshot)?;

    let media_dir = db.media_dir();
    std::fs::create_dir_all(&media_dir)?;

    let mut media_count = 0usize;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let name = entry.name().to_string();
        if let Some(rel) = name.strip_prefix("media/") {
            if !rel.is_empty() && !rel.contains("..") && !rel.contains('/') && !rel.contains('\\') {
                let target = media_dir.join(rel);
                if !target.exists() {
                    let mut buf = Vec::new();
                    entry.read_to_end(&mut buf)?;
                    std::fs::write(target, buf)?;
                    media_count += 1;
                }
            }
        }
    }
    report.media_downloaded = media_count;

    Ok(report)
}
