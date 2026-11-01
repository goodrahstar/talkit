# talkit

Local speech-to-text with NVIDIA Parakeet running on Apple's Neural Engine, through [FluidAudio](https://github.com/FluidInference/FluidAudio). Nothing is sent to a server.

| Folder | What it is |
|---|---|
| `ios/` | **Talkit** for iPhone: a hold-to-talk keyboard. The app keeps Parakeet v3 and the mic ready; the keyboard types the text where your cursor is. |
| `mac/` | A local OpenAI-style transcription server on `127.0.0.1:5092` (used by FreeFlow), the `ffstt` switch command and a menu bar switch. |

## iPhone

Needs Xcode, a free Apple ID signed in under Xcode → Settings → Accounts, and the phone plugged in with Developer Mode on.

```bash
ios/install-to-iphone.sh
```

First time on the phone: Settings → General → VPN & Device Management → trust your Apple ID. Then open Talkit and tap ⓘ for the keyboard setup.

With a free Apple account the app expires after 7 days. Run the script again to renew it. A paid developer account ($99/year) makes it last a year.

To use another Apple ID, change `DEVELOPMENT_TEAM` in `ios/app/project.yml`; bundle IDs may need a unique suffix.

## Mac

```bash
mac/install.sh
```

Builds the server into `~/parakeet-server`, installs `ffstt` into `~/.local/bin`, builds the menu bar switch into `~/Applications`, and starts both with launchd. FreeFlow settings: URL `http://127.0.0.1:5092/v1`, model `parakeet-ultra` or `parakeet-v3`.

`ffstt ultra | v3 | groq | on | off | status`
