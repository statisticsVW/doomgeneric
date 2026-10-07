// doomgeneric platform port for Power BI custom visual (browser, no SDL).
// Renders DG_ScreenBuffer into a 2D canvas via a JS blit callback and takes
// keyboard input pushed from JS (already translated to DOOM key codes).

#include "doomgeneric.h"
#include "doomkeys.h"

#include <stdint.h>
#include <string.h>
#include <emscripten.h>

#define KEYQUEUE_SIZE 16

static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int   s_KeyQueueWriteIndex = 0;
static unsigned int   s_KeyQueueReadIndex  = 0;

// RGBA scratch buffer handed to the canvas. DG_ScreenBuffer pixels are packed
// 0x00RRGGBB; canvas ImageData wants R,G,B,A byte order, so we swizzle.
static uint8_t s_Rgba[DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4];

// Pushed from JS. doomKey is an already-translated DOOM key code (doomkeys.h).
EMSCRIPTEN_KEEPALIVE
void dg_add_key(int pressed, int doomKey)
{
    unsigned short keyData = (unsigned short)(((pressed ? 1 : 0) << 8) | (doomKey & 0xff));
    s_KeyQueue[s_KeyQueueWriteIndex] = keyData;
    s_KeyQueueWriteIndex = (s_KeyQueueWriteIndex + 1) % KEYQUEUE_SIZE;
}

void DG_Init(void)
{
}

void DG_DrawFrame(void)
{
    const int n = DOOMGENERIC_RESX * DOOMGENERIC_RESY;
    for (int i = 0; i < n; i++)
    {
        uint32_t p = DG_ScreenBuffer[i];
        s_Rgba[i * 4 + 0] = (uint8_t)((p >> 16) & 0xff); // R
        s_Rgba[i * 4 + 1] = (uint8_t)((p >> 8)  & 0xff); // G
        s_Rgba[i * 4 + 2] = (uint8_t)( p        & 0xff); // B
        s_Rgba[i * 4 + 3] = 0xff;                        // A
    }

    EM_ASM({
        if (Module.dgBlit) Module.dgBlit($0, $1, $2);
    }, s_Rgba, DOOMGENERIC_RESX, DOOMGENERIC_RESY);
}

void DG_SleepMs(uint32_t ms)
{
    (void)ms; // RAF main loop paces us; never block.
}

uint32_t DG_GetTicksMs(void)
{
    return (uint32_t)emscripten_get_now();
}

int DG_GetKey(int* pressed, unsigned char* doomKey)
{
    if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex)
        return 0;

    unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];
    s_KeyQueueReadIndex = (s_KeyQueueReadIndex + 1) % KEYQUEUE_SIZE;

    *pressed = (int)(keyData >> 8);
    *doomKey = (unsigned char)(keyData & 0xff);
    return 1;
}

void DG_SetWindowTitle(const char* title)
{
    (void)title;
}

int main(int argc, char** argv)
{
    (void)argc;
    (void)argv;

    // The shareware IWAD is embedded into MEMFS at /doom1.wad (see emcc --embed-file).
    char* args[] = { "doom", "-iwad", "/doom1.wad" };
    doomgeneric_Create(3, args);

    emscripten_set_main_loop(doomgeneric_Tick, 0, 1);
    return 0;
}
