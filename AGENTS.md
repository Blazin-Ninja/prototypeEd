# Chimera Bond

Mobile-first, turn-based monster-evolution RPG built with **Godot 4.3 stable**. See `README.md`
for gameplay overview, architecture, controls, and the standard run/test/export commands.

## Cursor Cloud specific instructions

This is a Godot 4.3 project (no Node/Python package manager). The `godot` binary (`4.3-stable`,
linux x86_64) is provisioned by the environment update script and installed to `/usr/local/bin/godot`.
Generated files under `.godot/` are gitignored, so a fresh checkout must be imported before running
anything — the update script runs `godot --headless --path . --import` for this.

Key gotchas for this headless cloud VM:

- **Rendering driver:** The project's default renderer is `mobile` (Vulkan), and Vulkan is NOT
  available here (`VK_KHR_surface not found`). To open the game GUI you MUST force the OpenGL3
  compatibility renderer with software rasterization:
  `DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=true godot --path . --rendering-driver opengl3`.
  A Mesa `llvmpipe` software GL context is used (no GPU). Headless commands (`--headless`, e.g.
  tests/imports) do not need this.
- **Display:** A virtual X server is available on `DISPLAY=:1` (used for GUI runs and screenshots).
- **Audio:** There is no sound card; Godot falls back to the dummy audio driver. The ALSA errors
  on startup are harmless.
- **Startup dialog:** When run with the OpenGL3 fallback, Godot may pop a "video card driver"
  info dialog over the game window; dismiss it with its "okay" button — the game runs fine.
- **Overworld movement:** The overworld camera follows the player, so pressing WASD/arrows scrolls
  the map while the player sprite stays roughly centered — the world moving IS the player moving.

Commands (run from repo root):

- Headless tests (also what CI runs): `godot --headless --path . res://tests/TestRunner.tscn`
  — prints `ALL TESTS PASSED` and exits 0 on success.
- Run the game (GUI): use the rendering-driver command above.
- Android/Web export requires export templates + Android SDK/JDK (see `README.md`); not set up here.

Note: the `main` branch is a placeholder (README only). The actual game lives on the
`cursor/*` feature branches.
