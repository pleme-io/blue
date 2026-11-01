use crate::font;

pub const MAX_SIDE: i64 = 4096;
pub const BLACK: u32 = 0x00_0000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Canvas {
    width: usize,
    height: usize,
    back: Vec<u32>,
    front: Vec<u32>,
    presented: u64,
}

impl Canvas {
    pub fn new(width: i64, height: i64) -> Result<Canvas, String> {
        for (what, n) in [("width", width), ("height", height)] {
            if !(1..=MAX_SIDE).contains(&n) {
                return Err(format!(
                    "a canvas {what} is 1 to {MAX_SIDE} pixels, got {n}"
                ));
            }
        }
        let width = usize::try_from(width).map_err(|e| e.to_string())?;
        let height = usize::try_from(height).map_err(|e| e.to_string())?;
        Ok(Canvas {
            width,
            height,
            back: vec![BLACK; width * height],
            front: vec![BLACK; width * height],
            presented: 0,
        })
    }

    #[must_use]
    pub fn width(&self) -> usize {
        self.width
    }

    #[must_use]
    pub fn height(&self) -> usize {
        self.height
    }

    #[must_use]
    pub fn presented(&self) -> u64 {
        self.presented
    }

    pub fn clear(&mut self, rgb: u32) {
        self.back.fill(rgb);
    }

    fn span(at: i64, len: i64, side: usize) -> std::ops::Range<usize> {
        let side = i64::try_from(side).unwrap_or(i64::MAX);
        let from = at.clamp(0, side);
        let to = at.saturating_add(len.max(0)).clamp(0, side);
        usize::try_from(from).unwrap_or(0)..usize::try_from(to).unwrap_or(0)
    }

    pub fn fill_rect(&mut self, x: i64, y: i64, w: i64, h: i64, rgb: u32) {
        let xs = Self::span(x, w, self.width);
        for row in Self::span(y, h, self.height) {
            let line = row * self.width;
            self.back[line + xs.start..line + xs.end].fill(rgb);
        }
    }

    pub fn text(&mut self, x: i64, y: i64, text: &str, rgb: u32) {
        for (i, c) in text.chars().enumerate() {
            let left = x.saturating_add(
                i64::try_from(i)
                    .unwrap_or(i64::MAX)
                    .saturating_mul(font::WIDTH),
            );
            for (dy, bits) in (0i64..).zip(font::glyph(c)) {
                for dx in 0..font::WIDTH {
                    if bits & (1 << dx) != 0 {
                        self.fill_rect(left.saturating_add(dx), y.saturating_add(dy), 1, 1, rgb);
                    }
                }
            }
        }
    }

    pub fn present(&mut self) {
        self.front.clone_from(&self.back);
        self.presented += 1;
    }

    #[must_use]
    pub fn pixel(&self, x: i64, y: i64) -> Option<u32> {
        let x = usize::try_from(x).ok().filter(|x| *x < self.width)?;
        let y = usize::try_from(y).ok().filter(|y| *y < self.height)?;
        Some(self.front[y * self.width + x])
    }

    #[must_use]
    pub fn front_rgb8(&self) -> Vec<u8> {
        self.front
            .iter()
            .flat_map(|p| {
                let [_, r, g, b] = p.to_be_bytes();
                [r, g, b]
            })
            .collect()
    }
}

pub fn color(text: &str) -> Result<u32, String> {
    let bad = || format!("a color is \"#rgb\" or \"#rrggbb\", got {text:?}");
    let hex = text.strip_prefix('#').ok_or_else(bad)?;
    if !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(bad());
    }
    let full = match hex.len() {
        3 => hex.chars().flat_map(|c| [c, c]).collect::<String>(),
        6 => hex.to_string(),
        _ => return Err(bad()),
    };
    u32::from_str_radix(&full, 16).map_err(|_| bad())
}

