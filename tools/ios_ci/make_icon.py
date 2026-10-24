# Builds the iOS app icons from the player sheep (Playerwalkanim.png frame 0).
from PIL import Image
import math, sys, os
root = sys.argv[1]
sheet = Image.open(os.path.join(root, "Playerwalkanim.png")).convert("RGBA")
native = sheet.crop((0, 0, 1280, 1280)).resize((64, 64), Image.NEAREST)  # art is 20x upscaled 64px
sheep = native.crop(native.getbbox())
N = 64  # icon drawn on a 64x64 pixel grid, then 16x nearest -> 1024
bg = Image.new("RGB", (N, N))
top, bot = (40, 52, 110), (16, 18, 44)
halo = (255, 214, 120)
cx, cy = N / 2, N / 2 - 2
for y in range(N):
    t = y / (N - 1)
    base = tuple(round(top[i] * (1 - t) + bot[i] * t) for i in range(3))
    for x in range(N):
        d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
        c = base
        if d < 25:
            k = 0.82 if d < 21 else 0.45
            c = tuple(round(base[i] * (1 - k) + halo[i] * k) for i in range(3))
        bg.putpixel((x, y), c)
# ground ellipse under the sheep
w, h = sheep.size
scale = 1
ox, oy = (N - w) // 2, (N - h) // 2
canvas = bg.convert("RGBA")
canvas.alpha_composite(sheep, (ox, oy))
img = canvas.convert("RGB").resize((1024, 1024), Image.NEAREST)
out = os.path.join(root, "icons/ios")
img.save(os.path.join(out, "icon_1024.png"))
for s in (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180):
    img.resize((s, s), Image.LANCZOS).save(os.path.join(out, f"icon_{s}.png"))
img.save(sys.argv[2])
print("sheep native size", sheep.size)
