# German Practice

A small native macOS app for practicing typed or spoken English-to-German translations.

## Run

1. Open `german.xcodeproj` in Xcode and run the `german` scheme on your Mac (macOS 26.2 or newer).
2. Open **Settings** with the gear button or **⌘,**. Enter your OpenAI API key and, if you want to record, your ElevenLabs API key, then click **Save**. Keys are stored in this Mac's Keychain; clearing a field and saving removes that key. Main practice needs the OpenAI key to prepare its first batch.
3. Type or paste your German translation into **Your answer**, or click **Record** and allow microphone access to say it aloud. **Reset** discards the recording attempt and immediately records again; **Stop** finishes transcription. Typing does not require ElevenLabs or microphone access.
4. Correct the transcript if needed and press **Enter** or click **Check answer**. **Shift+Enter** inserts a new line. You'll receive a score from **1 to 5 (5 is best)**, a natural German answer, and at most one important tip.
5. Use **Try again** to clear your answer and type or record a new attempt, or **Next** (also **Enter** once the grade appears) to move on. The app remembers your current batch and answer. After question 10, **Next 10 questions** prepares a fresh batch.

Audio goes directly to ElevenLabs Scribe v2 Realtime. Grading uses OpenAI's Responses API with `gpt-6.1-sol`, Ultrafast processing (`service_tier: "ultrafast"`), low reasoning effort, and `store: false`. Your provider accounts need access and available API usage; Ultrafast pricing and normal provider retention policies apply. The app saves active lessons, their positions, and current answers and feedback locally in Application Support under `GermanPractice/session.json`. It does not save audio or a completed-answer history. It assesses the transcribed translation, not pronunciation.

Grading focuses on meaning and grammar: minor spelling mistakes with clear meaning should receive **4/5**. Capitalization and punctuation do not affect the score or feedback, whether you type or record. Feedback highlights only the most important correction.

After grading, click the speaker beside the corrected German answer to hear it using ElevenLabs Flash v2.5 (`eleven_flash_v2_5`, German language code `de`). This uses your saved ElevenLabs key and generates speech only when clicked. Click again to cancel generation or stop playback. Replays of the current answer reuse audio in memory; moving to another question discards it. No generated audio is saved to disk. [ElevenLabs speech API](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).

Click **Ask tutor** to start a spoken conversation about the current exercise. The tutor receives the question, reference translation, lesson tags, your answer, and any score and feedback. Ask follow-up questions in English or German. Replies play aloud and both speakers have captions. You can interrupt by speaking while the tutor talks; **Mute** stops outgoing microphone audio, and **End conversation** / **Close** stops the microphone and playback. Exercise progress and grades stay unchanged.

