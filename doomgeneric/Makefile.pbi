################################################################
#
# Power BI custom-visual port.
#
# Builds doomgeneric with the no-SDL browser shim (doomgeneric_pbi.c) into a
# SINGLE JavaScript file, doom.js, with the .wasm and the shareware doom1.wad
# base64-inlined. Power BI's visual sandbox blocks all network access, so the
# whole game has to ship inside the bundle; ../powerbi/ webpacks doom.js into
# the .pbiviz.
#
#   make -f Makefile.pbi            # -> doom.js
#   make -f Makefile.pbi install    # -> ../powerbi/src/doom.js
#
# Requires emcc on PATH and doom1.wad (shareware) in this directory.
# On Windows without make, ../powerbi/build_wasm.ps1 runs the same build.
#

ifeq ($(V),1)
	VB=''
else
	VB=@
endif

CC=emcc
CFLAGS+=-O2 -Wall -DNORMALUNIX -DLINUX -I.

WAD=doom1.wad
# Shareware DOOM1.WAD v1.9 — the exact file that gets embedded and shipped.
WAD_SHA256=1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771

LDFLAGS+=-s SINGLE_FILE=1 \
         -s MODULARIZE=1 \
         -s EXPORT_NAME=createDoom \
         -s ENVIRONMENT=web \
         -s ALLOW_MEMORY_GROWTH=1 \
         -s INITIAL_MEMORY=67108864 \
         -s EXIT_RUNTIME=0 \
         -s EXPORTED_RUNTIME_METHODS="['callMain','HEAPU8']" \
         -s EXPORTED_FUNCTIONS="['_main','_dg_add_key','_doomgeneric_Tick']" \
         --embed-file $(WAD)@/$(WAD)

# subdirectory for objects
OBJDIR=build
OUTPUT=doom

SRC_DOOM = dummy.o am_map.o doomdef.o doomstat.o dstrings.o d_event.o d_items.o d_iwad.o d_loop.o d_main.o d_mode.o d_net.o f_finale.o f_wipe.o g_game.o hu_lib.o hu_stuff.o info.o i_cdmus.o i_endoom.o i_joystick.o i_scale.o i_sound.o i_system.o i_timer.o memio.o m_argv.o m_bbox.o m_cheat.o m_config.o m_controls.o m_fixed.o m_menu.o m_misc.o m_random.o p_ceilng.o p_doors.o p_enemy.o p_floor.o p_inter.o p_lights.o p_map.o p_maputl.o p_mobj.o p_plats.o p_pspr.o p_saveg.o p_setup.o p_sight.o p_spec.o p_switch.o p_telept.o p_tick.o p_user.o r_bsp.o r_data.o r_draw.o r_main.o r_plane.o r_segs.o r_sky.o r_things.o sha1.o sounds.o statdump.o st_lib.o st_stuff.o s_sound.o tables.o v_video.o wi_stuff.o w_checksum.o w_file.o w_main.o w_wad.o z_zone.o w_file_stdc.o i_input.o i_video.o doomgeneric.o doomgeneric_pbi.o
OBJS += $(addprefix $(OBJDIR)/, $(SRC_DOOM))

all:	 $(OUTPUT).js

clean:
	rm -rf $(OBJDIR)
	rm -f $(OUTPUT).js
	rm -f $(OUTPUT).wasm

# Refuse to embed anything but the known shareware WAD.
wadcheck:
	@test -f $(WAD) || { echo "$(WAD) not found - see ../powerbi/README.md"; exit 1; }
	@echo "$(WAD_SHA256)  $(WAD)" | sha256sum -c - >/dev/null || { echo "$(WAD) SHA-256 mismatch - refusing to embed an unverified WAD"; exit 1; }
	@echo [WAD ok]

$(OUTPUT).js:	wadcheck $(OBJS)
	@echo [Linking $@]
	$(VB)$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $(OUTPUT).js
	@echo [Size]
	@ls -l $(OUTPUT).js

install:	$(OUTPUT).js
	cp $(OUTPUT).js ../powerbi/src/doom.js
	@echo [Installed -> ../powerbi/src/doom.js]

$(OBJS): | $(OBJDIR)

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/%.o:	%.c
	@echo [Compiling $<]
	$(VB)$(CC) $(CFLAGS) -c $< -o $@

print:
	@echo OBJS: $(OBJS)
