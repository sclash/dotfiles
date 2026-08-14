---
name: download-video
description: Download a video (or audio) from a URL using yt-dlp via uvx and ffmpeg. Use this whenever the user provides a link to a video or audio file and wants to download it, in full or only a specific time range. Also use it to fetch media locally before transcribing it with the transcribe-media skill.
origin: Andrea Sergi
compatibility: uv (uvx), node (for JS runtimes), ffmpeg
---

# Download Video

This skill triggers when the user gives a URL to a video or audio and wants it saved locally, either whole or as a clip of a time range.

## Base command

`uvx --with certifi yt-dlp --js-runtimes node <link_to_video> --downloader ffmpeg`

## Downloading a time range

When the user specifies a time range, prefer yt-dlp's native section download — it is built in, reliable, and avoids ambiguous seek semantics:

`uvx --with certifi yt-dlp --js-runtimes node <link_to_video> --download-sections "*<start>-<end>" --downloader ffmpeg`

`<start>` and `<end>` are absolute positions in the media, e.g. `--download-sections "*6:53-7:20"`.

If `--download-sections` is unavailable or misbehaves for a given site, fall back to passing ffmpeg seek arguments through the downloader:

`uvx --with certifi yt-dlp --js-runtimes node <link_to_video> --downloader ffmpeg --downloader-args "ffmpeg_i:-ss <start_time_in_seconds> -to <end_time_in_seconds>"`

Note: with `-ss` as an input option, ffmpeg's `-to` is interpreted relative to the start point, so `-ss 413 -to 440` yields the clip from 6:53 to 7:20.

## After download

- Confirm the saved file name and location with the user.
- If the user also wants the content transcribed, invoke the `transcribe-media` skill on the downloaded file.

## Tooling caveats

- Never make system-wide changes to install missing tools. Use isolated runners: `uvx`, `npx`, or `nix run nixpkgs#...`.

## Example

Input: "Download the first two minutes of https://www.youtube.com/watch?v=abc123"

Output: run
`uvx --with certifi yt-dlp --js-runtimes node https://www.youtube.com/watch?v=abc123 --download-sections "*0:00-2:00" --downloader ffmpeg`
and report where the file was saved.
