# PokeCard 📸

An **unofficial, fan-made** iOS app to scan trading cards, check a price
estimate, and build a personal collection. Built with SwiftUI + MVVM.

> ⚠️ Not affiliated with, endorsed by, or sponsored by The Pokémon Company,
> Nintendo, Game Freak, or Creatures Inc. See [`LICENSING.md`](LICENSING.md)
> for the full copyright-compliance policy — please read it before contributing.

## Features

- 🔐 **Auth** — Email/password + Google sign-in via Firebase.
- 🏠 **Cute home** — pick *Scan* or *My Collection* from a friendly, pastel UI.
- 🎯 **Scan** — live camera preview with on-device card detection. Rounded
corner "guiding lines" snap to the detected card and glow green once it's
validated.
- 🔎 **Validation** — the cropped card is read with on-device OCR; a heuristic
validator checks for *factual* card markers (HP, energy types, set number) to
decide whether it looks like a real card. No copyrighted artwork is used.
- 💰 **Price estimate** — pluggable `PriceEstimating` service (stub included).
- 📚 **Collection** — saved cards persist locally with SwiftData.

## Architecture

```
PokeCard/
├── App/                 # Entry point, AppState, routing, bootstrap
├── Core/
│   ├── Camera/          # AVFoundation capture
│   ├── DesignSystem/    # Cute theme, button/field/card styles
│   ├── Models/          # AppUser, CollectedCard (SwiftData)
│   ├── Services/        # Auth, pricing, image store
│   └── Vision/          # Rectangle detection + OCR + validator
└── Features/
    ├── Auth/            # Login / Sign up
    ├── Home/            # Entry points
    ├── Scanner/         # Camera scanning + guiding overlay
    └── Collection/      # Saved cards grid
```

Key abstractions (so vendors can be swapped and the UI can be previewed):


| Protocol                 | Default impl              | Swap for                 |
| ------------------------ | ------------------------- | ------------------------ |
| `AuthServicing`          | `FirebaseAuthService`     | mocks / other providers  |
| `CardRectangleDetecting` | `VisionRectangleDetector` | a CoreML/YOLO detector\* |
| `PriceEstimating`        | `StubPriceEstimator`      | a licensed pricing API   |


\* If you add a YOLO/CoreML detector, train it on the **generic shape of a
trading card**, never on copyrighted artwork. See `LICENSING.md`.

## Recognition pipeline (on-device, private)

1. `CameraController` streams video frames (`CVPixelBuffer`).
2. `VisionRectangleDetector` finds the most card-like quad (aspect ≈ 0.716).
3. `CardGuideOverlay` draws rounded corner brackets around the detected quad.
4. On capture, the still is cropped to the quad and read by
 `CardTextRecognizer` (Vision OCR).
5. `PokemonCardValidator` scores the text against factual card markers.
6. Valid cards can be saved to the SwiftData collection + priced.

## Setup

### Quick install (no Xcode GUI) — `install.sh`

Build and install straight onto a connected iPhone with one command:

```bash
./install.sh
```

The script will:

1. Verify the toolchain (full Xcode, `xcodebuild`, `devicectl`).
2. Install **XcodeGen** via Homebrew if needed, then generate
 `PokeCard.xcodeproj` from [`project.yml`](project.yml).
3. Resolve your Apple Developer **Team ID** (auto-detected, or pass it in).
4. Build a signed `.app` for your device.
5. Install it onto the connected iPhone with `xcrun devicectl`.

Options via environment variables:

```bash
# Pass your team id explicitly (find it in Xcode ▸ Settings ▸ Accounts):
POKECARD_TEAM_ID=ABCDE12345 ./install.sh

# Use your own bundle identifier:
POKECARD_BUNDLE_ID=com.yourname.pokecard ./install.sh
```

Requirements for on-device install:

- **Full Xcode** installed (not just Command Line Tools).
- An **Apple ID added to Xcode** (Xcode ▸ Settings ▸ Accounts). A *free*
Apple ID works, but the app expires after **7 days** — just re-run the script.
- iPhone connected via USB (or Wi-Fi paired), unlocked, "Trust This Computer"
accepted, and **Developer Mode** enabled (Settings ▸ Privacy &amp; Security ▸
Developer Mode) on iOS 16+.
- Homebrew (only needed to auto-install XcodeGen).

> First launch: if iOS blocks the app, trust the certificate at
> Settings ▸ General ▸ VPN &amp; Device Management ▸ (your Apple ID) ▸ Trust.

Firebase/Google sign-in still needs `GoogleService-Info.plist` and the
`REVERSED_CLIENT_ID` in `Info.plist` (see *Configure Firebase* below). Without
it the app launches fine and the camera/scanner work; only auth is disabled.

### Alternative: open in Xcode manually

If you prefer the GUI, generate the project and open it:

```bash
brew install xcodegen
xcodegen generate
open PokeCard.xcodeproj
```

Then set your signing team on the target and run.

### Create the Xcode project (fully manual)

This repo contains the Swift source tree. Create an app target around it:

1. Xcode → **File ▸ New ▸ Project ▸ iOS App**.
   - Interface: **SwiftUI**, Language: **Swift**, Storage: **SwiftData** (or None).
   - Delete the generated `ContentView.swift` / `App.swift`.
2. Add the `PokeCard/` folder to the target ("Create groups").
3. Set the target's **Info.plist** to `PokeCard/Resources/Info.plist`, or copy
 the `NSCameraUsageDescription` and `CFBundleURLTypes` keys into your own.
4. Deployment target: **iOS 17+** (required for SwiftData + the newer SwiftUI
 APIs used here).

### Add dependencies (Swift Package Manager)

Xcode → **File ▸ Add Package Dependencies…**

- `https://github.com/firebase/firebase-ios-sdk` → add **FirebaseAuth**
(and FirebaseCore).
- `https://github.com/google/GoogleSignIn-iOS` → add **GoogleSignIn**.

Pin to a specific version rather than "up to next major" for reproducible builds.

The auth code is wrapped in `#if canImport(...)` guards, so the project still
compiles before the packages are added (useful for UI previews).

### 3. Configure Firebase

1. Create a Firebase project and an iOS app with your bundle ID.
2. Enable **Email/Password** and **Google** providers in
 *Authentication ▸ Sign-in method*.
3. Download `GoogleService-Info.plist` and add it to the app target.
 (It's git-ignored by default — keep it out of source control.)
4. Open `GoogleService-Info.plist`, copy the `REVERSED_CLIENT_ID` value, and
 paste it into the `CFBundleURLSchemes` entry in `Info.plist`.

If `GoogleService-Info.plist` is missing, the app still launches (auth calls
return a clear "not configured" error) so you can work on the UI.

### 4. Run

Build &amp; run on a **physical device** (the camera isn't available in the
simulator). Previews use a mock auth service and in-memory data.

## Privacy

- All image processing is **on-device**. Photos are not uploaded.
- Captured images are stored in the app's sandbox (`Documents/cards`).
- See `LICENSING.md` for the copyright/trademark policy.

## Roadmap ideas

- Perspective-correct the crop before OCR for better accuracy.
- Expose the camera buffer dimensions to the overlay for a pixel-perfect fit
under `.resizeAspectFill`.
- Replace the stub pricer with a licensed pricing API.
- # Optional iCloud/Firestore sync (update the privacy policy accordingly).

# PokeCard

포켓몬 카드 수집용

> > > > > > > af5fd24b31e1ce71aabd2086b33b69ce7b99c9dd

