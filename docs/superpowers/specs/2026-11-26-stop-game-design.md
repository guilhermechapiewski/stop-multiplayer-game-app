# Stop — Local Multiplayer iPhone Game — Design

Date: 2026-11-26
Status: Ready for approval

## 1. Intent

An iPhone app for playing **Stop** (a.k.a. Adedanha / Scattergories-style word game) with family and friends sitting in the same room. No server, no accounts: phones talk directly over the local network. The owner will play it with family and friends, publish it **free on the App Store**, and open-source it on **GitHub**. Quality bar: it must feel polished, the typing must be instant, and the connection must survive normal phone life (calls, locking the screen, switching apps) without breaking the game.

## 2. Goals, non-goals, anti-goals

**Goals**
- One player hosts, configures categories and the stop rule, others join nearby with no codes.
- Rounds: unique random letter → 3-2-1 countdown → everyone types → STOP locks everyone instantly.
- Manual self-scoring per category (10 unique / 5 repeated / 0 blank), with everyone's answers visible read-only.
- Round ranking + running totals after each round; final standings when the host ends the game.
- Seamless resilience: players leaving/returning, host leaving/returning, even an app kill, without losing answers or desyncing.
- Portuguese and English from day one.
- Heavily automated tests; the full game playable in the simulator against simulated players.

**Non-goals (v1)**
- Internet play, accounts, cloud sync, leaderboards.
- Host migration (another player taking over if the host vanishes).
- Automatic answer validation or duplicate detection — scoring is the players' call (typos/abbreviations).
- Round time limits (a round ends only via STOPs or the host forcing it).
- iPad-optimized layout, Android, chat.

**Anti-goals (failure even if it "works")**
- Any perceptible typing lag.
- Losing typed answers for any reason (backgrounding, disconnect, app killed).
- Phones disagreeing about game state (who stopped, scores, phase).
- Silent disconnects: a player vanishing without the others being told.

## 3. Constraints