#[must_use]
pub fn hex(rgb: u32) -> String {
    format!("#{:06x}", rgb & 0xFF_FFFF)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_canvas_side_is_bounded_and_starts_black_with_nothing_presented() {
        let c = Canvas::new(4, 3).unwrap();
        assert_eq!((c.width(), c.height(), c.presented()), (4, 3, 0));
        assert_eq!(c.pixel(3, 2), Some(BLACK));
        for (w, h) in [(0, 1), (1, 0), (-2, 4), (MAX_SIDE + 1, 1)] {
            assert!(Canvas::new(w, h).is_err(), "{w}x{h}");
        }
    }

    #[test]
    fn drawing_reaches_the_front_only_when_presented() {
        let mut c = Canvas::new(4, 4).unwrap();
        c.clear(0x11_2233);
        c.fill_rect(1, 1, 2, 2, 0xFF_0000);
        assert_eq!(c.pixel(1, 1), Some(BLACK));
        c.present();
        assert_eq!(c.presented(), 1);
        assert_eq!(c.pixel(0, 0), Some(0x11_2233));
        assert_eq!(c.pixel(1, 1), Some(0xFF_0000));
        assert_eq!(c.pixel(2, 2), Some(0xFF_0000));
        assert_eq!(c.pixel(3, 3), Some(0x11_2233));
        assert_eq!(c.pixel(4, 0), None);
        assert_eq!(c.pixel(-1, 0), None);
    }

    #[test]
    fn a_rectangle_past_the_edge_is_clipped_and_one_with_no_area_draws_nothing() {
        let mut c = Canvas::new(3, 3).unwrap();
        c.fill_rect(-5, 2, 100, 100, 0x00_FF00);
        c.fill_rect(0, 0, 0, 3, 0x00_00FF);
        c.fill_rect(0, 0, -2, 3, 0x00_00FF);
        c.fill_rect(i64::MAX, i64::MAX, i64::MAX, i64::MAX, 0x00_00FF);
        c.present();
        assert_eq!(c.pixel(0, 2), Some(0x00_FF00));
        assert_eq!(c.pixel(2, 2), Some(0x00_FF00));
        assert_eq!(c.pixel(0, 0), Some(BLACK));
    }

    #[test]
    fn text_sets_the_glyph_bits_within_eight_by_eight_cells() {
        let mut c = Canvas::new(16, 8).unwrap();
        c.text(0, 0, "A ", 0xFF_FFFF);
        c.present();
        let lit = |x0: i64, x1: i64| {
            (x0..x1)
                .flat_map(|x| (0..8).map(move |y| (x, y)))
                .filter(|(x, y)| c.pixel(*x, *y) == Some(0xFF_FFFF))
                .count()
        };
        let a: u32 = font::glyph('A').iter().map(|b| b.count_ones()).sum();
        assert_eq!(lit(0, 8), a as usize);
        assert_eq!(lit(8, 16), 0, "a space lights nothing");
        assert_eq!(c.pixel(2, 0), Some(0xFF_FFFF), "the top of the A");
        assert_eq!(
            c.pixel(0, 7),
            Some(BLACK),
            "the last row of a glyph is blank"
        );
    }

    #[test]
    fn colors_are_three_or_six_hex_digits_and_read_back_as_six() {
        assert_eq!(color("#ff8800"), Ok(0xFF_8800));
        assert_eq!(color("#F80"), Ok(0xFF_8800));
        assert_eq!(hex(0xFF_8800), "#ff8800");
        assert_eq!(hex(color("#0a0b0c").unwrap()), "#0a0b0c");
        for bad in ["ff8800", "#ff88", "#gg0000", "#ff880000", "", "#"] {
            assert!(color(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_front_is_sent_as_rgb_bytes_row_by_row() {
        let mut c = Canvas::new(2, 1).unwrap();
        c.fill_rect(1, 0, 1, 1, 0x01_0203);
        c.present();
        assert_eq!(c.front_rgb8(), vec![0, 0, 0, 1, 2, 3]);
    }
}
