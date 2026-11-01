#![cfg(target_os = "linux")]

use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

use blue_lang_senses::audio::{self, Clip, Format};
use blue_lang_senses::Refusal;

const REQUIRE: &str = "BLUE_REQUIRE_ALSA";
const FRAMES: usize = 4000;

static DEVICE: Mutex<()> = Mutex::new(());

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-alsa-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("a scratch directory");
    dir
}

fn configured(dir: &Path, pcm: &str) -> Option<MutexGuard<'static, ()>> {
    let guard = DEVICE.lock().unwrap_or_else(PoisonError::into_inner);
    let conf = dir.join("asound.conf");
    std::fs::write(&conf, format!("pcm.!default {pcm}\n")).expect("an ALSA configuration");
    std::env::set_var("ALSA_CONFIG_PATH", &conf);
    match audio::device_format(false) {
        Err(Refusal::Unsupported(why)) if why.contains("does not load") => {
            assert!(
                std::env::var_os(REQUIRE).is_none(),
                "{REQUIRE} is set and libasound does not load: {why}"
            );
            eprintln!(
                "SKIPPED: {why} (set {} to a libasound.so.2)",
                audio::LIBRARY_VARIABLE
            );
            None
        }
        _ => Some(guard),
    }
}

fn file_pcm(written: &Path, read: Option<&Path>) -> String {
    let infile = read
        .map(|p| format!(" infile \"{}\"", p.display()))
        .unwrap_or_default();
    format!(
        "{{ type file slave.pcm {{ type null }} file \"{}\"{infile} format \"raw\" }}",
        written.display()
    )
}

fn pattern(samples: usize) -> Vec<f32> {
    (0..samples)
        .map(|i| (((i * 37) % 509) as f32 - 254.0) / 256.0)
        .collect()
}

fn bytes(samples: &[f32]) -> Vec<u8> {
    samples.iter().flat_map(|s| s.to_ne_bytes()).collect()
}

fn samples_in(path: &Path) -> Vec<f32> {
    let raw = std::fs::read(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    assert_eq!(
        raw.len() % 4,
        0,
        "{} bytes are not whole samples",
        raw.len()
    );
    raw.chunks_exact(4)
        .map(|b| f32::from_ne_bytes([b[0], b[1], b[2], b[3]]))
        .collect()
}

fn agree(want: &[f32], got: &[f32]) -> Result<(), String> {
    if want.len() != got.len() {
        return Err(format!("{} samples, not {}", got.len(), want.len()));
    }
    match want.iter().zip(got).position(|(w, g)| w != g) {
        Some(i) => Err(format!("sample {i} as {}, not {}", got[i], want[i])),
        None => Ok(()),
    }
}

#[test]
fn libasound_plays_a_stereo_clip_longer_than_its_buffer_into_a_file_device_sample_for_sample() {
    let dir = scratch("play");
    let played = dir.join("played.raw");
    let Some(_device) = configured(&dir, &file_pcm(&played, None)) else {
        return;
    };
    assert_eq!(
        audio::device_format(false),
        Ok(Some(Format {
            rate: 48_000,
            channels: 2
        }))
    );
    let format = Format::new(8000, 2).unwrap();
    let want = pattern(FRAMES * 2);
    let clip = Clip::new(format, want.iter().map(|s| f64::from(*s)).collect()).unwrap();
    audio::play(&clip).expect("libasound plays the clip");
    if let Err(e) = agree(&want, &samples_in(&played)) {
        panic!("the file device holds {e}");
    }
}

#[test]
fn libasound_captures_a_stereo_clip_longer_than_its_buffer_from_a_file_device_sample_for_sample() {
    let dir = scratch("capture");
    let spoken = dir.join("spoken.raw");
    let want = pattern(FRAMES * 2);
    std::fs::write(&spoken, bytes(&want)).expect("the device's input file");
    let Some(_device) = configured(&dir, &file_pcm(&dir.join("heard.raw"), Some(&spoken))) else {
        return;
    };
    assert_eq!(
        audio::device_format(true),
        Ok(Some(Format {
            rate: 48_000,
            channels: 2
        }))
    );
    let format = Format::new(8000, 2).unwrap();
    let clip = audio::capture(format, FRAMES).expect("libasound captures the clip");
    assert_eq!(clip.format, format);
    let got: Vec<f32> = clip.samples.iter().map(|s| *s as f32).collect();
    if let Err(e) = agree(&want, &got) {
        panic!("the capture holds {e}");
    }
}

#[test]
fn libasound_answers_a_card_that_is_not_there_with_a_named_refusal() {
    let dir = scratch("absent");
    let Some(_device) = configured(&dir, "{ type hw card 31 }") else {
        return;
    };
    assert_eq!(audio::device_format(false), Ok(None));
    assert_eq!(audio::device_format(true), Ok(None));
    let format = Format::new(8000, 1).unwrap();
    let clip = Clip::new(format, vec![0.0; 80]).unwrap();
    for refusal in [
        audio::play(&clip).expect_err("there is no card 31"),
        audio::capture(format, 80).expect_err("there is no card 31"),
    ] {
        assert!(matches!(refusal, Refusal::NotFound(_)), "{refusal}");
        assert!(refusal.message().starts_with("snd_pcm_open: "), "{refusal}");
    }
}
