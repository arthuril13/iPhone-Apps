# iPhone-Apps

Custom native iOS apps, built without owning a Mac.

| App | What it is |
|-----|------------|
| [HelloWorld](HelloWorld) | First app — "Hello, world!" with a tap counter |

## How this works

Windows can't compile iOS apps, and iOS won't run an app unless it's signed.
So the job is split in two:

1. **Build** — GitHub Actions runs a free macOS machine that compiles the app
   into an **unsigned** `.ipa`.
2. **Sign + install** — **Sideloadly** on the PC signs that `.ipa` with your own
   free Apple ID and installs it to the iPhone over the USB cable.

## One-time setup

1. **Install Sideloadly** — <https://sideloadly.io> (free).
2. **iPhone → Settings → Privacy & Security → Developer Mode → On**, then reboot.

## Getting the app onto the phone

1. Push a change — GitHub Actions builds it automatically.
2. **Actions** tab → newest run → download the **HelloWorld-ipa** artifact →
   unzip to get `HelloWorld.ipa`.
3. Open Sideloadly, plug the phone in, drag in the `.ipa`, enter your Apple ID,
   press **Start**.
4. On the phone: **Settings → General → VPN & Device Management** → tap your
   Apple ID → **Trust**.

## Free Apple ID limits

- The app **stops working after 7 days** — re-run Sideloadly to refresh it.
- Max **3 sideloaded apps** at once.

These are Apple's limits on free accounts, not something the code controls.

## Adding another app

Create a new folder next to `HelloWorld/` with its own `project.yml` and
`Sources/`, then copy `.github/workflows/build.yml` to a new workflow file and
point its `working-directory` at the new folder.
