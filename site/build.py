"""Inline the design tokens, motion script and app icon into one publishable page."""
import base64, io, pathlib
from PIL import Image
here = pathlib.Path(__file__).parent
skill = pathlib.Path.home() / ".claude/skills/rahul-design-language/assets"
icon = Image.open(here.parent / "ios/app/Parakeet/Assets.xcassets/AppIcon.appiconset/icon.png").resize((128, 128), Image.LANCZOS)
buf = io.BytesIO(); icon.save(buf, "PNG", optimize=True)
page = (here / "src.html").read_text()
page = page.replace("{{TOKENS}}", (skill / "tokens.css").read_text())
page = page.replace("{{MOTION}}", (skill / "motion.js").read_text())
page = page.replace("{{ICON}}", "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode())
(here / "index.html").write_text(page)
print("index.html", len(page), "bytes")
