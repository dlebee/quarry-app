# Quarry Builders

A little game for a preschooler: pick a machine (excavator, dump truck, loader, tractor, giant haul truck,
cement mixer) and move dirt in an open-pit quarry. The big button does each machine's job: dig and swing,
scoop, push, tip the bed. Full trucks drive themselves up the winding haul road to the rock crusher, and
the machines you aren't driving help out. Tap the ground to drive there; drag to look around.

- The quarry (terraced benches, haul road) is generated in Blender: `scripts/make_quarry_terrain.py`;
  piles and props are placed by `scripts/make_site_layout.py`.

## Build

Godot 4.7 (GL Compatibility renderer), one project for iPhone/iPad and Android.

```bash
cp scripts/devices.env.example scripts/devices.env   # your iPhone ids, Apple team, tablet serial/IP
scripts/build.sh iphone   # iOS export -> xcodebuild -> install on the iPhone
scripts/build.sh fire     # Android export -> adb install on the tablet (Wireless debugging on)
scripts/build.sh sim      # iOS simulator (Godot's simulator library is x86_64: runs under Rosetta)
```

Android export needs Java: `JAVA_HOME` defaults to Android Studio's bundled JDK. Desktop test with
screenshots: `cd godot && godot --resolution 1280x800 -- --autoplay=/tmp/shots`.

## Assets

Everything bundled is CC0, see `assets-src/CREDITS.md` for each source. The raw downloads in
`assets-src/` are not committed (they are large); the game only needs `godot/assets/`.
Code: MIT (`LICENSE`).
