# Doodledo

An iOS doodle journal with a calendar/gallery view, PencilKit tools, and optional AI image generation for lassoed regions.

## Features

- Daily doodle prompt with streak tracking.
- Calendar views (week/month/year) plus gallery grid.
- PencilKit drawing tools (ink, marker, eraser, lasso).
- Notes/captions per entry.
- "Girlypop" theme toggle.
- AI image generation using OpenAI Images Edit (`gpt-image-1.5`) on a lasso selection.

## Requirements

- Xcode 15+
- iOS 17.0+

## Run

1. Open `doodledo.xcodeproj` in Xcode.
2. Select the `doodledo` scheme.
3. Run on Simulator or device.

## OpenAI setup (optional)

When you tap **Generate**, the app prompts for an OpenAI API key and stores it locally in `UserDefaults` (`openai_api_key`). No key is checked into the repo.

Notes:
- The key is stored only on-device.
- For production, move the key and request to a backend.

## Testing

The `DoodleCore` SwiftPM module includes unit tests:

```bash
cd DoodleCore
swift test
```

## Data storage

Right now entries live in-memory only and reset on relaunch.
