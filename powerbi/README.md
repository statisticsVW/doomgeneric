# doomgeneric → Power BI custom visual

**It runs DOOM. Inside a Power BI report.**

This is a doomgeneric platform port whose "screen" is a `<canvas>` inside a
Power BI **custom visual**. The engine is compiled to WebAssembly with
Emscripten, and the `.wasm` **and** the shareware `DOOM1.WAD` are base64-inlined
into one `doom.js`, which webpack bundles into a single ~2.4 MB `.pbiviz`.
Everything runs **locally, offline, inside Power BI's sandboxed visual iframe** —
no server, no hosted game, no network. (Power BI's sandbox actually *blocks*
network access, which is exactly why everything has to be embedded.)

```
doomgeneric (C) + doomgeneric_pbi.c  ──emcc──►  doom.js (wasm + WAD inlined) ──webpack/pbiviz──►  .pbiviz
                                                                  RUN TIME, in Power BI's sandboxed iframe:
                                                                  WASM + JS  →  <canvas>
```

## The port

Two pieces, following the usual doomgeneric layout:

| Piece | Where | What it does |
|---|---|---|
| Platform shim | [`../doomgeneric/doomgeneric_pbi.c`](../doomgeneric/doomgeneric_pbi.c) | Implements `DG_Init` / `DG_DrawFrame` / `DG_SleepMs` / `DG_GetTicksMs` / `DG_GetKey`. `DG_DrawFrame` swizzles `DG_ScreenBuffer` (XRGB) to RGBA and hands it to a JS `Module.dgBlit` callback; `dg_add_key(pressed, doomKey)` is exported so JS can push already-translated DOOM key codes; the main loop is `emscripten_set_main_loop(doomgeneric_Tick)`. No SDL, no sound. |
| Makefile | [`../doomgeneric/Makefile.pbi`](../doomgeneric/Makefile.pbi) | Same shape as the other `Makefile.<platform>` files, but links with `-s SINGLE_FILE=1 -s MODULARIZE=1 -s EXPORT_NAME=createDoom --embed-file doom1.wad`. Output is `doom.js`; `make install` copies it to `powerbi/src/doom.js`. |
| Visual | [`src/visual.ts`](src/visual.ts) | Implements Power BI's `IVisual`: creates the canvas, calls `createDoom(module)` with a `dgBlit` that `putImageData`s each frame, maps `KeyboardEvent.code` → `doomkeys.h` codes, and keeps the canvas fitted to the viewport (16:10). |

The shim intentionally **never blocks**: `DG_SleepMs` is a no-op because
`requestAnimationFrame` paces the loop, and the key queue is the same 16-entry
ring the other ports use.

## Play it

No data fields required — it's a pure interactive visual.

1. Build (below) or grab a prebuilt `DoomInPowerBI.pbiviz`.
2. In **Power BI Desktop** (or a report in the Service): Visualizations pane → **⋯** →
   **Import a visual from a file** → select the `.pbiviz` → accept the "uncertified visual" prompt.
3. Drop the new visual on the canvas and **drag it large**.
4. **Click inside the visual** to give it keyboard focus, and play.

> Greyed-out import option? An admin has disabled *"visuals from the Power BI SDK"*
> for your tenant. Power BI Desktop allows it by default.

### Controls

| Action | Keys |
|---|---|
| Move / turn | `W` `S` + `←` `→` |
| Strafe | `A` `D` |
| Fire | `Ctrl` |
| Use / open doors | `Space` |
| Run | `Shift` |
| Weapons | `1`–`7` |
| Menu / back | `Enter` / `Esc` |

While the canvas has focus, game keys are `preventDefault`ed so arrow keys drive
DOOM instead of scrolling the report.

## Build from source

### 1. Engine → `doom.js`

Prereqs: [Emscripten](https://emscripten.org/) (`emcc` on PATH) and the shareware
`doom1.wad`. The WAD must match the pinned hash — the build refuses to embed
anything else, because this exact file ships inside the visual.

```bash
cd doomgeneric
curl -L -o doom1.wad https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad
echo "1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771  doom1.wad" | sha256sum -c -
make -f Makefile.pbi install      # -> ../powerbi/src/doom.js (~6 MB)
```

Windows (no `make`): the same build as a script.

```powershell
$env:EMSDK_ROOT = "D:\tools\emsdk"   # wherever emsdk is installed
.\powerbi\build_wasm.ps1              # -> powerbi\src\doom.js
```

Optional smoke test in a plain browser before touching Power BI:

```bash
cd powerbi && node dev/serve.js       # http://127.0.0.1:8099/  (dev/test.html)
```

`dev/sandbox.html` replays the build inside an `allow-scripts`-only iframe, which
is the same sandbox Power BI uses.

### 2. Visual → `.pbiviz`

```bash
cd powerbi
npm ci                                # pulls powerbi-visuals-tools (the pbiviz CLI)
npm run package                       # -> dist/*.pbiviz
```

## The one non-obvious gotcha

A custom visual with an empty `dataViewMappings` makes Power BI paint its own
*"Select or drag fields to populate this visual"* watermark **over** the visual.
The fix (in [`capabilities.json`](capabilities.json)) is to keep a real,
condition-free categorical mapping **and** set `"supportsLandingPage": true` so
Power BI lets the visual render with nothing bound. `supportsKeyboardFocus` is
what lets the canvas receive key events at all.

## Licensing

doomgeneric and the DOOM source are GPLv2; so is this port (see the repository
`LICENSE`). The embedded `doom1.wad` is id Software's freely redistributable
shareware episode — retail WADs are **not** redistributable and must not be
embedded. DOOM is a trademark of id Software LLC / ZeniMax Media; Power BI is a
trademark of Microsoft. This is an unofficial hobby port.
