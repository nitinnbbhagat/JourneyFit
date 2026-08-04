# JourneyFit

JourneyFit is a private, native iPhone fitness journal built with SwiftUI. It brings together the activity you already track with Apple Health and Fitness with detailed, per-set strength-training logs you record yourself.

## What it does

- Reads daily step counts and Apple Fitness workouts through HealthKit.
- Logs strength workouts by muscle group, exercise, weight, and individual set reps.
- Supports kilograms and pounds when entering weights.
- Keeps same-day strength entries together as one editable workout.
- Shows all-time lifting trends for a selected muscle group and exercise, using total reps or weight.
- Generates a readable PDF report for any selected date range, including daily steps, Apple Fitness workouts, and JourneyFit strength logs.
- Lets you append an InBody report image unchanged to the PDF.
- Stores strength logs, saved PDFs, and imported InBody images locally, with Backup & Restore for portability.

## Privacy

JourneyFit has no account, backend, analytics service, or cloud sync. Your workout data stays on your device unless you explicitly share a generated PDF or backup file. The app reads HealthKit data only after you authorize it.

## Run on an iPhone

1. Open `FitnessJourney.xcodeproj` in Xcode 16 or later.
2. In **Signing & Capabilities**, select your Apple Developer team and use a unique bundle identifier if necessary.
3. Connect an iPhone running iOS 17 or later, choose it as the run destination, and press **Run**.
4. On first launch, authorize Health access from the dashboard.

HealthKit must be tested on a physical iPhone; the simulator does not provide real Health data.

## Technology

- SwiftUI and SwiftData
- HealthKit
- PDFKit and UIKit PDF rendering
- PhotosUI
- Swift Charts

## Before a wider release

Add production distribution, a privacy policy, App Privacy disclosures, and a data-sync strategy only if the product moves beyond private testing.