- **iOS 27+ only**, iPhone, portrait. Swift 6 (strict concurrency), SwiftUI, Observation.
- **No third-party runtime dependencies.** Apple frameworks only.
- No server. Transport: **Network.framework** with Bonjour discovery and peer-to-peer Wi-Fi enabled (`includePeerToPeer = true`) so it works with or without a router.
- iOS suspends networking shortly after an app backgrounds; connections *will* drop. Design for drop + fast recovery, not for staying connected.
- Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist; users see the local-network permission prompt once. The app must handle "permission denied" with a clear explanation and a link to Settings.
- Open source: clean, documented code; MIT license (builder's call, see §11).

## 4. Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| A | **Network.framework + own session layer** (Bonjour, peer-to-peer Wi-Fi, TCP, our own heartbeat/reconnect/resync) | More code, but full control of disconnect detection, timing, and recovery; fully testable behind a protocol | **Chosen** — matches the "ultra high quality connectivity" requirement |
| B | MultipeerConnectivity | Fastest to build, but known for opaque disconnects, slow reconnection, little control. Bluetooth is mostly used for discovery only | Rejected |
| C | Both behind one interface | Doubles transport code and testing for little gain | Rejected |

## 5. Product design (decided with the owner)

### 5.1 Identity
- First launch asks for a display name (editable later in Settings). Each install has a persistent player UUID; reconnection matches by UUID, not by name.

### 5.2 Home
- Two primary actions: **Host a game** and **Join a game**. Join shows nearby games live (host name + player count), tap to join.

### 5.3 Game setup (host)
- Pick from built-in categories (localized defaults) and/or add custom ones; custom categories are remembered on the host device for future games. Any number of categories, minimum 1. Reorderable.
- **Categories are fixed for the whole game** once it starts (owner decision).
- **Stops required to end a round:** integer, minimum 1, maximum = number of players who haven't left (clamped automatically if players leave). Editable between rounds.
- **Allow giving up:** toggle (default off), editable between rounds. See §5.4.
- Lobby shows players as they join; host taps **Start** (needs ≥ 2 players including host). Host can remove a player at any time (confirm).
- Players have a **Leave game** action (confirm). See §5.7 for presence states.
- **New players can only join in the lobby.** Once the game starts it is closed to newcomers; adding someone means starting a new game (owner decision). Existing players (known UUID) can always reconnect or rejoin.

### 5.4 Round flow
1. **Letter reveal** — short animation. Letters are drawn without repetition within a game; when the set is exhausted it resets. All 26 letters A–Z are used in both languages (owner decision); if a hard letter comes up, players can all give up the round together.
2. **3-2-1 countdown**, then all fields unlock simultaneously.
3. **Writing** — single scrolling form, one field per category, keyboard stays up, Return moves to next field. Autocorrect off, auto-capitalize words. Each keystroke is local only.
4. **STOP** — big button, enabled only when every category is filled. If the host enabled "allow giving up", a secondary **Give up** button is always available and counts as a stop. Each player can stop at most once per round. **Tapping STOP or Give up immediately freezes that player's own answers** (owner decision); their answers are sent to the host right away and the screen shows "You stopped — waiting for others". Everyone sees the live count ("Stops 1/2 — Ana").
5. When the count reaches the required number, every device shows **STOP!** and locks immediately — **no grace period**. For players who hadn't stopped, the answers on their device at the moment it receives the lock are final.
6. Host has a **Force end round** action (in a menu, confirm) to unstick a round, e.g. when required stops can't be reached because players are away.

### 5.5 Scoring (manual)
- One category at a time, in setup order. Everyone sees all players' answers for that category read-only.
- Each player scores **only their own** answer: 10 / 5 / 0. A blank answer is fixed at 0. A player can change their pick until the category completes.
- Category completes when all present players have scored; then auto-advance (brief beat so people see it).
- If a player is away during scoring, the host can score on their behalf after they've been away a few seconds (host sees an "Away — score for Ana" control).
- The app never judges answers.

### 5.6 Results
- **Round results:** ranking for this round + overall totals (ties share a rank). Host chooses **Next round** or **End game**.
- **Game over:** final standings shown to everyone; celebratory moment for the winner; return to Home.

### 5.7 Presence and interruptions
- When a player leaves the app or their connection drops, everyone else gets a transient banner ("Ana left the app") and that player's chip greys out with "reconnecting…". On return: auto-rejoin, catch up to current state, banner "Ana is back".
- When the **host** leaves: everyone sees "Waiting for Gui to come back"; any countdown pauses; players may keep typing during writing. After ~2 minutes away, show "The host may be gone" with an option to leave the game.
- Typed answers are saved on-device continuously, so even an app kill loses nothing.
- **Presence states:** `present`, `away` (temporarily disconnected/backgrounded), `left` (tapped Leave game), `removed` (by host).
  - `away` players do not lower the required-stops cap; if they hold up a round the host can force-end it, and the host can score for them.
  - `left`/`removed` players stay in the standings with points so far, lower the required-stops cap if needed, and are skipped in scoring.
  - A `left` or `removed` player who rejoins (same UUID) returns with their score intact, from the next round.
- **Player whose connection dropped while the app stayed open:** they keep typing until they reconnect (accepted trade-off, rare). If they reconnect during scoring, their answers fill in only the categories not yet scored; already-scored categories count 0 for them.

## 6. Technical design

### 6.1 Module layout
Keep logic out of the app target so it's testable with fast `swift test` runs.

- **StopCore** (Swift package, pure, no I/O): models (`Player`, `GameSettings`, `Round`, `Answers`, `Scores`), rules (letter picker with injectable RNG, stop rule, scoring/ranking), and the **host game state machine** as a pure reducer: `(GameState, Intent from player) -> (GameState, [Effect])`.
- **StopNetworking** (Swift package): `Transport` protocol (advertise, browse, connect, send, receive, connection events); `NWTransport` (Network.framework); `InMemoryTransport` for tests with fault injection (drop, delay, disconnect, duplicate delivery). Wire protocol + framing.
- **StopSession** (Swift package): `HostSession` and `ClientSession` coordinators — heartbeat, presence, acknowledgements/retry, reconnection, snapshot resync, persistence hooks. Depends on StopCore + StopNetworking. Uses an injectable clock for deterministic tests.
- **App target**: SwiftUI views, view models, localization, haptics/sound, persistence implementation.

### 6.2 Authority and state sync
- Host is authoritative and is also a player (its own client talks to the host logic in-process via the same interface).
- Clients send **intents** (join, submitStop, giveUp, submitAnswers, setScore, …). Host validates, applies via the reducer, and broadcasts a **full snapshot** with a monotonically increasing `version`. Snapshots are small (tens of players × tens of categories), so full snapshots are simpler and more robust than diffs; clients ignore snapshots older than what they have.
- Snapshots never include other players' answers until the scoring phase (fairness).
- Every intent carries a client-generated ID; the host deduplicates (safe to retry after reconnect).

### 6.3 Wire protocol
- TCP over Network.framework, length-prefixed frames (custom `NWProtocolFramer` or equivalent — builder's call), Codable JSON payloads.
- Every message carries `protocolVersion`. Mismatch → friendly "Everyone needs the same app version" error.
- Bonjour service type `_stopgame._tcp`; TXT record carries host name, game ID, player count, protocol version, joinable flag.

### 6.4 Presence and reconnection
- Heartbeat both directions every 1 s; peer marked **away** after ~3 s silence.
- On scene phase going to background, the client sends a best-effort "going away" message (using a background task to flush) so others are notified immediately rather than after the timeout.
- Clients persist the current game ID and host identity; on return to foreground (or relaunch after a kill) they re-browse for that game ID and reconnect automatically with exponential backoff (fast first attempts). Reconnect handshake: player UUID + last known snapshot version → host replies with current snapshot.
- Host persists full game state on every change; if the host app is killed and relaunched, it restores the game and re-advertises the same game ID so clients rejoin.

### 6.5 Answer submission at STOP
- On receiving the lock, the client freezes its fields and sends `submitAnswers` (round ID + answers), retried until the host acks. Scoring can begin as soon as all present players' answers arrive; answers from an away player are taken on reconnect (their locally persisted answers), or treated as blank if the host proceeds without them (host gets a "Ana hasn't sent answers — continue anyway?" option).

### 6.6 Typing performance
- Each field's text lives in local view state; typing never touches the network or the shared game model.
- Persistence of in-progress answers is debounced and off the main thread.
- Views are structured so a keystroke invalidates only its own field (Observation, small subviews).
- A UI performance test guards against regressions.

### 6.7 Persistence
- Small on-device store (Codable files in Application Support, or SwiftData — builder's call): profile (UUID, name), custom categories, host game state, client in-progress answers keyed by game+round, last game reference for reconnection.

### 6.8 Localization
- String Catalog with pt-BR and en. Each device's UI follows its own language. Default categories follow the host's language; category names are shown exactly as the host configured them.

### 6.9 UX polish
- Haptics on letter reveal, countdown ticks, STOP, scoring taps. Optional sounds (toggle, off when phone is silent).
- Dynamic Type, VoiceOver labels, Reduce Motion alternatives, Dark Mode, high contrast.
- Keep the screen awake during a game (idle timer disabled while in a game).

## 7. Testing strategy
- **StopCore unit tests** (Swift Testing): letter picker (no repeats, reset on exhaustion, full A–Z), stop rule (filled vs give-up, once per player, required-count clamp), scoring and ranking with ties, full reducer phase transitions including invalid intents.
- **Session tests** with `InMemoryTransport` + test clock: full games with N simulated players; players dropping/returning in every phase; host dropping/returning; duplicate and retried intents; stale snapshots; app-kill restore from persisted state; protocol version mismatch.
- **NWTransport integration tests** on loopback (listener + connections in one process).
- **UI tests** (XCUITest): app launch argument starts a game with simulated bot players over the in-memory transport, so an entire game (setup → rounds → scoring → game over) runs in the simulator. Includes typing latency measurement.
- SwiftUI previews for every screen with mock data.
- Real-device checklist (manual, documented in repo) for multi-iPhone scenarios: router and no-router, lock/unlock, phone call, app kill.

## 8. Repository
- Git repo initialized on `main` (remote to be added by owner).
- README (what it is, how to build, how to test, architecture overview), LICENSE, `.gitignore`, real-device test checklist.
- GitHub Actions workflow running package and app tests (builder's call on runner/Xcode availability).

## 9. App Store readiness
- Free, no data collection (privacy label: no data collected), no tracking.
- Bundle ID: `com.gchapiewski.stopapp`. App name TBD by the owner (placeholder until then); app icon and launch experience to be designed.

## 10. Decided by the owner
- Approach A (Network.framework), iOS 27+ only.
- Host-authoritative state; seamless reconnection; notify others when a player leaves.
- Manual scoring, each player scores themselves, others' answers shown read-only.
- Portuguese + English.
- Host waits ~2 min then "host may be gone"; no host migration.
- Tapping STOP / Give up freezes that player's own answers.
- Categories are fixed for the whole game.
- All 26 letters in both languages.
- New players join only in the lobby; mid-game additions require a new game.
- Bundle ID `com.gchapiewski.stopapp`; app name decided later.
- Leave game action; left/removed players keep their score in standings and can rejoin; away players don't lower the stop cap.
- Disconnected-while-open players keep typing until reconnect; late answers fill only unscored categories.
- STOP requires all categories filled; "give up" counts as a stop when the host allows it (configurable).
- No grace period: STOP locks every device instantly.
- Typing must be instant; mock and automate as much as possible.
- Free App Store app, open source on GitHub.

## 11. Calls made by the designer (owner may override)
- 3-2-1 countdown; heartbeat 1 s, away after ~3 s.
- Minimum 2 players to start; host can remove players.
- Host can force-end a round and score for away players.
- Stops required and Allow giving up are editable between rounds.
- Blank answers fixed at 0.
- Autocorrect off in answer fields.
- MIT license.

## 12. Left to the builder
- Framing implementation, persistence technology, exact animation/visual design within the polish bar above, Xcode project generation approach (no third-party runtime deps), CI details.
