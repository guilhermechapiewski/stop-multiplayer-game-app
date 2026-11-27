# Publishing Stop to the App Store

App Store name: **Stop: Multiplayer Party Game** (28 characters). The home screen keeps the short display name **Stop!**.
`python3 tools/check_listing.py` checks every field against Apple's limits; run it after any listing edit.

## Step 1. Publish the website and privacy policy

Apple needs a privacy policy URL. The pages are in [`docs/`](../docs/) (English, plus Brazilian Portuguese
under `docs/pt/`) and are served by GitHub Pages (branch **main**, folder **/docs**), like Airplane Games'.
Every push to `main` updates them. Check that both open:
   - https://guilhermechapiewski.github.io/stop-multiplayer-game-app/
   - https://guilhermechapiewski.github.io/stop-multiplayer-game-app/privacy/

## Step 2. Signing

The team (`2JNHX2X73J`) is set on the targets in `Stop.xcodeproj`, like Airplane Games, so any Mac signed in to
your Apple account builds with no setup. Open `Stop.xcodeproj` → target **Stop** → **Signing & Capabilities**:
it should show your team, with **Automatically manage signing** on. (Xcode → **Settings** → **Accounts** must
have your Apple account.)

## Step 3. Register the bundle ID and create the app record

1. https://developer.apple.com/account/resources/identifiers/list → **+** → **App IDs** →
   **App** → Description `Stop`, **Explicit** Bundle ID:
   ```
   com.gchapiewski.stopapp
   ```
   No capabilities are needed (Bonjour and the local network need only the Info.plist keys the app already
   has) → **Continue** → **Register**. (Xcode's automatic signing may already have done this; if it's in the
   list, skip ahead.)
