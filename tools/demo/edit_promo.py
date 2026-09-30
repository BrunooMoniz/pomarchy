#!/usr/bin/env python3
"""Monta o vídeo curto do Pomarchy OS a partir da gravação de
tools/demo/record_promo.py: cartões de abertura e de fim, legendas, câmera lenta
no efeito gênio e a trilha. Duas saídas por idioma:

  out/promo/pomarchy-os-<idioma>-16x9.mp4   (README, YouTube)
  out/promo/pomarchy-os-<idioma>-1x1.mp4    (LinkedIn: o vídeo no meio, legenda embaixo)

Trilha: "Motivating Mornings", de Ahjay Stelino, da Mixkit (licença gratuita de
música da Mixkit: uso comercial, YouTube e redes sociais, sem atribuição).

Uso: tools/demo/edit_promo.py pt|en MUSICA.mp3
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "out" / "promo"
FONTS = Path("/usr/share/fonts/noto")
BLACK, BOLD, MEDIUM = (str(FONTS / f"NotoSans-{w}.ttf") for w in ("Black", "Bold", "Medium"))
WALLPAPER = REPO / "themes/pomarchy/backgrounds/1-aurora-dia.jpg"
LOGO = REPO / "icons/pomar-settings.svg"
FPS = 30
URL = "github.com/BrunooMoniz/pomarchy"

TEXT = {
    "pt": {
        "title": ("Pomarchy OS", "O Omarchy com jeito de Mac"),
        "end": ("Pomarchy OS", "Instale com um comando. Desfaça com outro.", f"Código aberto  ·  {URL}"),
        "band": "O Omarchy com jeito de Mac",
        "scenes": {
            "dock": "Um Dock de verdade, com ampliação",
            "open": "Apps abrem com animação",
            "minimize": "Minimizar com o efeito gênio",
            "restore": "E voltar com um clique no Dock",
            "zoom": "Botões na janela: ampliar e voltar",
            "close": "Fechar, como no Mac",
            "mission": "Mission Control com três dedos",
            "spaces": "Deslize entre as mesas",
            "launchpad": "Launchpad com uma pinça",
            "switcher": "Alt+Tab entre apps",
            "dark": "Tema escuro com um clique",
            "omarchy": "Outro tema? Volta o Omarchy puro",
        },
    },
    "en": {
        "title": ("Pomarchy OS", "The Mac-style desktop for Omarchy"),
        "end": ("Pomarchy OS", "Install with one command. Undo with another.", f"Open source  ·  {URL}"),
        "band": "The Mac-style desktop for Omarchy",
        "scenes": {
            "dock": "A real Dock, with magnification",
            "open": "Apps open with a pop",
            "minimize": "Minimize with the genie effect",
            "restore": "And back with one click",
            "zoom": "Window buttons: zoom in and out",
            "close": "Close, like on a Mac",
            "mission": "Mission Control with three fingers",
            "spaces": "Swipe between desktops",
            "launchpad": "Launchpad with a pinch",
            "switcher": "Alt+Tab between apps",
            "dark": "Dark mode in one click",
            "omarchy": "Pick another theme: pure Omarchy again",
        },
    },
}

# Cena, início e fim (segundos depois da marca), e um trecho em câmera lenta
# (início, fim, velocidade) para o efeito gênio.
SCENES = [
    ("dock", 0.3, 3.9, None),
    ("open", 0.0, 3.0, None),
    ("minimize", 0.6, 3.7, (2.2, 3.1, 0.45)),
    ("restore", 0.0, 2.7, (0.8, 1.6, 0.5)),
    ("zoom", 0.5, 5.3, None),
    ("close", 0.0, 2.2, None),
    ("mission", 0.0, 5.3, None),
    ("spaces", 0.9, 3.9, None),
    ("launchpad", 0.0, 5.8, None),
    ("switcher", 0.0, 2.5, None),
    ("dark", 0.2, 5.6, None),
    ("omarchy", 0.1, 6.2, None),
]


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def ffmpeg(*args):
    run("ffmpeg", "-y", "-loglevel", "error", *args)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def pill(text, path, size=50, font=BOLD, pad=(46, 22), alpha=0.8, radius=34):
    """Legenda: texto branco numa pílula escura arredondada, com sombra."""
    with tempfile.TemporaryDirectory() as tmp:
        label = Path(tmp) / "label.png"
        run("magick", "-background", "none", "-fill", "white", "-font", font, "-pointsize", size, f"label:{text}", label)
        w, h = (int(v) for v in subprocess.run(["magick", "identify", "-format", "%w %h", str(label)],
                                                capture_output=True, text=True, check=True).stdout.split())
        W, H = w + 2 * pad[0], h + 2 * pad[1]
        run("magick", "-size", f"{W}x{H}", "xc:none", "-fill", f"rgba(14,14,18,{alpha})",
            "-draw", f"roundrectangle 0,0,{W - 1},{H - 1},{radius},{radius}", label, "-gravity", "center",
            "-composite", "(", "+clone", "-background", "black", "-shadow", "45x14+0+8", ")", "+swap",
            "-background", "none", "-layers", "merge", "+repage", path)
    return path


def card(width, height, lines, path):
    """Cartão com o papel de parede do Pomarchy desfocado, o ícone e o texto."""
    title, *rest = lines
    scale = width / 1920
    logo = int(210 * scale)
    args = ["magick", str(WALLPAPER), "-resize", f"{width}x{height}^", "-gravity", "center", "-extent",
            f"{width}x{height}", "-blur", "0x28", "-fill", "rgba(10,14,40,0.42)", "-draw",
            f"rectangle 0,0,{width},{height}",
            "(", "-background", "none", "-density", "600", str(LOGO), "-resize", f"{logo}x{logo}", ")",
            "-density", "72",  # a densidade do SVG valeria também para o tamanho do texto
            "-gravity", "center", "-geometry", f"+0-{int(170 * scale)}", "-composite",
            "-font", BLACK, "-pointsize", str(int(118 * scale)), "-fill", "white",
            "-annotate", f"+0+{int(40 * scale)}", title]
    y = 150
    for index, line in enumerate(rest):
        font, pt, color = (MEDIUM, 46, "rgba(255,255,255,0.92)") if index == 0 else (BOLD, 36, "rgba(255,255,255,0.8)")
        args += ["-font", font, "-pointsize", str(int(pt * scale)), "-fill", color,
                 "-annotate", f"+0+{int(y * scale)}", line]
        y += 70
    run(*args, path)
    return path


def card_clip(png, seconds, path, fade_in=True):
    frames = int(seconds * FPS)
    w, h = (int(v) for v in subprocess.run(["magick", "identify", "-format", "%w %h", str(png)],
                                           capture_output=True, text=True, check=True).stdout.split())
    fades = f"fade=t=out:st={seconds - 0.35}:d=0.35" + (",fade=t=in:st=0:d=0.35" if fade_in else "")
    # Um quadro só na entrada: o zoompan gera os quadros (com -loop 1 o zoom cresce sem parar).
    ffmpeg("-i", png, "-vf",
           f"zoompan=z='1+0.035*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s={w}x{h}:fps={FPS},"
           f"{fades},format=yuv420p", "-frames:v", frames, "-c:v", "libx264", "-preset", "medium", "-crf", "17", path)
    return path


def scene_clip(raw, start, end, slow, path):
    """Um trecho da gravação; o pedaço do gênio vai em câmera lenta."""
    if slow is None:
        ffmpeg("-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", raw, "-an", "-vf", f"fps={FPS},format=yuv420p",
               "-c:v", "libx264", "-preset", "medium", "-crf", "17", path)
        return path
    a, b, speed = slow
    graph = (f"[0:v]trim=start={start}:end={start + a},setpts=PTS-STARTPTS[p1];"
             f"[0:v]trim=start={start + a}:end={start + b},setpts=(PTS-STARTPTS)/{speed},"
             f"minterpolate=fps={FPS}:mi_mode=blend[p2];"
             f"[0:v]trim=start={start + b}:end={end},setpts=PTS-STARTPTS[p3];"
             f"[p1][p2][p3]concat=n=3:v=1:a=0,fps={FPS},format=yuv420p[v]")
    ffmpeg("-i", raw, "-an", "-filter_complex", graph, "-map", "[v]", "-c:v", "libx264", "-preset", "medium",
           "-crf", "17", path)
    return path


def concat(parts, path):
    """Junta recodificando: trechos com bases de tempo diferentes (cartões e
    cenas) juntados por cópia embaralham os carimbos de tempo."""
    listing = path.with_suffix(".txt")
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    ffmpeg("-f", "concat", "-safe", "0", "-i", listing, "-vf", f"fps={FPS},format=yuv420p", "-an",
           "-c:v", "libx264", "-preset", "medium", "-crf", "17", path)
    return path


def overlay_captions(base, captions, positions, path, extra_inputs=(), pre=""):
    """Põe cada legenda (PNG) no seu intervalo, com entrada e saída suaves."""
    inputs = []
    for png, _, _ in captions:
        inputs += ["-loop", "1", "-i", png]
    for extra in extra_inputs:
        inputs += ["-loop", "1", "-i", extra]
    graph = [pre or "[0:v]null[v0]"]
    last = "v0"
    for index, (png, start, end) in enumerate(captions, start=1):
        length = end - start
        graph.append(f"[{index}:v]format=rgba,trim=duration={length:.3f},"
                     f"fade=t=in:st=0:d=0.2:alpha=1,fade=t=out:st={length - 0.25:.3f}:d=0.25:alpha=1,"
                     f"setpts=PTS-STARTPTS+{start:.3f}/TB[c{index}]")
        x, y = positions
        graph.append(f"[{last}][c{index}]overlay=x={x}:y={y}:eof_action=pass:enable='between(t,{start:.3f},{end:.3f})'"
                     f"[v{index}]")
        last = f"v{index}"
    graph.append(f"[{last}]format=yuv420p[out]")
    ffmpeg("-i", base, *inputs, "-filter_complex", ";".join(graph), "-map", "[out]", "-an",
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-shortest", path)
    return path


def with_music(video, music, path):
    """Trilha cortada no tamanho do vídeo, com entrada e saída suaves e o volume
    normalizado em duas passadas (-14 LUFS, pico -1,5 dB: o alvo do YouTube e
    uma margem para as plataformas recodificarem sem estourar)."""
    total = duration(video)
    shape = (f"atrim=0:{total:.3f},afade=t=in:st=0:d=0.4,afade=t=out:st={total - 2.6:.3f}:d=2.6")
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(music), "-af",
                            f"{shape},loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                           capture_output=True, text=True, check=True).stderr
    measured = json.loads(probe[probe.rindex("{"):probe.rindex("}") + 1])
    norm = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:"
            f"measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}:"
            f"offset={measured['target_offset']}:linear=true")
    ffmpeg("-i", video, "-i", music, "-filter_complex", f"[1:a]{shape},{norm},aresample=48000[a]",
           "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
           "-movflags", "+faststart", "-shortest", path)
    return path


def main():
    lang, music = sys.argv[1], Path(sys.argv[2])
    text = TEXT[lang]
    raw = OUT / f"raw-{lang}.mp4"
    marks = {m["scene"]: m["t"] for m in json.loads((OUT / f"raw-{lang}.json").read_text())["marks"]}
    work = OUT / f"work-{lang}"
    work.mkdir(parents=True, exist_ok=True)

    # 1. Cenas, na ordem, e o intervalo de cada legenda no vídeo sem cartões.
    parts, timeline, clock = [], [], 0.0
    for index, (name, start, end, slow) in enumerate(SCENES):
        clip = scene_clip(raw, marks[name] + start, marks[name] + end, slow, work / f"scene-{index:02d}.mp4")
        length = duration(clip)
        parts.append(clip)
        timeline.append((name, clock, clock + length))
        clock += length
    scenes = concat(parts, work / "scenes.mp4")

    # 2. Cartões nos dois formatos.
    title16 = card_clip(card(1920, 1080, text["title"], work / "title16.png"), 2.8, work / "title16.mp4", False)
    end16 = card_clip(card(1920, 1080, text["end"], work / "end16.png"), 4.2, work / "end16.mp4")
    title11 = card_clip(card(1080, 1080, text["title"], work / "title11.png"), 2.8, work / "title11.mp4", False)
    end11 = card_clip(card(1080, 1080, text["end"], work / "end11.png"), 4.2, work / "end11.mp4")

    # 3. 16:9: legenda no terço de baixo, acima do Dock.
    captions16 = [(pill(text["scenes"][name], work / f"cap16-{name}.png"), a + 0.05, b - 0.05)
                  for name, a, b in timeline]
    body16 = overlay_captions(scenes, captions16, ("(W-w)/2", "H-h-150"), work / "body16.mp4")
    final16 = with_music(concat([title16, body16, end16], work / "cut16.mp4"), music,
                         OUT / f"pomarchy-os-{lang}-16x9.mp4")

    # 4. 1:1 para o LinkedIn: fundo desfocado, o vídeo no meio, título em cima e
    #    a legenda grande na faixa de baixo.
    band = pill(text["band"], work / "band11.png", size=40, font=MEDIUM, alpha=0.0, pad=(10, 6))
    captions11 = [(pill(text["scenes"][name], work / f"cap11-{name}.png", size=46), a + 0.05, b - 0.05)
                  for name, a, b in timeline]
    title_png = pill("Pomarchy OS", work / "brand11.png", size=64, font=BLACK, alpha=0.0, pad=(10, 4))
    pre = ("[0:v]split[bg][fg];"
           "[bg]scale=-2:1080,crop=1080:1080,boxblur=28:3,colorchannelmixer=rr=0.55:gg=0.55:bb=0.6[blur];"
           "[fg]scale=1080:608[small];"
           "[blur][small]overlay=0:236[mix];"
           f"[{len(captions11) + 1}:v]format=rgba[brand];[{len(captions11) + 2}:v]format=rgba[tag];"
           "[mix][brand]overlay=(W-w)/2:62:shortest=1[m1];[m1][tag]overlay=(W-w)/2:150:shortest=1[v0]")
    body11 = overlay_captions(scenes, captions11, ("(W-w)/2", "236+608+(236-h)/2"), work / "body11.mp4",
                              extra_inputs=(title_png, band), pre=pre)
    final11 = with_music(concat([title11, body11, end11], work / "cut11.mp4"), music,
                         OUT / f"pomarchy-os-{lang}-1x1.mp4")
    for path in (final16, final11):
        print(f"{path}  {duration(path):.1f} s  {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
