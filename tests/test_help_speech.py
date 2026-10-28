"""The help voice reuses cached audio rather than rerendering every visit."""

import asyncio
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from server.app.routes import help_speech


class HelpSpeechTests(unittest.IsolatedAsyncioTestCase):
    async def test_same_text_is_rendered_once(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory)
            state = SimpleNamespace(
                models_ready=True,
                audio_lock=asyncio.Lock(),
                audio_builder=SimpleNamespace(tts=object()),
            )
            request = SimpleNamespace(app=SimpleNamespace(state=state))
            rendered = []

            def render(text, destination, tts):
                rendered.append(text)
                destination.write_bytes(b"mp3")

            with patch.object(help_speech.settings, "AUDIO_DIR", audio), patch.object(
                help_speech, "_render_help", side_effect=render
            ):
                body = help_speech.HelpSpeechRequest(text="  Помощь   съёмка  ")
                first = await help_speech.speech(request, body)
                second = await help_speech.speech(request, body)
            self.assertEqual(first, second)
            self.assertEqual(rendered, ["Помощь съёмка"])
            self.assertTrue((audio / first["audio_url"].split("/")[-1]).is_file())


if __name__ == "__main__":
    unittest.main()
