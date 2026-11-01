use crate::Refusal;

pub const MAX_RATE: i64 = 384_000;
pub const MAX_CHANNELS: i64 = 32;
pub const MAX_FRAMES: i64 = 1 << 24;
pub const LIBRARY_VARIABLE: &str = "BLUE_AUDIO_LIBRARY";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Format {
    pub rate: u32,
    pub channels: u16,
}

impl Format {
    pub fn new(rate: i64, channels: i64) -> Result<Format, String> {
        if !(1..=MAX_RATE).contains(&rate) {
            return Err(format!(
                "a sample rate is 1 to {MAX_RATE} frames a second, got {rate}"
            ));
        }
        if !(1..=MAX_CHANNELS).contains(&channels) {
            return Err(format!(
                "a frame holds 1 to {MAX_CHANNELS} channels, got {channels}"
            ));
        }
        Ok(Format {
            rate: u32::try_from(rate).map_err(|e| e.to_string())?,
            channels: u16::try_from(channels).map_err(|e| e.to_string())?,
        })
    }

    #[must_use]
    pub fn seconds(self, frames: usize) -> f64 {
        frames as f64 / f64::from(self.rate)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Clip {
    pub format: Format,
    pub samples: Vec<f64>,
}

impl Clip {
    pub fn new(format: Format, samples: Vec<f64>) -> Result<Clip, String> {
        let channels = usize::from(format.channels);
        if !samples.len().is_multiple_of(channels) {
            return Err(format!(
                "{} samples are not whole frames of {channels} channels",
                samples.len()
            ));
        }
        if let Some((i, s)) = samples
            .iter()
            .enumerate()
            .find(|(_, s)| !s.is_finite() || s.abs() > 1.0)
        {
            return Err(format!("sample {i} is {s}, outside -1.0 to 1.0"));
        }
        Ok(Clip { format, samples })
    }

    #[must_use]
    pub fn frames(&self) -> usize {
        self.samples.len() / usize::from(self.format.channels)
    }
}

pub fn frames(n: i64) -> Result<usize, String> {
    if !(0..=MAX_FRAMES).contains(&n) {
        return Err(format!("a capture is 0 to {MAX_FRAMES} frames, got {n}"));
    }
    usize::try_from(n).map_err(|e| e.to_string())
}

#[must_use]
pub fn library() -> String {
    std::env::var(LIBRARY_VARIABLE).unwrap_or_else(|_| default_library().to_string())
}

#[must_use]
pub fn default_library() -> &'static str {
    if cfg!(target_vendor = "apple") {
        "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox"
    } else {
        "libasound.so.2"
    }
}

#[cfg(unix)]
pub fn play(clip: &Clip) -> Result<(), Refusal> {
    crate::seam::play(&library(), clip)
}

#[cfg(unix)]
pub fn capture(format: Format, frames: usize) -> Result<Clip, Refusal> {
    crate::seam::capture(&library(), format, frames)
}

#[cfg(unix)]
pub fn device_format(input: bool) -> Result<Option<Format>, Refusal> {
    crate::seam::device_format(&library(), input)
}

#[cfg(not(unix))]
fn absent() -> Refusal {
    Refusal::Unsupported("this platform has no audio system blue can load".into())
}

#[cfg(not(unix))]
pub fn play(_: &Clip) -> Result<(), Refusal> {
    Err(absent())
}

#[cfg(not(unix))]
pub fn capture(_: Format, _: usize) -> Result<Clip, Refusal> {
    Err(absent())
}

#[cfg(not(unix))]
pub fn device_format(_: bool) -> Result<Option<Format>, Refusal> {
    Err(absent())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_format_is_a_positive_rate_and_a_bounded_channel_count() {
        assert_eq!(
            Format::new(48_000, 2),
            Ok(Format {
                rate: 48_000,
                channels: 2
            })
        );
        for (rate, channels) in [(0, 1), (-1, 1), (MAX_RATE + 1, 1), (8000, 0), (8000, 33)] {
            assert!(Format::new(rate, channels).is_err(), "{rate} {channels}");
        }
    }

    #[test]
    fn a_clip_is_whole_frames_of_finite_samples_within_one() {
        let stereo = Format::new(8000, 2).unwrap();
        assert_eq!(
            Clip::new(stereo, vec![0.0, 1.0, -1.0, 0.5])
                .unwrap()
                .frames(),
            2
        );
        assert!(Clip::new(stereo, vec![0.0]).is_err());
        assert!(Clip::new(stereo, vec![0.0, 1.5]).is_err());
        assert!(Clip::new(stereo, vec![0.0, f64::NAN]).is_err());
        assert_eq!(Clip::new(stereo, vec![]).unwrap().frames(), 0);
    }

    #[test]
    fn a_capture_length_is_bounded() {
        assert_eq!(frames(0), Ok(0));
        assert!(frames(-1).is_err());
        assert!(frames(MAX_FRAMES + 1).is_err());
    }
}
