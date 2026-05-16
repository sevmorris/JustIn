# JustIn
### Media File Analyzer for macOS

<p align="center">
  <strong>Drag-and-drop audio &amp; video inspection</strong>
  <br />
  <strong>Version:</strong> 1.0
  <br />
  <a href="https://github.com/sevmorris/JustIn/releases/latest/download/JustIn-v1.0.dmg"><strong>Download Latest (DMG)</strong></a>
</p>

**JustIn** answers a simple question fast: *what exactly is this file?* Drop one or
more audio or video files on the window and JustIn reports their technical
properties — format, sample rate, channels, codecs, resolution, color space,
bitrate, embedded metadata, chapters — alongside a measured loudness profile and
a passive waveform fingerprint.

- **Loudness, done right.** Integrated loudness is measured natively with an
  ITU-R BS.1770 implementation (no dependency). When `ffmpeg` is present, true
  peak (dBTP) and loudness range (LRA) are measured in the same pass; the
  loudness values are color-coded against standard podcast delivery targets.
- **Progressive analysis.** Fast AVFoundation fields appear immediately; the
  loudness pass fills in with live progress.
- **Waveform fingerprint.** A muted, per-render-normalized RMS waveform in a
  resizable, position-persisting pane — a shape fingerprint, not a loudness
  meter.
- **Local only.** No upload, no network, no audio leaving your machine.
  `ffmpeg`/`ffprobe` are used from your `PATH` if installed (Homebrew etc.); the
  app degrades gracefully without them.

JustIn is a focused companion to the
[WaxOn/WaxOff](https://github.com/sevmorris/WaxOnWaxOff) audio toolchain and
shares its visual language.

## Supported formats

WAV, WAVE, AIF, AIFF, MP3, M4A, CAF, FLAC, MP4, M4V, MOV. Formats AVFoundation
cannot natively decode (OGG, MKV, AVI) are intentionally excluded.

## Requirements

- macOS 14.0 or later
- Optional: `ffmpeg` + `ffprobe` on `PATH` for true peak, loudness range, and
  CBR/VBR detection (`brew install ffmpeg`)

## Building

```bash
xcodebuild -project JustIn.xcodeproj -scheme JustIn -configuration Release
```

## License

[GNU GPL v3.0](LICENSE)
