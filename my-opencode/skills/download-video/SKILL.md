---
name: download-video
description: Download video given the link using yt-ldp and ffmpeg
origin: Andrea Sergi
---

# Download Video

This skill will be invoked with a url linking to a video
- the base command will be this:
`uvx --with certifi yt-dlp --js-runtimes node <link_to_video> --downloader ffmpeg`
- If a specific time range of interest is specified you'll add these options:
`uvx --with certifi yt-dlp --js-runtimes node <link_to_video> --downloader ffmpeg --downloader-args "ffmpeg_i:-ss <start_time_in_seconds> -to <end_time_in_seconds>"`


# After Download

- You might be asked to transcribed the downloaded audio content in which case you'll be using the `markitdown` MCP
- You might be asked to transcribed the downloaded video content in which case you'll be using the `markitdown` MCP

Save the transcription:
- ***AUDIO: *** "<MM:SS-MM:SS>_[link_id]_[video_name].md"
- ***VIDEO: *** "<MM:SS-MM:SS>_[link_id]_[video_name]_snippet.md"

# Transcription Caveats:

- If to carry out the requested command you need tools not currently present in the system DO NOT EVER make system wide changes.
Use something linke 'uvx', 'nixpkgs#', 'npx' etc...
