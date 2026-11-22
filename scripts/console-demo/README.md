# Console demo video

Records a captioned demo of the Access Canvas and its "Set up a service" wizard as an MP4 with no audio. Captions sit in a strip below the console, so they never cover it.

```sh
scripts/console-demo/run-demo.sh                  # writes ./access-canvas-demo.mp4
scripts/console-demo/run-demo.sh --dry            # screenshots per step; nothing is applied
scripts/console-demo/run-demo.sh --console DIR    # record a different console build
scripts/console-demo/run-demo.sh --keep           # leave the demo running at http://127.0.0.1:8099
```

Needs Docker, Node.js and ffmpeg. The run takes about 4 minutes. Keep the machine awake: on macOS the script uses `caffeinate`, but if the machine sleeps anyway the recording stalls.

## What it does
1. Starts a throwaway OpenZiti 2.0.8 controller and router (`zdemo-ctrl`) and an nginx serving the console (`zdemo-web`) on a `zdemo` network. The admin password is random for each run. It never touches a real controller.
2. Runs `seed.sh` inside the controller to create a small company network, with two problems planted on purpose (see the script).
3. Runs `record.js`, which logs in and works through the canvas and wizard in Playwright at 1440×900 with a visible cursor. It saves each caption's time to `captions.json`.
4. Runs `make-video.js`, which renders every caption as a 1440×84 image and stacks that track under the recording to make the 1440×984 MP4.
5. Removes the containers and network, unless `--keep` is given.

## Files
| File | Purpose |
| --- | --- |
| `run-demo.sh` | Runs everything above |
| `seed.sh` | Example network: services, identities, policies, and hosting tunnelers |
| `nginx.conf` | Serves the console and proxies `/edge` to the controller, as the deployment does |
| `record.js` | The demo script: actions, captions and timing |
| `make-video.js` | Caption strip and MP4 encoding (H.264) |

## Changing the demo
- **Steps and captions** are in `record.js`. `cap(text, holdMs)` shows a caption and then pauses, and it's the place to slow a step down.
- **Check a change** with `--dry` first, which saves a screenshot per step and doesn't apply anything.
- **Fixing a caption's wording** doesn't need a new recording. Edit `out-full/captions.json` and rerun `make-video.js`.
- **Selectors** follow the canvas markup in `moscait/ziti-console` (`.ab-*` board classes, `.ac-*` page classes), so a markup change there can break a step. Steps time out after 8 seconds rather than hanging.
