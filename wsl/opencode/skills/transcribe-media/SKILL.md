---
name: transcribe-media
description: Transcribe audio and video into markdown, and OCR text out of images. Use whenever the user wants a transcript, captions, subtitles, or the spoken content of a recording, podcast, video clip, or meeting — or wants text pulled out of a screenshot, photo, or scanned image. Also handles media that exists only as a URL (fetch it locally with download-video first). Do NOT use for .pdf, .docx, .pptx, or .xlsx — route those to the pdf, docx, pptx, and xlsx skills, which handle those formats directly.
metadata:
  origin: Andrea Sergi
compatibility: markitdown MCP (primary), markitdown via uvx (fallback), nix/uvx OCR tools
---

# Transcribe Media

Convert media files into readable markdown text.

## Backend availability

**Primary: the `markitdown` MCP server**, configured in `~/.config/opencode/opencode.json`. When it is enabled in the current session its tools are available and you should prefer it — no extra install, and output stays consistent across media types.

**Fallback: the `markitdown` CLI via `uvx`.** If the MCP server is disabled or its tools are missing from your tool list, or an MCP call errors out, do **not** stop and ask the user to enable it — run the CLI instead:

```bash
uvx --from markitdown markitdown <file>
```

On this host `uvx` uses uv-managed Python, so packages pulling numpy load Ubuntu's `libstdc++` directly; no `LD_LIBRARY_PATH` prefix is needed.

Both backends produce equivalent markdown, so the rest of this skill applies unchanged.

## Workflow

1. **Locate the file.** If the media exists only as a URL, invoke the `download-video` skill first to fetch it locally.
2. **Convert** with markitdown — *except for images*, which markitdown cannot OCR (see [OCR section](#ocr-text-in-images)). Use whichever backend from [Backend availability](#backend-availability) is live in this session.
3. **Save** the result to a `.md` file following the naming rules below.
4. If a time range was requested, save the full transcript *and* a snippet file covering just that range.

## Naming the output file

- Time-range snippet of a video/audio clip:
  `<MM:SS-MM:SS>_[link_id]_[video_name]_snippet.md`
- Full transcript of a video/audio:
  `<MM:SS-MM:SS>_[link_id]_[video_name].md`
- Anything else (image, PDF, document): the source file's basename, e.g. `screenshot.png` → `screenshot.md`

Where:
- `<link_id>` is the media identifier from the source URL (e.g. the YouTube ID).
- `<video_name>` is a short, sanitized slug of the title (lowercase, hyphens instead of spaces).

## What markitdown produces per type

| Type | Output |
|------|--------|
| audio (mp3, wav, m4a) | spoken-word transcription |
| video (mp4, webm) | spoken-word transcription |
| image (png, jpg) | **no text** — markitdown only reads EXIF metadata; run a dedicated OCR tool instead (below) |

For `.pdf`, `.docx`, `.pptx`, and `.xlsx` use the sibling skills instead — they produce better structure than markitdown's generic extraction.

## OCR (text in images)

markitdown does **not** extract text from images, so use a dedicated OCR tool. Never modify the system to get one — every tool below runs isolated via `nix run` or `uvx`.

### Primary: Tesseract

The mature, offline, always-available default — best for clean screenshots, UI captures, and scans of printed text.

`nix run nixpkgs#tesseract -- <image> stdout`

- Add languages when the content isn't English (nixpkgs ships all language data):
  `nix run nixpkgs#tesseract -- <image> stdout -l eng+chi_sim`
- List available languages:
  `nix run nixpkgs#tesseract -- --list-langs`

### When tesseract underperforms

Low contrast, rotation, photos, dense layouts, or handwriting: try a deep-learning engine before giving up.

- **RapidOCR** (ONNX, lightweight, good accuracy): `uvx --from rapidocr-onnxruntime rapidocr <image>`
- **PaddleOCR** (strong for complex scenes and CJK): `uvx --from paddleocr paddleocr --image_dir <image> --lang en`
- **EasyOCR**: `uvx --from easyocr easyocr -f <image>`
- **Last resort**: ask a multimodal model (e.g. the session model) to read the image verbatim. Treat that result as an unverified caption, not a faithful transcript.

### Preprocessing (usually worth it)

OCR accuracy improves dramatically on clean input — upscale, grayscale, and threshold first. ffmpeg is already present:

`ffmpeg -i <image> -vf "scale=iw*2:ih*2,format=gray" <preprocessed>.png`

Run the OCR command above against the preprocessed copy, not the original.

## Tooling caveats

- Never make system-wide changes to install missing tools. Use isolated runners: `uvx`, `npx`, or `nix run nixpkgs#...`.
- Prefer the configured `markitdown` MCP when it is enabled, so no separate install is needed; fall back to the `uvx` CLI when it is not — except for images, where OCR tools are required either way.
