# Synthetic JPEG fixture

`synthetic_restart_422.jpg` is generated from the original mathematical RGB
pattern in `scripts/jpeg_restart_fixtures.mjs` using the already installed
ImageMagick WASM encoder: 257×193, 4:2:2, baseline, restart interval 17, quality 60.
It contains no user photo or downloaded image. The test adds `0x55` padding before
RST markers only in memory to reproduce the decoder compatibility failure.

Generator (refuses to overwrite an existing fixture):

```powershell
node scripts/jpeg_restart_fixtures.mjs --write-regression-fixture
```
