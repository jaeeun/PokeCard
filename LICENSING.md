# Licensing & Copyright Compliance

This document explains how **PokeCard** is designed to avoid infringing the
intellectual property of The Pokémon Company, Nintendo, Game Freak, Creatures
Inc., or any third party. Treat it as a binding design constraint — do not add
features that violate these principles.

## 1. Nature of the app

PokeCard is an **unofficial, fan-made utility**. It is **not** affiliated with,
endorsed, sponsored, or approved by The Pokémon Company or any rights holder.
"Pokémon" and all related names are trademarks of their respective owners and
are used here only nominatively (to describe compatibility), never as branding.

## 2. What we DO

- Process **only the user's own photos**, captured live with their device camera.
- Run all recognition **on-device** (Apple Vision for rectangle detection + OCR).
  No images are uploaded to our servers.
- Derive **factual data** from the card via OCR: the card name and the set
  number (e.g. `123/198`). Facts are not protected by copyright.
- Store the user's own photo locally in the app sandbox, plus the factual
  metadata above.

## 3. What we DO NOT do

- ❌ We do **not** bundle, ship, reproduce, or redistribute any official Pokémon
  artwork, card images, logos, or trademarked assets.
- ❌ We do **not** train or use a model on copyrighted card artwork. Any object
  detector must be trained to recognize the **generic shape of a trading card**,
  not specific creative artwork.
- ❌ We do **not** compare captured images against a database of copyrighted
  card scans.
- ❌ We do **not** use the Poké Ball mark or other trademarks in our icon,
  branding, or UI. The in-app mascot is an original design.

## 4. Pricing data

Card prices are **factual** and not copyrightable, but every price API has its
own Terms of Service. When connecting a real pricing provider:

- Use an official or public API (e.g. a licensed TCG pricing API) with a key
  where required.
- Respect rate limits and required attribution.
- Do **not** scrape sites whose ToS prohibit scraping.
- Keep API keys out of source control (use `Secrets.xcconfig` or Keychain).

See `Core/Services/PriceEstimationService.swift` for the integration point.

## 5. Trademark hygiene checklist (before release)

- [ ] App name / icon do not use "Pokémon" or trademarked logos.
- [ ] A clear "unofficial / not affiliated" disclaimer is visible in-app
      (currently on the Home screen) and in the App Store description.
- [ ] No copyrighted artwork is bundled in the app or its assets.
- [ ] Any ML model ships with documentation of its training data provenance.
- [ ] Pricing provider ToS reviewed and complied with.

## 6. User-generated content

Photos a user takes of cards they physically own are the user's own content.
We store them locally and do not redistribute them. If cloud sync is added
later, make the privacy policy explicit and keep images private to the user.
