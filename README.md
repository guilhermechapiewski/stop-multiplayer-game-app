# Stop

Stop, the classic word game, for iPhones in the same room. No internet, no accounts, no ads.

Stop (also called Adedanha or Adedonha) is coming to the App Store (name to be announced). This source is open
so that anyone can see how it works, reuse the code under the [MIT license](LICENSE), report problems, and
contribute improvements.

<img src="docs/images/screens/en-US/03-writing.jpg" alt="Everyone writing their answers for the letter of the round" width="300">

## Features

- Host a game on one iPhone; friends nearby see it and join with one tap. No codes, no accounts.
- Works on the same Wi-Fi network, or with no router at all (peer-to-peer Wi-Fi), with no internet connection.
- **Practice with bots:** a solo game on one phone against 1–5 computer players, at Relaxed, Normal or Fast
  speed. Good for learning the game, and it needs no network at all.
- Built-in categories in English and Brazilian Portuguese, plus your own custom categories (remembered for
  future games), in any order.
- A random letter every round (all 26 letters, no repeats until every letter has been used), then a 3-2-1
  countdown.
- STOP locks every phone at the same instant. The host chooses how many stops end a round, and can allow
  giving up on a hard letter.
- Score together: everyone sees all the answers, and each player scores their own (10 unique, 5 repeated,
  0 blank). The app never judges answers.
- Round results with running totals, and final standings with a celebration for the winner.
- Survives normal phone life: locking the screen, a phone call, switching apps, even the app being closed.
  Players rejoin automatically, and the answers they've typed are kept.
- Haptics, optional sounds, VoiceOver labels, Dynamic Type, Reduce Motion, dark mode.

## How to play

1. One player taps **Host a game**, picks the categories and the rules, and waits in the lobby.
2. Everyone else taps **Join a game** and picks the host's game from the list.
3. The host taps **Start**. A letter appears, then a 3-2-1 countdown.
4. Everyone fills in one word per category starting with that letter.
5. When you've filled every category, tap **STOP**. Once enough players have stopped, every phone locks.
6. Go through the categories together: each player gives their own answer 10 (nobody else wrote it),
   5 (someone else wrote the same) or 0 (blank or wrong).
7. See the round ranking and totals. The host starts the next round or ends the game.

## Requirements

- iPhone with iOS 27 or later.
- All players on the same Wi-Fi network, or near each other with Wi-Fi turned on (no network needed to be
  joined). Guest or isolated (client-isolation) networks may block it.
- Local Network permission granted (Settings > Privacy & Security > Local Network). Practice with bots works
  without it.
- To build: macOS with Xcode 27 and the iOS 27 simulator runtime.

## Building

1. Clone the repository.
2. Open `App/Stop.xcodeproj` and run the `Stop` scheme on a simulator. No signing setup is needed; use
   Practice with bots or mock mode (below) to play without a second device.

