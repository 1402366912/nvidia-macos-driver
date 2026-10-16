# Expanded AsusSMC source overlay

Source WIP, not a complete upstream checkout or a compiled kext.

These seven `AsusSMC/` files are byte-identical to the output of applying
`../patches/AsusSMC-FX505GT.patch` to AsusSMC commit
`c15d2f297c86b65a3cb866cc2bcece595c136417`. Their expected SHA-256 values are
listed in `../upstream-manifest.json` under `sha256_after`.

Original AsusSMC copyright and its unchanged MIT `LICENSE.md` are preserved.
New bridge code is independently authored MIT; see `../LICENSE`.

The full upstream source, Lilu/VirtualSMC dependencies and Apple kernel SDK are
still required to build. No GUI, driver binary, installation, load or hardware
validation is included. Feature configuration remains off by default.
