# Hello World — custom iPhone app

A real native iOS app (SwiftUI), built without a Mac.

## How this works

Windows can't compile iOS apps, and iOS won't run an app unless it's signed.
So the job is split in two:

1. **Build** — GitHub Actions runs a free macOS machine that compiles the app
   into an **unsigned** `.ipa`.
2. **Sign + install** — **Sideloadly** on your PC signs that `.ipa` with your
   own free Apple ID and installs it onto the iPhone over the USB cable.

## One-time setup

1. **Install Sideloadly** — <https://sideloadly.io> (free). Install it yourself;
   it needs Apple's drivers, which you already have.
2. **iPhone → Settings → Privacy & Security → Developer Mode → On**, then reboot.

## Each time you want the app

1. Push a change. GitHub Actions builds it automatically.
2. Open the repo on github.com → **Actions** tab → newest run → download the
   **HelloWorld-ipa** artifact → unzip it to get `HelloWorld.ipa`.
3. Open Sideloadly, plug the phone in, drag in `HelloWorld.ipa`, enter your
   Apple ID, press **Start**.
4. On the phone: **Settings → General → VPN & Device Management** → tap your
   Apple ID → **Trust**.

## Free Apple ID limits

- App **stops working after 7 days** — re-run Sideloadly to refresh it.
- Max **3 sideloaded apps** at once.
- These are Apple's limits on free accounts, not something the code controls.

## Project layout

```
Sources/HelloWorldApp.swift   app entry point
Sources/ContentView.swift     the screen (edit this to change the app)
project.yml                   XcodeGen config -> generates the Xcode project
.github/workflows/build.yml   the cloud Mac build
```
