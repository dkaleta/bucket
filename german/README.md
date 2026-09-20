# German Practice

A small native macOS app for practicing spoken English-to-German translations.

## Run

1. Open `german.xcodeproj` in Xcode and run the `german` scheme on your Mac (macOS 26.2 or newer).
2. Open **Settings** with the gear button or **⌘,**. Enter your ElevenLabs and OpenAI API keys and click **Save**. Keys are stored in this Mac's Keychain; clearing a field and saving removes that key.
3. Click **Record** and allow microphone access. Say the German translation. **Reset** discards the attempt and immediately records again; **Stop** finishes transcription.
4. Correct the transcript if needed and click **Check answer**. You'll receive a score from **1 to 5 (5 is best)**, a natural German answer, and at most one important tip.
5. Use **Try again** or **Next**. The app remembers your position in the 100 sentences. After the last sentence, **Start again** returns to the beginning.

Audio goes directly to ElevenLabs Scribe v2 Realtime. Grading uses OpenAI's Responses API with `gpt-4.1-mini` and `store: false`. Your provider accounts need access and available API usage; normal provider charges and retention policies apply. The app does not save recordings or answer history locally. It assesses the transcribed translation, not pronunciation.

If microphone access was denied, enable it in **System Settings → Privacy & Security → Microphone**. A connection failure keeps available text so you can edit it or record again. The app never submits an answer for grading until you click **Check answer**.

## Development

No third-party dependencies are required. Build the app through Xcode, or:

```sh
xcodebuild -project german.xcodeproj -scheme german -configuration Debug build
swift test
```

The Swift package runs isolated tests for the practice state machine, sentence data, transcript assembly, and grading request/response handling without API keys or provider calls. Microphone capture and live provider behavior require an end-to-end check with configured keys.
