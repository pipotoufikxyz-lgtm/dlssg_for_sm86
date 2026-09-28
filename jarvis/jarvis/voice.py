"""Speech in (microphone -> text) and speech out (text -> speaker)."""

from __future__ import annotations


class Listener:
    """Microphone speech-to-text using the SpeechRecognition package.

    engine="google"  - free Google Web Speech API (needs internet, no key)
    engine="whisper" - offline, runs OpenAI Whisper locally (pip install openai-whisper)
    """

    def __init__(self, engine: str = "google", language: str = "en-US"):
        import speech_recognition as sr  # imported lazily so text mode needs no audio deps

        self.sr = sr
        self.engine = engine
        self.language = language
        self.recognizer = sr.Recognizer()
        self.recognizer.pause_threshold = 0.9
        self.mic = sr.Microphone()
        with self.mic as source:
            self.recognizer.adjust_for_ambient_noise(source, duration=1)

    def listen(self, timeout: float | None = None) -> str | None:
        with self.mic as source:
            try:
                audio = self.recognizer.listen(source, timeout=timeout, phrase_time_limit=30)
            except self.sr.WaitTimeoutError:
                return None
        try:
            if self.engine == "whisper":
                return self.recognizer.recognize_whisper(audio, model="base",
                                                         language=self.language.split("-")[0]).strip()
            return self.recognizer.recognize_google(audio, language=self.language).strip()
        except self.sr.UnknownValueError:
            return None
        except self.sr.RequestError as e:
            print(f"[speech recognition error: {e}]")
            return None


class Speaker:
    """Offline text-to-speech using pyttsx3 (SAPI5 on Windows, NSSpeech on macOS, eSpeak on Linux)."""

    def __init__(self, rate: int = 185, muted: bool = False):
        self.muted = muted
        self.engine = None
        if muted:
            return
        try:
            import pyttsx3

            self.engine = pyttsx3.init()
            self.engine.setProperty("rate", rate)
            # Prefer a British male voice when one is installed - it's JARVIS after all.
            for v in self.engine.getProperty("voices"):
                name = f"{v.name} {v.id}".lower()
                if any(k in name for k in ("george", "daniel", "en-gb", "english_rp", "ryan")):
                    self.engine.setProperty("voice", v.id)
                    break
        except Exception as e:  # no audio device / driver missing
            print(f"[text-to-speech unavailable: {e}]")
            self.engine = None

    def say(self, text: str) -> None:
        print(f"\nJ.A.R.V.I.S.: {text}\n")
        if self.engine and text:
            self.engine.say(text)
            self.engine.runAndWait()
