/*
 *  Doom in Power BI — a custom visual that runs the shareware DOOM via a
 *  WebAssembly build of doomgeneric, rendered into a 2D canvas.
 */
"use strict";

import powerbi from "powerbi-visuals-api";
import "./../style/visual.less";

import VisualConstructorOptions = powerbi.extensibility.visual.VisualConstructorOptions;
import VisualUpdateOptions = powerbi.extensibility.visual.VisualUpdateOptions;
import IVisual = powerbi.extensibility.visual.IVisual;

// The Emscripten single-file Doom module (UMD). Loaded via require so TS does
// not try to resolve a declaration for the bundled .js; webpack bundles it.
interface DoomModule {
    HEAPU8: Uint8Array;
    _dg_add_key: (pressed: number, doomKey: number) => void;
    dgBlit?: (ptr: number, w: number, h: number) => void;
    [key: string]: unknown;
}
declare function require(path: string): unknown;
const createDoom = require("./doom.js") as (moduleArg?: Partial<DoomModule>) => Promise<DoomModule>;

const DOOM_W = 640;
const DOOM_H = 400;

function el(tag: string, className: string, text?: string): HTMLDivElement {
    const node = document.createElement(tag) as HTMLDivElement;
    node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
}

// DOOM key codes (from doomgeneric/doomkeys.h).
const K = {
    RIGHTARROW: 0xae,
    LEFTARROW: 0xac,
    UPARROW: 0xad,
    DOWNARROW: 0xaf,
    STRAFE_L: 0xa0,
    STRAFE_R: 0xa1,
    USE: 0xa2,
    FIRE: 0xa3,
    ESCAPE: 27,
    ENTER: 13,
    TAB: 9,
    BACKSPACE: 0x7f,
    RSHIFT: 0x80 + 0x36,
    RALT: 0x80 + 0x38,
    EQUALS: 0x3d,
    MINUS: 0x2d,
};

export class Visual implements IVisual {
    private target: HTMLElement;
    private root: HTMLDivElement;
    private canvas: HTMLCanvasElement;
    private ctx: CanvasRenderingContext2D;
    private imageData: ImageData;
    private overlay: HTMLDivElement;

    private module: DoomModule | null = null;
    private focused = false;

    constructor(options: VisualConstructorOptions) {
        this.target = options.element;
        this.buildDom();
        this.startDoom();
    }

    private buildDom(): void {
        this.root = document.createElement("div");
        this.root.className = "doom-root";

        this.canvas = document.createElement("canvas");
        this.canvas.width = DOOM_W;
        this.canvas.height = DOOM_H;
        this.canvas.className = "doom-canvas";
        this.canvas.tabIndex = 0; // focusable, so it can receive key events
        this.ctx = this.canvas.getContext("2d", { alpha: false }) as CanvasRenderingContext2D;
        this.imageData = this.ctx.createImageData(DOOM_W, DOOM_H);

        this.overlay = document.createElement("div");
        this.overlay.className = "doom-overlay";
        const inner = el("div", "doom-overlay-inner");
        inner.appendChild(el("div", "doom-title", "DOOM"));
        inner.appendChild(el("div", "doom-sub", "Click to play"));
        inner.appendChild(el("div", "doom-help",
            "Move: W/S + ←/→   |   Strafe: A/D   |   " +
            "Fire: Ctrl   |   Use/Open: Space   |   Menu: Enter/Esc"));
        this.overlay.appendChild(inner);

        this.root.appendChild(this.canvas);
        this.root.appendChild(this.overlay);
        this.target.appendChild(this.root);

        // Focus handling: keyboard only flows once the visual is clicked.
        const focus = () => {
            this.canvas.focus();
            this.focused = true;
            this.overlay.classList.add("hidden");
        };
        this.root.addEventListener("mousedown", focus);
        this.canvas.addEventListener("blur", () => { this.focused = false; });

        this.canvas.addEventListener("keydown", (e) => this.onKey(e, 1));
        this.canvas.addEventListener("keyup", (e) => this.onKey(e, 0));
    }

    private onKey(e: KeyboardEvent, pressed: number): void {
        const key = this.mapKey(e);
        if (key < 0) return;
        // Stop Power BI from scrolling / shifting focus on game keys.
        e.preventDefault();
        e.stopPropagation();
        if (this.module && this.module._dg_add_key) {
            this.module._dg_add_key(pressed, key);
        }
    }

    private mapKey(e: KeyboardEvent): number {
        switch (e.code) {
            case "ArrowUp": case "KeyW": return K.UPARROW;
            case "ArrowDown": case "KeyS": return K.DOWNARROW;
            case "ArrowLeft": return K.LEFTARROW;
            case "ArrowRight": return K.RIGHTARROW;
            case "KeyA": return K.STRAFE_L;
            case "KeyD": return K.STRAFE_R;
            case "Space": return K.USE;
            case "ControlLeft": case "ControlRight": return K.FIRE;
            case "ShiftLeft": case "ShiftRight": return K.RSHIFT;
            case "AltLeft": case "AltRight": return K.RALT;
            case "Enter": return K.ENTER;
            case "Escape": return K.ESCAPE;
            case "Tab": return K.TAB;
            case "Backspace": return K.BACKSPACE;
            case "Minus": return K.MINUS;
            case "Equal": return K.EQUALS;
        }
        // Digits (weapon select) and letters (menu y/n etc.) -> lowercase ASCII.
        if (e.key.length === 1) {
            const c = e.key.toLowerCase().charCodeAt(0);
            if (c >= 32 && c < 127) return c;
        }
        return -1;
    }

    private startDoom(): void {
        // Emscripten (MODULARIZE) uses the object we pass in AS `Module`, attaching
        // HEAPU8 / _dg_add_key onto it. So we keep a reference now; dgBlit (which can
        // fire before the factory promise resolves) reads HEAPU8 off the same object.
        const mod = {} as DoomModule;
        mod.dgBlit = (ptr: number, w: number, h: number) => {
            const heap = mod.HEAPU8; // re-read each frame: it detaches on memory growth
            if (!heap) return;
            const src = heap.subarray(ptr, ptr + w * h * 4);
            this.imageData.data.set(src);
            this.ctx.putImageData(this.imageData, 0, 0);
        };
        this.module = mod;

        createDoom(mod).catch((err) => {
            console.error("Doom failed to start", err);
            this.module = null;
            this.showError(String(err));
        });
    }

    private showError(msg: string): void {
        this.overlay.classList.remove("hidden");
        this.overlay.replaceChildren();
        const inner = el("div", "doom-overlay-inner");
        inner.appendChild(el("div", "doom-title", "ERROR"));
        inner.appendChild(el("div", "doom-sub", msg));
        this.overlay.appendChild(inner);
    }

    public update(options: VisualUpdateOptions): void {
        // No data binding; just keep the canvas fitted to the viewport (16:10).
        const vp = options.viewport;
        const scale = Math.max(0.01, Math.min(vp.width / DOOM_W, vp.height / DOOM_H));
        const w = Math.round(DOOM_W * scale);
        const h = Math.round(DOOM_H * scale);
        this.canvas.style.width = w + "px";
        this.canvas.style.height = h + "px";
    }
}
