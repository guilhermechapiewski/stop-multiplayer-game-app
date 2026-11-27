# Device test checklist (real iPhones)

Checks that need two or more real iPhones. The simulator and the automated tests cover the game itself; this
list covers what only real radios, real interruptions and real phones show. Contributors: run the sections your
change touches and list the setups and the number of phones in your pull request.

**Record results privately.** Do not commit or post real names, Wi-Fi network names, IP addresses or device
names. In public notes, call the phones "host", "player 1", "player 2" and so on.

## Setup

- [ ] The same build installed on every phone (TestFlight, or run from Xcode).
- [ ] Each phone has a different display name; two of them share a name at least once (for example "Ana" and
      "Ana") to check the "Ana 2" suffix.
- [ ] Start clean on each phone the first time: delete the app and reinstall, so the Local Network prompt
      appears.

Run the steps under each of these setups:

- [ ] **A. Same Wi-Fi router:** every phone joined to the same (non-guest) Wi-Fi network.
- [ ] **B. No router (peer-to-peer):** Wi-Fi turned on in Control Center or Settings on every phone, but not
      joined to any network (forget it or move away from it). Mobile data off.
- [ ] Phone counts: **2 phones** (host and one player), **4 phones**, and **8 phones** (once per release is
      enough for 8).

## Steps and expected results

Run each step during a real game, starting from the lobby. "Everyone" means every other phone in the game.

### Join

- [ ] The host taps **Host a game** and opens the lobby. On every other phone, **Join a game** lists the host's
      game within a few seconds, with the host's name and the player count.
- [ ] Each player taps the game: they appear in the host's lobby and on everyone's lobby, and the count goes up.
- [ ] The host taps **Start**: every phone shows the same letter, then the same 3-2-1 countdown, and the fields
      unlock together.
- [ ] During the countdown the host taps **New letter**: every phone spins again to the same new letter (never
      the old one) and the countdown restarts; VoiceOver announces the new letter. Guests have no button.
- [ ] One player taps **STOP**: everyone sees the stop count ("Stops 1/2 — name"). When the required number is
      reached every phone shows **STOP!** and locks at the same moment.
- [ ] Scoring shows the same answers and the same points on every phone, and a player's pick shows on the
      other phones as soon as it's made. A player can change their pick after everyone has scored. Only the
      host has **Next category** (**See results** on the last); the others see "Waiting for (host) to
      continue…". Results and totals match on every phone.
- [ ] Read aloud (default): when a category opens, each phone shows only its own answer; the others show "…"
      until that player scores, then their answer and points appear on every phone at once. The host sees an
      away player's answer and scoring for them reveals it. With **Silent mode** on (setup, lobby or round
      results; the lobby shows the mode to everyone), all answers show as soon as the category opens. The ⓘ
      beside Silent mode explains both, and VoiceOver reads it.
- [ ] The host taps **Previous category** on the second category, and later **Back to scoring** on the round
      results: every phone goes back together, a player changes their pick, and after moving on again the
      round totals on every phone show the change. Guests have neither button.
- [ ] Known limit: a pick changed at the same moment the host taps **Next category** is dropped (the host has
      moved on); the player's phone then shows the host's score for that category, and results agree.

### Lock and unlock a player mid-writing

- [ ] During writing, a player types a few answers and locks their phone (side button).
- [ ] Within 3 s everyone sees the "left the app" banner and that player's chip greys out ("reconnecting…").
- [ ] The player unlocks and returns to the app: they rejoin by themselves, everyone sees "is back", and the
      answers they had typed are still in their fields.

### Incoming call on the host during the countdown

- [ ] Call the host phone (or start a FaceTime call to it) while the 3-2-1 countdown is running.
- [ ] Everyone sees "Waiting for host to come back" and the countdown pauses on every phone.
- [ ] The host ends the call and returns to the app: the countdown resumes on every phone, and writing starts
      together.

### Force-quit a player mid-writing and relaunch

- [ ] During writing, a player types some answers, then force-quits the app (swipe it away in the app switcher).
- [ ] Everyone sees that player go away within 3 s.
- [ ] The player relaunches the app: it rejoins the same game automatically and the typed answers are restored
      into the fields.

### Force-quit the host mid-scoring and relaunch

- [ ] During scoring, after at least one category has been scored, force-quit the host app.
- [ ] Everyone sees "Waiting for host to come back".
- [ ] The host relaunches the app: the game is restored and every player rejoins by themselves, on the same
      category, with the scores given so far intact.
- [ ] After about 2 minutes with the host gone (try once), players see "The host may be gone" with an option to
      leave.

### Walk out of range and back

- [ ] A player walks away (another room or floor) until the connection drops: everyone sees them as away, and
      the player sees that they're reconnecting.
- [ ] The player walks back: they rejoin by themselves and catch up to the current phase. If they come back
      during scoring, their answers fill only the categories not scored yet.

### Local Network permission denied, then granted

- [ ] On a fresh install, answer **Don't Allow** to the Local Network prompt: Host and Join show a clear
      explanation with a button that opens Settings.
- [ ] Turn Local Network on for the app in Settings > Privacy & Security > Local Network and return: hosting
      and joining work without reinstalling.

### Mismatched app versions

- [ ] Install a build with a different protocol version on one phone (an older TestFlight build, or a local
      build with the wire `protocolVersion` changed; build 3 speaks version 2, builds 1 and 2 version 1). On
      **Join a game**, the other phone's game appears dimmed and can't be joined: on the older phone with
      "Update the app to join", on the newer one with "This game uses an older version of Stop". If a phone
      does connect (for example, rejoining a saved game), it shows "Everyone needs the same version of the
      app". Neither phone crashes or gets stuck.

## Also check once per release

- [ ] One phone in English and one in Portuguese in the same game: each shows its own language; categories
      show exactly as the host set them.
- [ ] A Release build (TestFlight) has no **Practice with bots** on Home. A build run from Xcode (Debug) has
      it, and in Airplane Mode a full practice round plays with no Local Network prompt.
- [ ] VoiceOver reads a label for every control; the largest Dynamic Type size has nothing important clipped.
- [ ] Light and dark mode both look right.
