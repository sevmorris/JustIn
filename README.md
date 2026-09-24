# JustIn

> **Retired on 2026-09-24. Use [WaxOn/WaxOff](https://github.com/sevmorris/WaxOnWaxOff) instead,** which covers what JustIn did. JustIn gets no further updates, and this repository is archived and kept for reference. Its last release, v1.0.4, stays downloadable.

Media file analyzer for macOS · Version 1.0.4 · [Download DMG](https://github.com/sevmorris/JustIn/releases/latest/download/JustIn-v1.0.4.dmg)

Drop one or more audio or video files onto the window to inspect their technical properties: format, duration, sample rate, channels, bit depth, codec, bitrate, file size, modification date, embedded metadata, and chapter markers. Video files also report resolution and color space.

Loudness analysis runs as a separate pass: integrated loudness (LUFS) is measured using a native ITU-R BS.1770 implementation. If `ffmpeg` is available on `PATH`, true peak (dBTP), loudness range (LRA), and CBR/VBR mode are also reported. Loudness values are color-coded against standard podcast delivery targets. A per-channel RMS waveform is displayed in a resizable pane below the metadata.

AVFoundation fields populate immediately; the loudness pass runs in the background with live progress. All analysis is local — no network access.

Related: [WaxOn/WaxOff](https://github.com/sevmorris/WaxOnWaxOff)

---

## Supported formats
WAV, AIFF, AIF, MP3, M4A, CAF, FLAC, MP4, M4V, MOV. Formats AVFoundation cannot natively decode (OGG, MKV, AVI) are not supported.

## Requirements
* macOS 14.0 or later
* Optional: `ffmpeg` and `ffprobe` on `PATH` for true peak, loudness range, and CBR/VBR detection (`brew install ffmpeg`)

## Building
```bash
xcodebuild -project JustIn.xcodeproj -scheme JustIn -configuration Release
```

---

### License
[GNU GPL v3.0](LICENSE)
