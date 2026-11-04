{ stdenv, fetchFromGitHub, pkg-config, elfutils, zlib, zstd }:

stdenv.mkDerivation {
  pname = "veristat";
  version = "0.5.1";
  src = fetchFromGitHub {
    owner = "libbpf";
    repo = "veristat";
    rev = "v0.5.1";
    fetchSubmodules = true;
    hash = "sha256-kYAr40GFAd2fn9zyUayHbfImQHLfjp6SO9rZGDA+rAU=";
  };
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ elfutils zlib zstd ];
  hardeningDisable = [ "all" ];
  makeFlags = [ "-C" "src" ];
  installPhase = "mkdir -p $out/bin; cp src/veristat $out/bin/";
}
