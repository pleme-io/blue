macro_rules! moduledoc {
    ($purpose:literal, $example:literal) => {
        concat!(
            "@moduledoc \"\"\"\n",
            $purpose,
            "\n\n    ",
            $example,
            "\n\"\"\"\n\n"
        )
    };
    ($purpose:literal, $example:literal, $body:literal) => {
        concat!(
            "@moduledoc \"\"\"\n",
            $purpose,
            "\n\n    ",
            $example,
            "\n\"\"\"\n\n",
            $body
        )
    };
}
