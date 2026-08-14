---
name: transcribe-media
description: Transcribe or extract the text content of any media file (audio, video, images, PDFs, Office documents) into markdown using the markitdown MCP. Use this whenever the user asks to transcribe, caption, or pull the text out of a recording, podcast, video clip, screenshot, scanned document, PDF, or a .docx/.pptx/.xlsx file. Make sure to use this skill for any media content extraction request, even if the user doesn't say "transcribe" explicitly.
origin: Andrea Sergi
compatibility: markitdown MCP
---

# Transcribe Media

Convert media files into readable markdown text. Always use the `markitdown` MCP for the conversion — it is already configured, so no extra installs are needed and the output stays consistent across media types.
If the `markitdown` mcp server is not available stop and prompt the user to activate it.

## Workflow

1. **Locate the file.** If the media exists only as a URL, invoke the `download-video` skill first to fetch it locally.
2. **Convert** with the `markitdown` MCP — *except for images*, which markitdown cannot OCR (see [OCR section](#ocr-text-in-images)).
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
| PDF, .docx, .pptx, .xlsx | structured text extraction |
| image (png, jpg) | **no text** — markitdown only reads EXIF metadata; run a dedicated OCR tool instead (below) |

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
- Prefer the configured `markitdown` MCP so no separate install is needed — except for images, where OCR tools are required.
