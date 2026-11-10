use std::path::{Path, PathBuf};

const CHANNEL_SLACK: u8 = 8;
const PIXEL_TOLERANCE: f64 = 0.01;

#[derive(Debug, Clone, PartialEq, Eq)]
struct Image {
    width: u32,
    height: u32,
    rgba: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
enum Verdict {
    Green(f64),
    Red(f64),
    Blind(String),
}

fn decode(path: &Path) -> Image {
    let file = std::fs::File::open(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    let mut decoder = png::Decoder::new(std::io::BufReader::new(file));
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().expect("a PNG header");
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).expect("a PNG frame");
    let channels = info.color_type.samples();
    let rgba = buf[..info.buffer_size()]
        .chunks(channels)
        .flat_map(|p| match *p {
            [r, g, b, a] => [r, g, b, a],
            [r, g, b] => [r, g, b, 255],
            [l, a] => [l, l, l, a],
            [l] => [l, l, l, 255],
            _ => [0, 0, 0, 0],
        })
        .collect();
    Image {
        width: info.width,
        height: info.height,
        rgba,
    }
}

fn compare(golden: &Image, shot: &Image) -> Verdict {
    if (golden.width, golden.height) != (shot.width, shot.height) {
        return Verdict::Blind(format!(
            "the shot is {}x{} and the golden {}x{}: another simulator model",
            shot.width, shot.height, golden.width, golden.height
        ));
    }
    let first = shot.rgba.get(..4).unwrap_or_default();
    if shot.rgba.chunks(4).all(|p| p == first) {
        return Verdict::Blind("the shot is one flat colour: no frame was drawn".to_owned());
    }
    let pixels = golden.rgba.len() / 4;
    let differing = golden
        .rgba
        .chunks(4)
        .zip(shot.rgba.chunks(4))
        .filter(|(a, b)| {
            a.iter()
                .zip(b.iter())
                .any(|(x, y)| x.abs_diff(*y) > CHANNEL_SLACK)
        })
        .count();
    let fraction = differing as f64 / pixels.max(1) as f64;
    if fraction <= PIXEL_TOLERANCE {
        Verdict::Green(fraction)
    } else {
        Verdict::Red(fraction)
    }
}

fn synthetic(rect: [u8; 3]) -> Image {
    let (width, height) = (40, 80);
    let mut rgba = Vec::new();
    for y in 0..height {
        for x in 0..width {
            let inside = (10..30).contains(&x) && (20..40).contains(&y);
            let [r, g, b] = if inside { rect } else { [26, 51, 102] };
            rgba.extend_from_slice(&[r, g, b, 255]);
        }
    }
    Image {
        width,
        height,
        rgba,
    }
}

#[test]
fn the_diff_is_green_on_a_match_red_on_another_colour_and_blind_on_a_flat_shot() {
    let golden = synthetic([255, 128, 0]);
    assert_eq!(compare(&golden, &golden), Verdict::Green(0.0));
    assert!(matches!(
        compare(&golden, &synthetic([0, 200, 80])),
        Verdict::Red(f) if f > 0.1
    ));
    let black = Image {
        rgba: vec![0; golden.rgba.len()],
        ..golden.clone()
    };
    assert!(matches!(compare(&golden, &black), Verdict::Blind(_)));
    let small = Image {
        width: 1,
        height: 1,
        rgba: vec![0, 0, 0, 255],
    };
    assert!(matches!(compare(&golden, &small), Verdict::Blind(_)));
}

#[test]
#[ignore = "needs a simulator screenshot in BLUE_IOS_SHOT: blue run crates/blue-lang-ios/sim.b -- golden"]
fn the_simulator_frame_matches_the_golden() {
    let shot = std::env::var_os("BLUE_IOS_SHOT").expect("BLUE_IOS_SHOT names the screenshot");
    let golden = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("golden/iphone-17-pro.png");
    match compare(&decode(&golden), &decode(Path::new(&shot))) {
        Verdict::Green(_) => {}
        other => panic!("{other:?} against {}", golden.display()),
    }
}
