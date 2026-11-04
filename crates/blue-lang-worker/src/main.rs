fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let judge = blue_lang_worker::child::Judge {
        entry: "world",
        program: "def judged(entries)\n  entries\nend\n",
    };
    let code = blue_lang_worker::child::dispatch(&args, judge).unwrap_or(2);
    std::process::exit(code);
}