2. https://appstoreconnect.apple.com → **Apps** → **+** → **New App**:

   | Field | Value |
   |---|---|
   | Platforms | **iOS** |
   | Name | **Name** in [Listing — English (U.S.)](#listing--english-us) |
   | Primary Language | **English (U.S.)** |
   | Bundle ID | **com.gchapiewski.stopapp** (pick it from the list) |
   | SKU | `stop-local-multiplayer-ios` (private, any unique text) |
   | User Access | **Full Access** |

   Name: **Stop: Multiplayer Party Game**. It must not already be taken on the App Store (App Store Connect tells you when you
   click **Create**). If it is, pick a variant of at most 30 characters and update both listing sections
   below. Only the App Store name changes: the bundle ID stays the same, and the home screen shows the app's
   display name, `Stop!` (set in the project).
3. **Create**.

## Step 4. App Information and the age rating

App Store Connect → your app → **General** → **App Information**.

1. **Subtitle**: from [Listing — English (U.S.)](#listing--english-us).
2. **Category**: Primary **Games**, with subcategories **Word** and **Family**. Secondary:
   **Entertainment** (optional).
3. **Content Rights**: "No, it does not contain, show, or access third-party content." (The categories, and
   the word lists of the Debug-only practice bots, are written for the app.)
4. **Age Ratings** → **Set Up Age Ratings**. Answer every question **No** or **None**:
   - In-App Controls, Capabilities (web access, user-generated content, messaging, advertising...): all
     **No**. Answers are typed for the game and shown only to the other phones in the same room; nothing is
     published or sent through a service. (Answering **No** to user-generated content on that basis is the
     owner's call.)
   - Mature Themes, Medical, Sexuality or Nudity, Violence, Chance-Based Activities: all **None** / **No**.
   - The calculated rating should be **4+**. Don't choose **Made for Kids**: that's the Kids Category, which
     has extra rules and can't be undone.
   - **Save**.
5. **Add the Portuguese localization**: at the top right of **Localizable Information**, the language menu
   (it shows **English (U.S.)**) → **Portuguese (Brazil)**. Enter its **Name** and **Subtitle** from
   [Listing — Portuguese (Brazil)](#listing--portuguese-brazil), and the Portuguese privacy policy URL:
   `https://guilhermechapiewski.github.io/stop-multiplayer-game-app/pt/privacidade/`.
6. **Save** the page.

## Step 5. Pricing and Availability

Your app → **Monetization** → **Pricing and Availability**.

1. **Price Schedule** → **Add Pricing** → base country **United States** → **$0.00 (Free)** →
   **Next** → **Confirm**.
2. **App Availability** → **all countries and regions** → **Confirm**.
3. **Trader status (EU Digital Services Act)**: Apple asks everyone: **Business** →
   **Agreements** → **Compliance** → **Digital Services Act**. A free app published by an
   individual, not as a business, is usually **not a trader**, but the choice is your own
   assessment. A trader's address, phone and email are shown publicly on EU App Store pages.

## Step 6. App Privacy

Your app → **General** → **App Privacy**.

1. **Privacy Policy URL**:
   ```
   https://guilhermechapiewski.github.io/stop-multiplayer-game-app/privacy/
   ```
   **Save**.
2. **Data Collection** → **Get Started** → "**No, we do not collect data from this app**" →
   **Save** → **Publish**. The label then reads **Data Not Collected**. That's true: Apple counts data as
   collected when it's sent off the device to the developer or to third parties. The game's names, answers
   and scores go only to the other phones in the game over the local network (the host's name is also
   shown to nearby phones browsing for games), and nothing reaches the developer or any service.

## Step 7. Build and upload

1. `git pull`. In Xcode: scheme **Stop** → destination **Any iOS Device (arm64)**.
2. Version `1.0` (`MARKETING_VERSION`) and Build (`CURRENT_PROJECT_VERSION`) both come from
   `Config/Project.xcconfig`. Every upload needs a higher build number: bump `CURRENT_PROJECT_VERSION` in that
   file before each upload, and commit the change (it holds nothing private). The Version must match the
   version page in App Store Connect.
3. **Product → Archive** (Release configuration: no debug launch arguments, and no Practice with bots).
4. The **Organizer** opens → the archive → **Distribute App** → **App Store Connect** →
   **Distribute**.
5. After 5–30 minutes, **TestFlight** shows the build and you get an email.

## Step 8. Test it with TestFlight

You need at least 2 iPhones (more is better).

1. **TestFlight** → **+** next to **Internal Testing** → name the group → **Create** →
   **Invite Testers** → add yourself and whoever owns the other phones.
2. Install **TestFlight** from the App Store on each iPhone, accept the invite, install.
3. Check (details in [`docs/device-test-checklist.md`](../docs/device-test-checklist.md)):
   - [ ] Host on one phone and join from the other, both on the same Wi-Fi: play a round to the results.
   - [ ] Join with no router: Wi-Fi on but not joined to a network, on both phones.
   - [ ] Lock a player's phone mid-round: the host shows the "left the app" banner; unlock: it rejoins.
   - [ ] Call the host during the 3-2-1 countdown: everyone is paused; after the call, it resumes.
   - [ ] Force-quit a player, then the host, and relaunch each: the game and typed answers come back.
   - [ ] One phone in Portuguese and one in English in the same game: each shows its own language.
   - [ ] **Settings → About**: the version is right; the links open.
4. Anything wrong? Fix it before submitting.

## Step 9. The version page (1.0)

App Store Connect → your app → **iOS App 1.0** (left column). The page has its own language menu at the
top right: fill in **English (U.S.)** first, then switch to **Portuguese (Brazil)** and fill it in from its
section. Screenshots, Promotional Text, Description and Keywords are per language; the rest is shared.

1. **Screenshots** (drag them in, in this order, `01-lobby` … `07-game-over`), per language
   (`en-US` for English, `pt-BR` for Portuguese):
   - **iPhone 6.9" display** (1320 × 2868):
     [`screenshots/iphone/en-US/`](./screenshots/iphone/en-US/),
     [`screenshots/iphone/pt-BR/`](./screenshots/iphone/pt-BR/)
   - **iPhone 6.3" display** (1206 × 2622), if App Store Connect asks for it:
     [`screenshots/iphone-medium/en-US/`](./screenshots/iphone-medium/en-US/),
     [`screenshots/iphone-medium/pt-BR/`](./screenshots/iphone-medium/pt-BR/)

   The seven shots are `01-lobby`, `02-letter`, `03-writing`, `04-stop`, `05-scoring`, `06-results` and
   `07-game-over` (`.png`). App Store Connect scales them down for the other devices.
2. **Promotional Text**, **Description** and **Keywords**: from the language's listing section below.
3. **Support URL**:
   ```
   https://github.com/guilhermechapiewski/stop-multiplayer-game-app/issues
   ```
4. **Marketing URL** (for Portuguese, `…/stop-multiplayer-game-app/pt/`):
   ```
   https://guilhermechapiewski.github.io/stop-multiplayer-game-app/
   ```
5. **Version**: `1.0`. **Copyright** (Apple adds the "©"):
   ```
   2026 Guilherme Chapiewski
   ```
6. **Build** → **+** → the build you tested in step 8.
7. **App Review Information**:
   - Sign-in required: **off** (the app has no accounts).
   - Contact: your first and last name, phone with country code, and email. Typed here only.
   - **Attachment**: the screen recording from [Step 9a](#step-9a-the-screen-recording-for-app-review).
   - **Notes**: **Review Notes** in [Listing — English (U.S.)](#listing--english-us) (fill in the `[...]`
     first).
8. **Version Release**: **Manual** (you pick the launch moment after approval) or **Automatic**.
9. **Save**.

## Step 9a. The screen recording for App Review

Apple asks for one when an app needs more than one device. Record it on physical iPhones with the latest iOS,
running the TestFlight build you're submitting.

1. On each iPhone: **Settings → Control Center**: make sure **Screen Recording** is in Control Center.
2. Close the app on both phones if it's open (swipe it away in the app switcher), so the recording shows a
   real launch.
3. **Two phones.** Start screen recordings on both phones (or record phone A's screen and film phone B with a
   third device). In about 3 minutes:
   - Phone A: **Host a game** → keep the default categories → wait in the lobby.
   - Phone B: **Join a game** → tap phone A's game (allow Local Network if asked: show the prompt).
   - Phone A: **Start**. Both phones show the letter and the 3-2-1 countdown.
   - Both: write an answer in every category; tap **STOP** on both (or on one, if one stop is required).
   - Both: score each category (each phone shows everyone's points); phone A taps **Next category** after
     each one, then **See results**.
   - Lock phone B for a few seconds: phone A shows the "left the app" banner. Unlock phone B: it rejoins and
     phone A shows that it's back.
   - Phone A: **End game**; both show the final standings.
4. Stop the recordings (the red indicator at the top → **Stop**). They're saved to Photos.
5. Trim them in Photos if needed and put them together or side by side (iMovie or QuickTime), AirDrop the
   file to your Mac, and add it under **App Review Information → Attachment**. (If the file is too large,
   export it at a lower resolution.)

## Step 10. Submit

1. Top right: **Add for Review** → **Submit for Review**.
2. Review usually takes 1 to 3 days.
3. If Apple rejects it, the message is under **App Review**. Read it, fix the app or draft a
   reply, and resubmit.

## Step 11. After approval

1. **Release** it (if you chose Manual).
2. Enable Apple's "Download on the App Store" badge on the website: in `docs/index.md` and
   `docs/pt/index.md`, remove the `<!-- badge: ... -->` comment markers around the badge, replace `APPLE_ID`
   in its link with the app's Apple ID (on **App Information**, e.g. `https://apps.apple.com/app/id1234567890`),
   remove the "Coming soon to the App Store" / "Em breve na App Store" line, and update the README's first
   paragraph with the App Store name. On the Portuguese page, use Apple's pt-BR badge ("Baixar na App
   Store", from Apple's Marketing Resources) instead of `app-store-badge.svg`: add it as
   `docs/images/app-store-badge-pt-br.svg` and point the pt page's `<img>` at it, with a
   `https://apps.apple.com/br/app/id…` link. The links work once Apple releases the app.
3. **Accessibility Nutrition Labels** (optional): **App Accessibility** → **Get Started**.
   Declare only what you checked on a device (VoiceOver, Larger Text, Dark Interface, Reduced Motion...).

## Listing — English (U.S.)

**Name** (30):
```
Stop: Multiplayer Party Game
```

**Subtitle** (30):
```
Word game for friends nearby
```

**Promotional Text** (170):
```
The classic word game for iPhones in the same room. Everyone writes at once, STOP locks every phone, and you score together. No internet, no accounts, no ads.
```

**Description** (4000):
```
Stop is the classic word game (also known as Adedanha), for iPhones in the same room. Pick the categories, get a letter, and race to fill in a word for each one. The first to finish shouts STOP, and once enough players have stopped, every phone locks at once. No internet, no accounts and no ads.

HOW TO PLAY
• One player hosts a game and picks the categories: Name, Animal, Fruit, Country... or your own.
• Everyone nearby taps Join a game and picks the game. No codes to type.
• A letter appears, then a 3-2-1 countdown, and everyone writes at the same time.
• Fill in every category and tap STOP. When enough players stop, every phone locks instantly.
• Score together: everyone sees all the answers and gives their own 10 (unique), 5 (repeated) or 0, with everyone's points on every phone. When all have scored, the host moves on to the next category. The app never judges; the table decides.
• See the round ranking and running totals, and play as many rounds as you like.

MADE FOR GAME NIGHT
• Works on the same Wi-Fi, or with just Wi-Fi turned on and no network at all. No internet needed.
• Someone took a call or locked their phone? They rejoin by themselves, and the answers they've typed come back with them, even if the app was closed.
• The host decides how many stops end a round, and can let players give up on a hard letter.
• All 26 letters, with no repeats until every letter has come up.
• In English and Portuguese: each phone shows its own language in the same game.
• Built-in and custom categories (your last game's categories are ready for the next one), haptics, optional sounds, VoiceOver, larger text and dark mode.

PRIVATE BY DESIGN
No ads, no in-app purchases, no accounts, no analytics and no tracking. The app talks only to the other phones in your game on your local network; names, answers and scores never leave it. While you host, your display name is shown to nearby phones that open Join a game, so friends can find your game.

FREE AND OPEN SOURCE
Stop is completely free, with nothing to unlock. Its source code is published on GitHub under the MIT license.
```

**Keywords** (100):
```
word game,party,family,categories,stop,offline,friends,multiplayer,local,game night,letters
```

**Review Notes** (4000):
```
THIS APP NEEDS TWO IPHONES. Stop is a multiplayer game for people in the same room: each player uses their own iPhone, and the phones connect directly to each other over the local network. To review it, use two iPhones on the same Wi-Fi network, or near each other with Wi-Fi turned on (they don't need to be joined to a network). No internet connection, account or server is needed.

1. SCREEN RECORDING
Attached. Recorded on [iPhone models] running iOS [version]. It shows two iPhones playing a full round together: hosting, joining (with the Local Network prompt), the letter and countdown, writing, STOP, scoring each category and the round results, then one phone being locked to show the "left the app" banner and rejoining, and the final standings. The app has no account registration or login, no user-generated content shared beyond the room and no paid content, so there are no such flows to show.

2. PURPOSE AND AUDIENCE
Stop: Multiplayer Party Game is a free version of Stop (also called Adedanha), the classic category word game, for family and friends sitting in the same room. Each person plays on their own iPhone: a letter is drawn, everyone writes a word for each category, the first to finish calls STOP, and the players score their own answers together. It needs no internet connection, no accounts and no server; the phones talk directly to each other.

3. HOW TO USE THE APP
No login, setup or sample files are needed. On first launch, enter any display name on each iPhone.
1) iPhone A (host): tap Host a game, keep the default categories (or edit them) and tap Create game. The lobby opens.
2) iPhone B: tap Join a game and tap iPhone A's game in the list. It appears in iPhone A's lobby.
3) iPhone A: tap Start. Both phones show the letter, then a 3-2-1 countdown.
4) Both: type a word starting with that letter in every field, then tap STOP (by default one STOP ends the round). Every phone locks at once.
5) Scoring, one category at a time: both phones show everyone's answers and points. Each player taps 10, 5 or 0 for their own answer. When both have scored, iPhone A taps Next category (See results after the last one).
6) Round results: iPhone A taps Next round to play again, or End game to show the final standings on both phones.
The first time you host or join, iOS asks for Local Network permission: tap Allow on both phones. The app uses it only to find and connect to the other iPhones in the game (Bonjour on the local network). If it's denied, the app explains how to turn it on in Settings.

4. EXTERNAL SERVICES
None. The app contains no third-party SDKs and makes no internet requests: no analytics, advertising, authentication, payment, cloud or AI services. Its only network traffic is between the iPhones in a game, on the local network.

5. REGIONAL DIFFERENCES
None. The app works the same in every region. Its interface is in English and Brazilian Portuguese.

6. REGULATED INDUSTRY OR THIRD-PARTY MATERIAL
Not applicable. The app is not in a regulated industry and contains no protected third-party material. Stop is a traditional game implemented from scratch; the categories are written for the app. The source code is public under the MIT license: https://github.com/guilhermechapiewski/stop-multiplayer-game-app
```

## Listing — Portuguese (Brazil)

**Name** (30):
```
Stop: Multiplayer Party Game
```

**Subtitle** (30):
```
Adedanha com amigos por perto
```

**Promotional Text** (170):
```
O clássico jogo de palavras para iPhones na mesma sala. Todos escrevem juntos, o STOP trava todos os celulares e vocês pontuam juntos. Sem internet, contas ou anúncios.
```

**Description** (4000):
```
O Stop é o clássico jogo de palavras (também chamado de Adedanha), para iPhones na mesma sala. Escolham as categorias, recebam uma letra e corram para escrever uma palavra em cada uma. Quem terminar primeiro grita STOP, e quando jogadores suficientes dão STOP, todos os celulares travam na hora. Sem internet, sem contas e sem anúncios.

COMO JOGAR
• Um jogador cria a partida e escolhe as categorias: Nome, Animal, Fruta, País... ou as suas.
• Quem está por perto toca em Entrar em uma partida e escolhe a partida. Sem códigos para digitar.
• Aparece uma letra, depois uma contagem 3-2-1, e todo mundo escreve ao mesmo tempo.
• Preencha todas as categorias e toque em STOP. Quando jogadores suficientes dão STOP, todos os celulares travam na hora.
• Pontuem juntos: todo mundo vê todas as respostas e dá a própria nota: 10 (única), 5 (repetida) ou 0, com os pontos de todos em todos os celulares. Quando todo mundo pontuou, quem criou o jogo passa para a próxima categoria. O app nunca julga; quem decide é a turma.
• Vejam a classificação da rodada e o placar geral, e joguem quantas rodadas quiserem.

FEITO PARA REUNIR A TURMA
• Funciona no mesmo Wi-Fi, ou só com o Wi-Fi ligado e sem rede nenhuma. Não precisa de internet.
• Alguém atendeu uma ligação ou bloqueou o celular? A pessoa volta sozinha, e as respostas que ela já tinha escrito voltam junto, mesmo se o app foi fechado.
• Quem cria o jogo decide quantos STOPs encerram a rodada, e pode deixar os jogadores desistirem de uma letra difícil.
• Todas as 26 letras, sem repetir até que todas tenham saído.
• Em português e inglês: cada celular mostra o próprio idioma na mesma partida.
• Categorias prontas e personalizadas (as da última partida já ficam prontas para a próxima), vibração, sons opcionais, VoiceOver, texto maior e modo escuro.

PRIVACIDADE DE VERDADE
Sem anúncios, sem compras no app, sem contas, sem análises de uso e sem rastreamento. O app só conversa com os outros celulares da sua partida, na sua rede local; nomes, respostas e pontos nunca saem dela. Enquanto você hospeda uma partida, o seu nome aparece para os celulares por perto que abrem Entrar em um jogo, para que os amigos encontrem a sua partida.

GRÁTIS E DE CÓDIGO ABERTO
O Stop é totalmente grátis, sem nada para desbloquear. O código-fonte está publicado no GitHub sob a licença MIT.
```

**Keywords** (100):
```
adedanha,stop,jogo de palavras,família,amigos,festa,categorias,multiplayer,offline,local
```