To run it on your own iPhone, copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` (git-ignored)
and set your `DEVELOPMENT_TEAM` (and a bundle identifier of your own if you like). Do this instead of picking a
team in Xcode's Signing & Capabilities, which writes the team into the public project file; the
`tools/check-signing.sh` build phase stops the build if it finds one there. Shared build settings (bundle ID,
version, deployment target, Swift settings) live in `Config/Project.xcconfig`.

## Testing

```sh
tools/test.sh            # everything: package tests, then app tests (default)
tools/test.sh package    # StopKit only: swift test --package-path Packages/StopKit (seconds, runs on the Mac)
tools/test.sh app        # app unit and UI tests: xcodebuild test on an iPhone simulator (several minutes)
```

`tools/test.sh` uses the `iPhone 17` simulator, or the first available iPhone if that isn't installed. The
package tests are where most of the logic is tested and finish quickly; the app tests build the app and drive a
whole game in the simulator with XCUITest, so they take most of the time. CI (`.github/workflows/ci.yml`) runs
both on pushes and pull requests to `main`.

Multi-iPhone behaviour (routers, locking, calls, force-quits) is checked by hand with
[`docs/device-test-checklist.md`](docs/device-test-checklist.md).

### Mock mode and launch arguments

Set these in the scheme (Product > Scheme > Edit Scheme > Run > Arguments) or pass them to `tools/run-sim.sh`:

| Argument | Effect |
|---|---|
| `-mockGame` | Starts a game against bots "Ana", "Bia" and "Caio" over an in-memory connection, with no network. The bots stop only after you do, so tests control the round. |
| `-resetState` | Wipes the on-device store at launch. |
| `-playerName <name>` | Sets the display name and skips onboarding. |
| `-uiTesting` | Clean state, no sounds, and Reduce Motion forced on (views read a custom `\.reduceMotion` value) so XCUITest never waits on looping animations. |

For example: `tools/run-sim.sh "iPhone 17" build/shot.png -mockGame -playerName Gui`.

## Architecture

| Path | Contents |
|---|---|
| `Packages/StopKit/` | Swift package with all game logic, networking and sessions; no UI code |
| `  StopCore` | Pure models and rules: players, settings, letter picker, stop rule, scoring and ranking, and the host's game engine as a reducer `(state, intent) -> (state, effects)` |
| `  StopNetworking` | `Transport` protocol; `NWTransport` (Network.framework, Bonjour `_stopgame._tcp`, peer-to-peer Wi-Fi, length-prefixed JSON frames) and an in-memory transport with fault injection |
| `  StopSession` | Host and client sessions: wire protocol, heartbeat and presence, acknowledgements and retries, reconnection, snapshot resync, persistence |
| `  StopSimulation` | Bot players and in-memory games, used by Practice with bots, mock mode and tests |
| `  StopTestSupport` | Test clock, seeded random numbers and other test helpers |
| `App/` | SwiftUI app: views, view models, localization (`Localizable.xcstrings`, en and pt-BR), haptics and sounds, on-device store |
| `Config/` | Shared build settings; your local signing settings |
| `docs/` | Website and privacy policy (GitHub Pages), device test checklist, design spec |
| `appstore/` | App Store publishing guide and screenshots |
| `tools/` | Test, simulator, screenshot and listing-check scripts |

**Host-authoritative snapshots.** The host phone runs the game engine and is also a player: its own client
talks to the engine in-process through the same interface as everyone else. Clients send intents (join, stop,
give up, answers, scores), each with an ID so retries are safe. The host validates and applies them, then sends
every client a full snapshot of the game with an increasing version number; clients ignore older snapshots.
Other players' answers are left out of snapshots until scoring starts. Typing never touches the network or the
shared game model: answers stay in the field's local state and are saved on the device in the background.

**Reconnection.** Both sides send a heartbeat every second; a player silent for 3 seconds is shown as away to
everyone. When an app goes to the background it says so right away. On return, or after a relaunch, the
client looks for the same game ID again and reconnects (after 0.25 s, 0.5 s, 1 s, then every 2 s), sending its
player ID and last snapshot version; the host replies with the current snapshot. The host saves the whole game
on every change, so if the host app is closed and reopened it restores the game and advertises it again, and
everyone rejoins. Clients save their in-progress answers per game and round, so the answers you've typed come back with you.

```
            Host iPhone                              Each player's iPhone
 +-------------------------------+            +-------------------------------+
 | SwiftUI app                   |            | SwiftUI app                   |
 |   | (in-process local client) |            |   |                           |
 | StopSession: host session     |  intents   | StopSession: client session   |
 |   StopCore game engine     <--+------------+-- answers, stops, scores      |
 |   game saved on every change  |  snapshots |   drafts saved per round      |
 |                            ---+------------+->                             |
 | StopNetworking: NWTransport   |            | StopNetworking: NWTransport   |
 +---------------+---------------+            +---------------+---------------+
                 |    TCP over Wi-Fi or peer-to-peer Wi-Fi     |
                 +---- Bonjour _stopgame._tcp, 1 s heartbeats -+
```

Practice with bots runs the same host and client code over the in-memory transport, so it never touches the
network and never shows the Local Network prompt.

## Privacy

The app collects no data. There is no analytics, advertising, tracking or crash reporting, and no third-party
code. It only talks to other iPhones in the game on your local network; names, answers and scores never leave
it. See the [privacy policy](docs/privacy/index.md).

## Contributing and feedback

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). The maintainer
reviews every pull request and decides what goes into each App Store release. Report problems in
[GitHub issues](https://github.com/guilhermechapiewski/stop-multiplayer-game-app/issues).

## License

[MIT](LICENSE).
