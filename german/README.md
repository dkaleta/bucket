# German Practice

A small native macOS app for practicing typed or spoken English-to-German translations.

## Run

1. Open `german.xcodeproj` in Xcode and run the `german` scheme on your Mac (macOS 26.2 or newer).
2. Open **Settings** with the gear button or **⌘,**. Enter your OpenAI API key and, if you want to record, your ElevenLabs API key, then click **Save**. Keys are stored in this Mac's Keychain; clearing a field and saving removes that key.
3. Type or paste your German translation into **Your answer**, or click **Record** and allow microphone access to say it aloud. **Reset** discards the recording attempt and immediately records again; **Stop** finishes transcription. Typing does not require ElevenLabs or microphone access.
4. Correct the transcript if needed and press **Enter** or click **Check answer**. **Shift+Enter** inserts a new line. You'll receive a score from **1 to 5 (5 is best)**, a natural German answer, and at most one important tip.
5. Use **Try again** to clear your answer and type or record a new attempt, or **Next** (also **Enter** once the grade appears) to move on. The app remembers your position in the 100 sentences. After the last sentence, **Start again** returns to the beginning.

Audio goes directly to ElevenLabs Scribe v2 Realtime. Grading uses OpenAI's Responses API with `gpt-4.1-mini` and `store: false`. Your provider accounts need access and available API usage; normal provider charges and retention policies apply. The app does not save recordings or answer history locally. It assesses the transcribed translation, not pronunciation.

Grading focuses on meaning and grammar: minor spelling mistakes with clear meaning should receive **4/5**. Capitalization and punctuation do not affect the score or feedback, whether you type or record. Feedback highlights only the most important correction.

Hover over an English word to immediately see a German vocabulary hint below the sentence. All 100 sentences have built-in, context-specific hints that work offline. Nouns include articles, verbs generally show their infinitive, and expressions such as “get up” share a phrase hint.

If microphone access was denied, enable it in **System Settings → Privacy & Security → Microphone**. A connection failure keeps available text so you can edit it or record again. The app never submits an answer for grading until you click **Check answer**.

## Development

No third-party dependencies are required. Build the app through Xcode, or:

```sh
xcodebuild -project german.xcodeproj -scheme german -configuration Debug build
swift test
```

The Swift package runs isolated tests for the practice state machine, sentence data, transcript assembly, and grading request/response handling without API keys or provider calls. Microphone capture and live provider behavior require an end-to-end check with configured keys.

The opt-in grading regression makes five real OpenAI requests using the key saved in German Practice Settings. It checks minor typos, capitalization, alternative wording, and a changed meaning:

```sh
GERMAN_LIVE_TESTS=1 swift test --filter GradingLiveTests
```