The tutor uses [GPT-Live](https://developers.openai.com/api/docs/guides/live) (`gpt-live-1`, Marin voice) over **WebRTC**, with `POST /v1/live/sessions`. It uses your saved OpenAI key and needs GPT-Live access. The native app creates the session; the key never enters the embedded audio document. WebKit handles microphone capture, echo cancellation, automatic gain, and playback. The microphone stays active while the tutor speaks. More involved grammar questions can use OpenAI-managed Responses delegation to `gpt-6.1-sol` with low reasoning effort. Grading, question generation, and ElevenLabs pronunciation playback keep their existing models.

The selected Settings microphone is matched to the WebRTC input. The panel shows input/output names, microphone activity, and reply audio status. **Test speaker** plays a local chime on the system output. Captions preserve separate speaker timelines during overlapping speech. Closing stops local media immediately and requests graceful session finalization. The session uses `store: false`; audio and captions are not saved locally. Provider voice-duration and delegated-model usage charges apply.


Hover over an English word to immediately see a German vocabulary hint below the sentence. Generated questions include context-specific hints that remain available offline once the batch is saved. Nouns include articles, verbs generally show their infinitive, and expressions such as “get up” share a phrase hint.

Every question has topic and grammar tags. Click a tag or **Custom lesson…** to generate a focused lesson using GPT-6.1 Sol with Ultrafast and low reasoning effort. For custom lessons, describe what you want—for example, “More questions like this about zu/zum”. The generator receives the current English prompt, reference German, tags, your answer, and any grading feedback to resolve references to the current example. **Settings → Practice lessons** selects 5, 10 (default), or 20 questions for new lessons. Generated questions match the source question’s difficulty and include word hints. Provider usage charges apply.

Tags inside a lesson can open another lesson. The breadcrumb shows your path; **Return to …** restores the interrupted question, answer, and feedback. The final question’s return button finishes the lesson; you can also return early. Main practice generates mixed beginner batches of exactly 10 questions. After the last grade, **Next 10 questions** prepares another set. Main practice excludes the original 100 prompts and the most recent 200 generated prompts from main batches and focused lessons, saved locally for duplicate avoidance. The focused-lesson size setting does not affect main batches.

**Reload**, beside the question counter, replaces the current set with fresh questions and starts at 1. In a focused lesson it keeps the topic, question count, and saved parent lesson. Custom lessons also keep your original description and exercise context across reloads and app restarts. The current set and answer stay intact if generation fails or is cancelled. Reopening the app resumes saved questions; it does not reload them automatically.

Active nested lessons resume after reopening the app without regeneration. Generation errors and cancellation preserve the original question.

If microphone access was denied, enable it in **System Settings → Privacy & Security → Microphone**. A connection failure keeps available text so you can edit it or record again. The app never submits an answer for grading until you click **Check answer**.

**Settings → Microphone test** provides a separate local capture check. Choose a **Microphone**, click **Record 7-second test**, speak, then use **Play recording**. The live meter and elapsed audio duration distinguish missing audio from silent audio. You can stop early or refresh the device list to compare another microphone. Permission status and a shortcut to microphone permissions are shown in the same section. This test checks the selected microphone through native capture; the tutor uses WebRTC echo-cancelled capture of that same device. It makes no API calls and needs no API keys. Starting it stops any active tutor or answer recording. The clip stays in memory and is discarded on closing Settings, changing the test input, or starting another test. The selected microphone is saved and used by new tutor conversations too; macOS system input settings are unchanged.

## Development

No third-party dependencies are required. Build the app through Xcode, or:

```sh
xcodebuild -project german.xcodeproj -scheme german -configuration Debug build
swift test
```

The Swift package runs isolated tests for the practice state machine, sentence data, transcript assembly, grading, and voice tutor context, streaming, interruptions, and cleanup without API keys or provider calls. Microphone capture and live provider behavior require an end-to-end check with configured keys.

A Debug build launched with `--lesson-preview` uses isolated local lesson and grading fixtures for UI checks, without reading API keys or saving user progress.

For an opt-in hardware check, launch a Debug build with `--tutor-audio-check` after granting microphone permission to the app. It captures and discards two seconds of microphone input, plays a silent buffer through the tutor's output path, and reports whether both worked. It makes no network requests, reads no keys, and saves no audio or practice state. This exercises the shared microphone capture and separate reply playback engine.

The opt-in Realtime regression sends a locally synthesized test question using the saved OpenAI key and checks server speech detection, transcription, and returned speech. It uses no microphone and incurs normal API usage:

```sh
say -v Samantha -o /tmp/german-voice-question.aiff 'How do I say I am closing the window in German?'
GERMAN_VOICE_LIVE_TESTS=1 GERMAN_VOICE_FIXTURE=/tmp/german-voice-question.aiff swift test --filter VoiceTutorLiveTests
```

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

For an opt-in GPT-Live WebRTC smoke check, build the Debug app and launch its executable with `--gpt-live-check` and `GERMAN_LIVE_FIXTURE_BASE64` containing base64-encoded synthesized audio (AAC keeps the environment small). WebKit briefly opens and stops local microphone capture to authorize network candidates; only the synthetic track is sent to OpenAI. This uses the saved key and incurs provider usage. The check requires input captions, output captions, and non-silent incoming media. To test spoken interruption, also set `GERMAN_LIVE_INTERRUPT_BASE64` to synthesized “Stop. Just say Guten Morgen.” It injects that phrase while reply audio is active and verifies that Live follows the new request. A successful media check does not establish physical speaker audibility. The older `GERMAN_VOICE_LIVE_TESTS` check covers the legacy Realtime adapter only, not the active tutor.
