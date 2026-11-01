use blue_lang_senses::audio::{self, Clip, Format};
use blue_lang_senses::canvas::Canvas;
use blue_lang_senses::display::{self, Screen};
use blue_lang_senses::Refusal;

#[test]
fn a_host_with_no_audio_system_and_no_canvas_server_answers_named_refusals() {
    let dir = std::env::temp_dir().join(format!("blue-senses-absent-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::env::set_var(audio::LIBRARY_VARIABLE, dir.join("libasound.so.2"));
    std::env::set_var(display::SOCKET_VARIABLE, dir.join("canvas.sock"));

    let format = Format::new(8000, 1).unwrap();
    let clip = Clip::new(format, vec![0.0, 0.5]).unwrap();
    for refusal in [
        audio::play(&clip).expect_err("no audio system"),
        audio::capture(format, 4).expect_err("no audio system"),
        audio::device_format(false).expect_err("no audio system"),
        audio::device_format(true).expect_err("no audio system"),
    ] {
        assert!(matches!(refusal, Refusal::Unsupported(_)), "{refusal}");
        assert_eq!(refusal.kind(), "unsupported");
        assert!(refusal.message().contains("does not load"), "{refusal}");
    }
    let empty = Clip::new(format, vec![]).unwrap();
    assert_eq!(
        audio::play(&empty)
            .expect_err("an empty clip still needs a device")
            .kind(),
        "unsupported"
    );

    let canvas = Canvas::new(4, 4).unwrap();
    let refusal = Screen::open(&canvas, "absent")
        .err()
        .expect("no canvas server");
    assert!(matches!(refusal, Refusal::NotFound(_)), "{refusal}");
    assert_eq!(refusal.kind(), "not_found");
    assert!(
        refusal
            .message()
            .contains(&dir.join("canvas.sock").display().to_string()),
        "{refusal}"
    );
}