The grading prompt uses explicit score examples, following [OpenAI's guidance on examples in prompts](https://developers.openai.com/api/docs/guides/prompt-engineering#few-shot-learning).

## LangMap

Run the **LangMap** scheme for an offline, two-level German grammar map. The overview has six connected branches; zooming into a branch cross-fades into its topic names. This first version contains no lessons or third level.

- Drag or scroll to pan. Pinch or **⌘-scroll** over a branch to zoom into it. Reversing the zoom reverses the fade.
- Click or double-click a branch to fit its submap in the window. Use **German** in the breadcrumb or **Escape** to return to the saved overview position.
- **⌘+ / ⌘−** zoom at the viewport center. **⌘0** or **Reset view** fits the overview again.

The map uses SwiftUI Canvas with measured node geometry and a separate accessible interaction layer. Colors identify topic families. Navigation is Mac-first; iOS and visionOS configurations compile, but touch-specific navigation is not yet implemented. The hierarchy and layout are hardcoded; no keys or network access are needed.

```sh
xcodebuild -project german.xcodeproj -scheme LangMap -destination 'platform=macOS' test
```

Tests cover camera transforms, pointer anchoring, hit-testing, the reversible two-level transition, navigation, and window resizing. UI tests exercise branch navigation, drag/scroll panning, command-scroll zoom, and screenshots of the overview, transition, and detail view.

## KonjuGo

The **KonjuGo** scheme is a separate app for exploring German verb conjugation on Mac, iPhone, and iPad. Its existing targets require macOS/iOS 27.0.

1. Run the `KonjuGo` scheme and open the gear button. Save your OpenAI API key in Settings. KonjuGo uses its own Keychain entry, separate from German Practice.
2. Type or paste an infinitive such as `machen`, `fahren`, `aufstehen`, or `sich freuen`, then press Return or **Conjugate**.
3. Choose a form from the **Mood / tense** menu. Separators group **Indikativ** (six tenses), **Konjunktiv I** (present, past, future, future perfect), **Konjunktiv II** (synthetic present, hypothetical past, würde form, future perfect), and **Imperativ** (du, ihr, Sie).
4. Read the verb details and formation rule. The **ⓘ** button expands the rule's explanation. If conjugation depends on meaning, choose the intended meaning in the menu.

Orange marks only irregular letters/endings of the verb being studied, such as **ä** in `fährst` or **en** in `gefahren`. Regular forms of an otherwise irregular verb stay neutral. Auxiliaries and reflexive pronouns are not highlighted. VoiceOver describes the irregular changes; on Mac, hovering over a form also explains them.

**Settings → Conjugation loading** offers **On demand** (the default) and **Load everything**. On demand initially requests verb details and Präsens only. Selecting a missing mood/tense requests just that table for the selected verb meaning; switching back to a saved table works offline. Refresh regenerates the selected table without discarding the others. Load everything fetches all 15 tables together; Refresh regenerates the complete verb. Changing modes applies to subsequent lookups/refreshes. Existing complete caches remain usable in either mode.

Both modes use OpenAI (`gpt-5.6-terra`, low reasoning effort, structured output, `store: false`). Successful responses are validated and saved in Application Support under `KonjuGo/VerbCache`. Partial results accumulate per verb meaning. Failed or cancelled requests preserve saved forms, and late responses cannot overwrite a newer selection. Passive forms and the exhortative wir form are not included. Imperative tables have three addressee rows; other tables have six person rows.

The app validates table completeness, mood-specific person sets, and the presence of required separable prefixes in simple main-clause forms and principal parts. This does not guarantee the linguistic accuracy of every generated answer. Unknown words receive suggestions when available. Failed or cancelled lookups never replace newer results; a failed refresh retains the previously displayed result.

### KonjuGo validation

```sh
xcodebuild -project german.xcodeproj -scheme KonjuGo -destination 'platform=macOS' test
xcodebuild -project german.xcodeproj -scheme KonjuGo -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Unit tests cover grammar fixtures, letter annotations, structured-response validation, cache versioning, cancellation, retries, and meaning selection. UI tests use a deterministic preview provider activated by the Debug-only `--konjugo-ui-testing` launch argument; they do not read real keys or call OpenAI. Release builds exclude this provider. Live generation requires an API key and available provider usage.

Live Terra regression tests are opt-in and use the OpenAI key saved in the macOS app's Keychain. They make three real, uncached API requests (`ausweichen`, `aufstehen`, and `besuchen`) and compare all indicative persons and highlights, representative forms from every subjunctive table, and all three imperative forms against reference data. Normal test runs skip these requests. To target specific fixtures, set `TEST_RUNNER_KONJUGO_LIVE_VERBS=aufstehen,sprechen` alongside the live-test flag.

```sh
TEST_RUNNER_KONJUGO_LIVE_TESTS=1 xcodebuild -project german.xcodeproj -scheme KonjuGo -destination 'platform=macOS' -only-testing:KonjuGoTests/LiveVerbGenerationTests test
```

The offline `ausweichen` regression also checks response decoding and a disk-cache round trip: `ausgewichen` remains one word, Perfekt uses `sein`, and only the changed `i` and strong ending `en` are highlighted.

On-demand loading has separate state, cache, request/response, and live coverage. To run the focused live flow (Präsens followed by Perfekt, Imperativ, and the würde form):

```sh
TEST_RUNNER_KONJUGO_LIVE_TESTS=1 xcodebuild -project german.xcodeproj -scheme KonjuGo -destination 'platform=macOS' -only-testing:KonjuGoTests/OnDemandLiveTests test
```
