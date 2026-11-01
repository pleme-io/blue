use blue_lang_senses::audio::{self, Clip, Format};

#[test]
#[ignore = "reaches this host's real audio output; run with --ignored on a machine with a speaker"]
fn the_host_output_device_answers_its_format_and_plays_a_silent_clip_to_the_end() {
    let format = audio::device_format(false)
        .expect("an audio system")
        .expect("an output device");
    assert!(format.rate >= 8000 && format.channels >= 1, "{format:?}");
    let silence = Clip::new(
        Format::new(i64::from(format.rate), 1).unwrap(),
        vec![0.0; format.rate as usize / 10],
    )
    .unwrap();
    let started = std::time::Instant::now();
    audio::play(&silence).expect("plays");
    assert!(
        started.elapsed() >= std::time::Duration::from_millis(80),
        "a tenth of a second of audio returned after {:?}",
        started.elapsed()
    );
}
