"""Deterministic Slime Pub tavern menu, drawn from geometry and pixels.

The reference's domed slime silhouette is generated with a signed-distance-like
mask, rim and glint, following the game's code-drawn character approach. The
world pass mirrors shaders/pixel_post.gdshader: square cells, edge darkening,
YCoCg levels, and a 4x4 Bayer dither. HUD is drawn after that pass.
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


W, H = 1280, 720
ROOT = Path(__file__).resolve().parent
OUT = ROOT / "tavern_preview.png"
FONT = ROOT.parent / "tavern_upheavtt.ttf"
BARTENDER = json.loads((ROOT.parent / "godot/data/bartender.json").read_text(encoding="utf-8"))
RNG = random.Random(42)


def rgb(code: str) -> tuple[int, int, int]:
    return tuple(bytes.fromhex(code.lstrip("#")))


def shade(c: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(v * factor))) for v in c)


im = Image.new("RGB", (W, H), rgb("#281d32"))
d = ImageDraw.Draw(im)


def poly(points, fill, outline=None, width=2):
    d.polygon(points, fill=rgb(fill) if isinstance(fill, str) else fill)
    if outline:
        d.line(points + [points[0]], fill=rgb(outline) if isinstance(outline, str) else outline, width=width, joint="curve")


def rect(box, fill, outline=None, width=2, radius=0):
    color = rgb(fill) if isinstance(fill, str) else fill
    line = rgb(outline) if isinstance(outline, str) else outline
    if radius:
        d.rounded_rectangle(box, radius=radius, fill=color, outline=line, width=width)
    else:
        d.rectangle(box, fill=color, outline=line, width=width)


def ellipse(box, fill, outline=None, width=2):
    d.ellipse(box, fill=rgb(fill) if isinstance(fill, str) else fill,
              outline=rgb(outline) if isinstance(outline, str) else outline, width=width)


def line(points, fill, width=2):
    d.line(points, fill=rgb(fill) if isinstance(fill, str) else fill, width=width, joint="curve")


def glow(cx, cy, rx, ry, color, strength=0.42):
    """A soft light field before the pixel pass; not a painted texture."""
    arr = np.asarray(im).astype(np.float32).copy()
    x0, x1 = max(0, cx-rx), min(W, cx+rx)
    y0, y1 = max(0, cy-ry), min(H, cy+ry)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    v = np.maximum(0, 1 - ((xx-cx)/rx)**2 - ((yy-cy)/ry)**2)
    a = (v**2 * strength)[..., None]
    arr[y0:y1, x0:x1] = arr[y0:y1, x0:x1] * (1-a) + np.array(rgb(color)) * a
    im.paste(Image.fromarray(np.uint8(np.clip(arr, 0, 255))), (0, 0))
    global d
    d = ImageDraw.Draw(im)


def shaded_poly(points, base, vertical=0.0, horizontal=0.0, warm=0.0):
    """Fill a polygon with a directional light field, keeping pixel edges crisp."""
    global d
    mask = Image.new("L", (W, H))
    ImageDraw.Draw(mask).polygon(points, fill=255)
    yy, xx = np.mgrid[0:H, 0:W]
    x0, x1 = min(p[0] for p in points), max(p[0] for p in points)
    y0, y1 = min(p[1] for p in points), max(p[1] for p in points)
    u = np.clip((xx-x0)/max(1,x1-x0),0,1)
    v = np.clip((yy-y0)/max(1,y1-y0),0,1)
    light = 1 + vertical*(.5-v) + horizontal*(.5-u)
    c = np.array(rgb(base),dtype=np.float32)[None,None,:] * light[...,None]
    c += np.stack([warm*(1-v), warm*.48*(1-v), -warm*.35*(1-v)],axis=-1)
    arr = np.asarray(im).copy()
    arr[np.asarray(mask)>0] = np.uint8(np.clip(c,0,255)[np.asarray(mask)>0])
    im.paste(Image.fromarray(arr),(0,0))
    d = ImageDraw.Draw(im)


def bottle(x, shelf_y, w, h, c, cap="#c79755"):
    """One generated bottle, faceted like the game's geometry."""
    body = rgb(c)
    dark = shade(body, .52)
    light = shade(body, 1.35)
    neck_w = max(8, w // 3)
    nx = x + (w-neck_w)//2
    poly([(x+5,shelf_y-h+16),(x+w-5,shelf_y-h+16),(x+w,shelf_y-h+26),
          (x+w,shelf_y-3),(x,shelf_y-3),(x,shelf_y-h+26)], body, dark, 3)
    poly([(x+4,shelf_y-h+20),(x+w//3,shelf_y-h+20),(x+w//3,shelf_y-5),(x+4,shelf_y-5)], light)
    poly([(x+w*3//4,shelf_y-h+20),(x+w-4,shelf_y-h+22),(x+w-4,shelf_y-6),(x+w*3//4,shelf_y-6)], dark)
    rect((nx,shelf_y-h+3,nx+neck_w,shelf_y-h+19),c,shade(body,.58),2)
    rect((nx-2,shelf_y-h,nx+neck_w+2,shelf_y-h+5),cap)
    rect((x+w//3,shelf_y-h+30,x+w//3+3,shelf_y-h+40),shade(body,1.55))


def slime(box, radius, base):
    """A code-generated dome with the game's dark rim and pixel glint."""
    x0,y0,x1,y1 = box
    yy, xx = np.mgrid[y0:y1, x0:x1]
    cx, cy = (x0+x1)/2, (y0+y1)/2
    hx, hy = (x1-x0)/2, (y1-y0)/2
    # Reference silhouette: half-ellipse crown, near-vertical jelly sides,
    # gently pinched toward a flat base. `radius` controls the dome height.
    crown_y = y0 + radius
    row = np.clip((yy-crown_y)/radius,-1,0)
    side = hx*np.sqrt(np.maximum(0,1-row*row))
    low = yy >= crown_y
    side[low] = hx*(1-.055*(yy[low]-crown_y)/max(1,y1-crown_y))
    # A broad, nearly flat contact edge with only small rounded corners
    # matches the squat pink slime in the visual reference.
    corner = 14
    t = np.clip((yy-(y1-corner))/corner,0,1)
    side -= corner*.55*(1-np.sqrt(np.maximum(0,1-t*t)))
    nx = np.clip(np.abs(xx-cx)/hx,0,1)
    top = crown_y-radius*np.sqrt(np.maximum(0,1-nx*nx))
    margin = np.minimum.reduce([side-np.abs(xx-cx),yy-top,y1-1-yy])
    inside = margin >= 0
    arr = np.asarray(im).copy()
    part = arr[y0:y1,x0:x1].astype(np.float32)
    c = np.array(rgb(base), dtype=np.float32)
    u = (xx-cx)/hx
    v = (yy-y0)/max(1,y1-y0)
    # Rounded volume: warm lantern key from the upper left, cool window rim
    # from the right, internal gel glow and a strong contact-darkened base.
    nx = np.clip(u,-1,1)
    ny = np.clip((v-.35)*1.20,-1,1)
    nz = np.sqrt(np.maximum(.04,1-.73*nx*nx-.32*ny*ny))
    lambert = np.maximum(0, -.48*nx-.50*ny+.72*nz)
    vol = .64 + .52*lambert - .23*np.clip((v-.64)/.36,0,1)
    color = c[None,None,:]*vol[...,None]
    key_w = .27 * (104/(x1-x0))
    key_h = .16 * (85/(y1-y0))
    key_v = .23
    key_u = .38
    key = np.exp(-((u+key_u)/key_w)**2-((v-key_v)/key_h)**2)
    broad = np.exp(-((u+.31)/.56)**2-((v-.37)/.55)**2)
    color += key[...,None]*np.array([67,51,47])
    color += broad[...,None]*np.array([16,9,5])
    cool_rim = np.clip((u-.56)/.36,0,1)*(1-v*.55)
    color += cool_rim[...,None]*np.array([8,24,34])
    # A darker compressed gel lip spreads its weight onto the stool.
    band = np.clip((yy-(y1-18))/9,0,1)
    color *= (1-.17*band)[...,None]
    # The rim is shaded, not a uniform dark outline; this preserves the
    # silhouette while making the right and lower edges recede in space.
    rim = inside & (margin < 20)
    color[rim] *= (.75 + .23*np.clip(margin[rim]/20,0,1))[...,None]
    edge = inside & (margin <= 4)
    edge_color = np.array(rgb("#743249"))
    color[edge] = color[edge]*.25 + edge_color*.75
    color = np.clip(color,0,255)
    mask = inside
    part[mask] = color[mask]
    arr[y0:y1,x0:x1] = np.uint8(part)
    im.paste(Image.fromarray(arr), (0,0))
    global d
    d = ImageDraw.Draw(im)
    # pixels for the characteristic little highlight
    glint_x = x0 + int(hx * .55)
    glint_y = y0 + int(hy * .42)
    glint_color = "#f9eece"
    rect((glint_x,glint_y,glint_x+14,glint_y+8),glint_color)
    rect((glint_x-6,glint_y+8,glint_x+1,glint_y+18),glint_color)
    rect((x0+18,y0+37,x0+25,y0+54),"#251a31")
    rect((x0+48,y0+37,x0+55,y0+54),"#251a31")


def bartender(origin, scale, shapes):
    for fill, points in shapes:
        d.polygon([(round(origin[0] + x * scale), round(origin[1] + y * scale))
                   for x, y in points], fill=rgb(fill))


# ---- Geometric scene, back to front ------------------------------------------------

# wall with broad lighting bands, no bitmap texture
for y in range(0, 522):
    t=y/522
    c=(int(46+15*t),int(30+7*t),int(51+5*t))
    line([(0,y),(W,y)],c,1)
glow(750,220,530,440,"#a55b39",.33)
glow(1070,260,310,380,"#246a8f",.23)

# dark back corner and baseboard
rect((0,435,W,528),"#3b263b")
line([(0,492),(W,492)],"#6e3d4c",7)
rect((0,513,W,531),"#221a2b")

# tile floor, laid in perspective
poly([(0,518),(W,518),(W,H),(0,H)],"#453245")
for y, thick in [(538,2),(570,2),(612,3),(665,3)]:
    line([(0,y),(W,y)],"#241d30",thick)
for x in range(-100,1450,96):
    far_x = int(W*.51 + (x-W*.51)*1.55)
    line([(x,518),(far_x,H)],"#2d2435",3)
for row_y, step in [(551,95),(591,115),(637,135),(690,170)]:
    for x in range((row_y//2)%step-80,W,step):
        line([(x,row_y),(x,row_y+20)],"#312637",2)
glow(780,560,680,250,"#ac5b43",.10)

# moonlit arched window
ellipse((897,52,1211,370),"#82707d","#251d2f",9)
rect((897,211,1211,447),"#82707d","#251d2f",8)
ellipse((918,78,1190,347),"#12314b","#50394a",6)
rect((918,211,1190,422),"#12314b","#50394a",5)
# Radial joints make the arch read as individual cut stone blocks rather
# than one flat gray outline. Side stones recede against the dark glass.
for angle in (192,211,230,249,268,287,306,325,344):
    a=math.radians(angle)
    outer=(round(1054+157*math.cos(a)),round(211+159*math.sin(a)))
    inner=(round(1054+137*math.cos(a)),round(211+133*math.sin(a)))
    line([outer,inner],"#574452",3)
    line([(outer[0]-2,outer[1]-2),(inner[0]-2,inner[1]-2)],"#a58489",1)
for yy in (241,295,350,404):
    line([(899,yy),(917,yy)],"#604d59",3)
    line([(1191,yy+7),(1209,yy+7)],"#564451",3)
poly([(902,215),(910,215),(910,420),(902,420)],"#aa8a8f")
poly([(1198,213),(1207,213),(1207,422),(1198,422)],"#66515e")
glow(1090,215,170,180,"#16708b",.22)
poly([(924,368),(952,342),(970,351),(1000,318),(1024,351),(1050,335),
      (1090,371),(1130,330),(1185,367),(1185,421),(924,421)],"#18425a")
for x,y,s in [(956,158,3),(1132,218,3),(1162,184,2),(999,297,3),(1071,132,2)]:
    rect((x,y,x+s,y+s),"#b3e3dd")
ellipse((1084,143,1120,181),"#c9eee5")
ellipse((1074,134,1109,174),"#12314b")
line([(1054,83),(1054,421)],"#554151",15)
line([(918,253),(1190,253)],"#554151",14)
poly([(898,422),(1210,422),(1190,444),(907,444)],"#ad8990","#2c2432",4)
poly([(908,426),(1196,426),(1184,437),(916,437)],"#c29da1")
poly([(895,444),(1216,444),(1210,462),(899,462)],"#443046","#2a2232",3)
line([(903,447),(1208,447)],"#715563",3)

# architectural beams and square foreground language
rect((0,0,W,27),"#44273d")
rect((0,25,W,39),"#6a3c4c")
rect((0,43,W,58),"#2e2034")
for x in (39,849,1212):
    # Each column is a shallow prism, with an illuminated bevel on the left
    # and a receding side on the right. Trim pieces project toward the viewer.
    poly([(x+47,51),(x+56,58),(x+56,475),(x+47,483)],"#2d2335")
    shaded_poly([(x,48),(x+48,48),(x+48,478),(x,478)],"#59364b",vertical=.07,horizontal=.14,warm=3)
    poly([(x+1,53),(x+9,48),(x+9,474),(x+1,480)],"#815066")
    poly([(x+41,49),(x+48,49),(x+48,478),(x+41,471)],"#3c293e")
    rect((x+13,73,x+37,183),"#613a50")
    line([(x+15,75),(x+15,181)],"#8a536a",3)
    line([(x+35,74),(x+35,183)],"#442c42",3)
    rect((x+13,218,x+37,330),"#5d384d")
    line([(x+15,221),(x+15,329)],"#865167",3)
    line([(x+35,220),(x+35,328)],"#412a3f",3)
    rect((x+13,343,x+37,466),"#5b374b")
    line([(x+15,345),(x+15,466)],"#805065",3)
    line([(x+35,345),(x+35,465)],"#40293d",3)
    # Beveled capital and two collars establish consistent depth cues.
    poly([(x-6,30),(x+50,30),(x+60,42),(x+1,42)],"#946076","#39283b",3)
    poly([(x+1,42),(x+60,42),(x+58,63),(x+1,63)],"#6b4055","#342638",3)
    line([(x+6,46),(x+50,46)],"#a36a7d",3)
    poly([(x-10,184),(x+52,184),(x+65,194),(x-4,194)],"#865368","#332537",3)
    poly([(x-4,194),(x+65,194),(x+61,207),(x-5,207)],"#603b50")
    line([(x+1,198),(x+52,198)],"#a06777",2)
    poly([(x-4,207),(x+61,207),(x+57,218),(x,218)],"#3c2a3f")
    poly([(x-6,329),(x+52,329),(x+60,337),(x-2,337)],"#71475b")
    poly([(x-2,337),(x+60,337),(x+57,345),(x,345)],"#422d42")
    line([(x+2,338),(x+48,338)],"#8d5b6d",2)
    # Raised plinth catches light on top and casts a dark line on the floor.
    poly([(x-7,470),(x+51,470),(x+65,480),(x-12,480)],"#946073","#352737",3)
    poly([(x-12,480),(x+65,480),(x+62,500),(x-10,500)],"#674154","#342638",3)
    line([(x-5,485),(x+53,485)],"#a16b7b",3)
    poly([(x-16,499),(x+65,499),(x+60,510),(x-13,510)],"#39293c")
poly([(779,53),(795,53),(849,110),(849,134)],"#553449")
poly([(779,53),(787,53),(849,119),(849,127)],"#885469")
line([(795,54),(849,110)],"#342638",3)

# bottle shelves
for a,b,y in [(219,699,205),(208,392,311),(577,705,310)]:
    poly([(a,y),(b,y),(b+8,y+10),(a-5,y+10)],"#b9825a","#4a2e38",3)
    poly([(a-5,y+10),(b+8,y+10),(b+4,y+25),(a-1,y+25)],"#6a463f")
    for sx in (a+20,b-28):
        poly([(sx,y+22),(sx+15,y+22),(sx+8,y+38)],"#392835")
for x,w,h,c in [(235,22,69,"#4a918a"),(272,21,55,"#a76b53"),(311,36,77,"#d68b44"),
                (379,26,84,"#9d6595"),(421,28,77,"#69a27f"),(479,30,58,"#478fb2"),
                (580,26,84,"#519a82"),(619,26,69,"#cf8b49"),(653,24,55,"#ad628c")]:
    bottle(x,205,w,h,c)
for x,w,h,c in [(234,24,57,"#c8884c"),(273,21,46,"#946385"),(342,25,69,"#46957d"),
                (607,28,59,"#c2814e"),(659,27,64,"#458fb1")]:
    bottle(x,311,w,h,c)

# lamp and its concentrated amber pool
glow(763,180,250,230,"#e9a153",.48)
line([(766,34),(766,86)],"#241f2d",7)
for i in range(4):
    rect((759,44+i*12,773,49+i*12),"#6a5560")
poly([(739,97),(791,97),(804,114),(726,114)],"#503242","#241f2c",4)
poly([(730,115),(799,115),(790,174),(739,174)],"#d9934b","#332535",4)
poly([(747,121),(783,121),(778,171),(751,171)],"#fbd16c")
rect((756,123,772,167),"#ffe5a0")
poly([(735,173),(795,173),(802,184),(727,184)],"#49333f","#241e2e",4)

# barrel at left
ellipse((65,480,197,518),"#312435")
shaded_poly([(79,363),(175,363),(187,486),(174,499),(79,499),(68,486)],"#875641",vertical=.34,horizontal=.23,warm=9)
poly([(79,363),(98,366),(100,493),(78,499),(68,486)],"#623e3c")
poly([(156,366),(175,363),(187,486),(174,499),(156,493)],"#a36a48")
poly([(171,369),(179,375),(184,486),(175,495),(169,489)],"#6a443d")
for x0,x1 in [(103,107),(145,149)]:
    line([(x0,375),(x1,493)],"#543a3a",3)
ellipse((75,349,182,382),"#a97450","#422c36",4)
ellipse((88,354,170,372),"#4c3034","#30252f",3)
poly([(76,368),(90,376),(168,376),(181,368),(177,381),(162,385),(95,385),(79,380)],"#b37a53","#4b3038",2)
for y in (408,477):
    poly([(70,y),(86,y+4),(172,y+4),(185,y),(182,y+13),(169,y+17),(87,y+17),(72,y+13)],"#737782","#30333e",2)
    line([(87,y+5),(167,y+5)],"#a0a2a2",2)

# Contact shadow anchors the large cabinet to the tiled floor.
glow(442,581,347,64,"#1d1826",.68)

# little stool behind younger slime
ellipse((713,575,861,611),"#302334")
# Two rear legs sit in shadow, then the illuminated front legs and stretchers.
poly([(721,458),(738,457),(728,565),(713,570)],"#563439","#30242f",3)
poly([(812,451),(827,453),(836,561),(820,562)],"#60383a","#30242f",3)
shaded_poly([(741,477),(762,477),(755,589),(728,591)],"#85503e",vertical=.32,horizontal=.22,warm=17)
shaded_poly([(827,471),(846,468),(859,588),(831,590)],"#79443c",vertical=.34,horizontal=.28,warm=10)
poly([(744,481),(752,481),(745,585),(734,588)],"#c17b51")
poly([(832,474),(840,472),(848,583),(839,586)],"#ac6748")
poly([(722,522),(826,516),(830,528),(720,534)],"#56353a")
poly([(743,537),(841,531),(845,544),(739,549)],"#6a3d3c")
line([(747,537),(839,533)],"#bb7650",3)
# Wider, nearly level rear edge and a deeper visible top surface match the
# reference stool's shallow 3D perspective below the slime.
shaded_poly([(728,459),(835,459),(845,468),(739,478)],"#b56847",vertical=.28,horizontal=.08,warm=19)
poly([(735,462),(831,462),(837,468),(741,472)],"#cf8050")
poly([(739,478),(845,468),(843,484),(741,491)],"#733e3b")
line([(741,477),(843,469)],"#d88d56",3)

# The elder slime is drawn before the foreground counter, like the reference bartender.
ellipse((453,386,654,423),"#291f31")
bartender((462, 226), 1.85, BARTENDER)

# younger pink slime sitting beside the counter
ellipse((736,445,832,463),"#442337")
slime((729,373,833,458),55,"#ed5897")

# wooden counter, broad forms with squared edges
shaded_poly([(219,405),(711,411),(690,457),(164,447)],"#c89361",vertical=.28,horizontal=-.06,warm=25)
line([(219,405),(711,411)],"#604139",3)
line([(219,405),(164,447)],"#604139",3)
poly([(229,413),(696,419),(682,446),(187,436)],"#e2aa70")
line([(226,408),(701,414)],"#f9c789",3)
shaded_poly([(164,447),(690,457),(691,474),(165,464)],"#c28856",vertical=.52,horizontal=.02,warm=17)
line([(168,451),(686,461)],"#f8cb89",3)
line([(165,464),(691,474)],"#70423a",3)
shaded_poly([(165,464),(691,474),(690,565),(172,562)],"#855344",vertical=.46,horizontal=.04,warm=8)
line([(165,464),(691,474),(690,565),(172,562),(165,464)],"#332633",4)
shaded_poly([(691,474),(711,411),(716,550),(690,565)],"#5b3b3c",vertical=.26,horizontal=.34,warm=2)
line([(691,474),(711,411),(716,550),(690,565)],"#332633",3)
shaded_poly([(179,477),(682,486),(681,554),(180,552)],"#996448",vertical=.40,horizontal=.08,warm=10)
poly([(181,477),(192,478),(192,552),(181,552)],"#bc7b50")
poly([(671,486),(683,486),(681,553),(669,553)],"#75463d")
for y in (501,526,548): line([(184,y),(677,y+7)],"#774a40",4)
for x in (211,346,481,615): line([(x,482),(x,553)],"#784a40",3)
poly([(174,562),(692,565),(709,584),(190,583)],"#49313a","#2e2131",4)
poly([(412,470),(500,474),(499,553),(410,553)],"#c65f74","#6a3447",3)
poly([(420,475),(492,478),(491,535),(420,534)],"#da7580")
for x in range(422,499,12): rect((x,549,x+6,558),"#9b3c5b")

# record player and service bell on the top
# The case is a strict cuboid: top, left face and front face share corners.
poly([(292,392),(432,392),(457,408),(315,408)],"#685061","#2b2231",3)
poly([(292,392),(315,408),(315,438),(292,422)],"#3b303e","#261e2d",3)
shaded_poly([(315,408),(457,408),(457,438),(315,438)],"#493a48",vertical=.23,horizontal=.03,warm=3)
line([(315,408),(457,408),(457,438),(315,438)],"#2b2231",3)
line([(321,412),(452,412)],"#967683",2)
ellipse((329,375,420,409),"#201d2d","#876d72",4)
ellipse((339,380,411,403),"#4a233d","#1d1c2a",3)
ellipse((356,384,395,400),"#bd5a78")
ellipse((371,389,381,396),"#f2b66c")
line([(428,384),(443,386),(423,410),(405,408)],"#c9b8ac",7)
rect((435,379,453,386),"#d7c6ae")
ellipse((325,421,334,429),"#c3ada0")
ellipse((430,421,439,429),"#c3ada0")
# The counter bell has a raised brass dome, button, rolled rim and dark foot.
ellipse((208,427,273,439),"#2a1d2d","#704434",2)
ellipse((213,421,268,434),"#6b4234","#2a1e2c",2)
ellipse((215,416,266,430),"#d99a46","#68402e",2)
poly([(216,421),(216,411),(220,406),(229,402),(250,402),(259,406),
      (264,411),(264,421),(261,423),(219,423)],"#d29442","#71432d",2)
poly([(217,412),(222,406),(230,403),(231,423),(218,423)],"#ae6f33")
poly([(230,403),(247,403),(248,422),(230,422)],"#e9b65f")
poly([(249,403),(258,407),(263,412),(263,422),(249,423)],"#a96a35")
poly([(221,409),(229,404),(235,404),(232,412),(225,415),(221,415)],"#ffe1a0")
poly([(247,404),(251,405),(253,416),(249,416)],"#fff0ba")
line([(218,422),(263,422)],"#f5c779",3)
poly([(216,424),(266,424),(263,430),(218,430)],"#b97935","#56352c",2)
rect((237,394,244,401),"#c68839")
ellipse((231,386,250,399),"#d99b47","#73412d",2)
ellipse((234,388,244,393),"#ffe5a5")

# small square note and gold star tie the scene to Midi Runner's visual language
for x,y in [(630,368),(644,357),(657,368)]:
    rect((x,y,x+5,y+5),"#eab465")


def pixel_post(src: Image.Image) -> Image.Image:
    px = max(1, math.floor(H/270 + .5))  # exactly the game's scale rule: 3 at 720p
    arr = np.asarray(src, dtype=np.float32)/255
    ys = np.minimum(np.arange(math.ceil(H/px))*px + px//2,H-1)
    xs = np.minimum(np.arange(math.ceil(W/px))*px + px//2,W-1)
    c = arr[ys[:,None],xs[None,:]].copy()
    lum = lambda a: a[...,0]*.299+a[...,1]*.587+a[...,2]*.114
    y = lum(c)
    yr,yl = np.roll(y,-1,axis=1),np.roll(y,1,axis=1)
    yd,yu = np.roll(y,-1,axis=0),np.roll(y,1,axis=0)
    brighter = np.maximum.reduce([yr,yl,yd,yu])-y
    ramp_x=np.where((yr-y)*(y-yl)>0,np.minimum(abs(yr-y),abs(y-yl)),0)
    ramp_y=np.where((yd-y)*(y-yu)>0,np.minimum(abs(yd-y),abs(y-yu)),0)
    smooth=lambda a,b,v: np.clip((v-a)/(b-a),0,1)**2*(3-2*np.clip((v-a)/(b-a),0,1))
    dark=smooth(.14,.16,brighter)
    c *= (1-.4*dark)[...,None]
    c = np.clip((lum(c)[...,None]+(c-lum(c)[...,None])*1.15-.5)*1.05+.5,0,1)
    Y=c[...,0]*.25+c[...,1]*.5+c[...,2]*.25
    co=(c[...,0]-c[...,2])*.5
    cg=-c[...,0]*.25+c[...,1]*.5-c[...,2]*.25
    bayer=np.array([[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]],dtype=np.float32)
    by,bx=np.indices(Y.shape)
    th=(bayer[by%4,bx%4]+.5)/16-.5
    grad=smooth(.001,.006,np.maximum(ramp_x,ramp_y))*(1-dark)
    Y=np.floor(Y*15+.5+th*.8*grad)/15
    co=np.floor(co*64+.5)/64
    cg=np.floor(cg*64+.5)/64
    out=np.stack([Y+co-cg,Y+cg,Y-co-cg],axis=-1)
    out=np.uint8(np.clip(out,0,1)*255)
    out=np.repeat(np.repeat(out,px,axis=0),px,axis=1)[:H,:W]
    return Image.fromarray(out,"RGB")


im=pixel_post(im)
d=ImageDraw.Draw(im)

# HUD after the world post-process: nearest pixel font, shadow, readable spacing.
font=ImageFont.truetype(str(FONT),40)
small=ImageFont.truetype(str(FONT),30)


def hud_text(x,y,s,font,color="#f9e7c4",anchor=None):
    d.text((x+3,y+3),s,font=font,fill="#2a1c32",anchor=anchor,stroke_width=2,stroke_fill="#2a1c32")
    d.text((x,y),s,font=font,fill=color,anchor=anchor,stroke_width=1,stroke_fill="#4a2f40")


hud_text(128,78,"SLIME PUB",font)
poly([(423,649),(857,649),(846,697),(434,697)],"#362638","#9e6770",3)
rect((451,662,829,686),"#563447")
hud_text(640,654,"PRESS SPACE TO START",small,anchor="ma")

OUT.parent.mkdir(parents=True,exist_ok=True)
im.save(OUT,optimize=True)
print(OUT)
