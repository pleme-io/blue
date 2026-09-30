#![no_std]
#![forbid(unsafe_code)]
use kiban_io::Io;
const BL_UART0: u32 = 268435456u32;
fn bl_put<I: Io>(io: &mut I, p_c: u32) -> u32 {
    {
        io.write8(BL_UART0, p_c);
        p_c
    }
}
fn bl_send<I: Io>(io: &mut I, p_c: u32, p_n: u32) -> u32 {
    let mut p_c = p_c;
    let mut p_n = p_n;
    loop {
        if (p_n == 0u32) {
            return p_c;
        } else {
            bl_put(io, p_c);
            let t_0 = kiban_io::checked(p_c.checked_add(1u32));
            let t_1 = kiban_io::checked(p_n.checked_sub(1u32));
            p_c = t_0;
            p_n = t_1;
            continue;
        };
    };
}
pub fn main<I: Io>(io: &mut I) {
    bl_send(io, 104u32, 2u32);
    bl_put(io, 10u32);
}
