# Custom sounds

Drop custom addon sound files here and reference them by path, e.g.
`Interface\AddOns\ExsarAddon\Sounds\windfury.ogg`.

## Windfury proc whoosh

`MeleeWeaveHelper.lua` plays `Sounds/windfury.ogg` on a Windfury extra-attack
proc (see `WINDFURY_SOUND`). If that file is absent it falls back to the
built-in Whirlwind whoosh (FileDataID 568519), so the effect still works with
no file present.

To use your own sound:
1. Put an **`.ogg`** file here named `windfury.ogg` (Vorbis; 44100 Hz; keep it
   short). `.wav` is NOT supported by the modern Anniversary client; `.ogg` is
   the safe choice (`.mp3` usually works too).
2. **Fully restart the WoW client** — not just `/reload`. WoW indexes sound
   files at launch, so a newly added file is invisible until relaunch.
3. Test in-game with `/exsar wftest`.

## Regenerating windfury.ogg

`windfury.ogg` is procedurally synthesized (a filtered-noise blade-whoosh — no
samples). To retune it, edit the DSP knobs (duration, sweep, envelope) in
`windfury_gen.py` and re-run:

```
python3 windfury_gen.py                        # writes Sounds/windfury.wav
ffmpeg -y -i windfury.wav -c:a vorbis -strict -2 -ac 2 -b:a 112k -ar 44100 windfury.ogg
rm windfury.wav
```

Note the `-c:a vorbis -strict -2 -ac 2`: if your ffmpeg lacks `libvorbis`, the
built-in experimental `vorbis` encoder works but needs **stereo** (`-ac 2`).
With `libvorbis` available, `-c:a libvorbis -qscale:a 5` gives better quality.
