"""Original M5LEE radio-link artwork. Requires Pillow; no external artwork/fonts."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import math
OUT=Path(__file__).resolve().parents[1]/'assets'
SIZES=[16,20,24,32,48,64,128,256]
NAVY='#10233D';CYAN='#36DBE7';GOLD='#FFBC53';WHITE='#F4F9FF'
def create(kind):
 scale=4;im=Image.new('RGBA',(1024,1024));d=ImageDraw.Draw(im)
 def xy(p):return tuple(round(x*scale) for x in p)
 def line(points,fill,width):
  points=[xy(p) for p in points];d.line(points,fill=fill,width=round(width*scale),joint='curve')
  r=width*scale/2
  for x,y in [points[0],points[-1]]:d.ellipse((x-r,y-r,x+r,y+r),fill=fill)
 d.rounded_rectangle(xy((8,8,248,248)),radius=52*scale,fill=NAVY)
 d.rounded_rectangle(xy((12,12,244,244)),radius=48*scale,outline='#243D5B',width=2*scale)
 # The arch links two radio terminals. Keep the silhouette legible at 16 px.
 points=[]
 for n in range(101):
  t=n/100;u=1-t
  points.append((u**3*66+3*u*u*t*66+3*u*t*t*190+t**3*190,u**3*145+3*u*u*t*65+3*u*t*t*65+t**3*145))
 line(points,WHITE,16)
 line([(66,140),(66,170)],CYAN,16);line([(190,140),(190,170)],GOLD,16)
 for x,color in [(66,CYAN),(190,GOLD)]:d.ellipse(xy((x-17,163,x+17,197)),fill=color)
 line([(97,211),(159,211)],'#6B87A5',8)
 line([(97,211),(107,201)],'#6B87A5',8);line([(159,211),(149,221)],'#6B87A5',8)
 # Compact RF crest, original geometry rather than a vendor mark.
 d.arc(xy((106,44,150,82)),205,335,fill=CYAN,width=6*scale)
 d.ellipse(xy((124,70,132,78)),fill=CYAN)
 if kind!='bridge':
  # A dark separation ring keeps the overlay clear on every desktop colour.
  d.ellipse(xy((151,150,251,250)),fill=NAVY)
  if kind=='settings':
   points=[]
   for n in range(64):
    a=math.tau*n/64;r=43 if n%8 in (0,1,6,7) else 35
    points.append(xy((201+math.cos(a)*r,200+math.sin(a)*r)))
   d.polygon(points,fill=GOLD);d.ellipse(xy((184,183,218,217)),fill=NAVY);d.ellipse(xy((195,194,207,206)),fill=WHITE)
  else:
   d.ellipse(xy((158,157,244,243)),fill=CYAN)
   line([(201,174),(201,211)],NAVY,11);line([(185,199),(201,215),(217,199)],NAVY,11)
 return im.resize((512,512),Image.Resampling.LANCZOS)
def svg(kind):
 badge=''
 if kind=='settings':
  teeth=''.join(f'<rect x="194" y="155" width="14" height="25" rx="3" transform="rotate({a} 201 200)"/>' for a in range(0,360,45))
  badge=f'<circle cx="201" cy="200" r="50" fill="{NAVY}"/><g fill="{GOLD}">{teeth}<circle cx="201" cy="200" r="35"/></g><circle cx="201" cy="200" r="17" fill="{NAVY}"/><circle cx="201" cy="200" r="6" fill="{WHITE}"/>'
 if kind=='setup':badge=f'<circle cx="201" cy="200" r="50" fill="{NAVY}"/><circle cx="201" cy="200" r="43" fill="{CYAN}"/><path d="M201 174V211M185 199L201 215L217 199" stroke="{NAVY}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'
 return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-label="M5LEE radio link {kind}">
<!-- Copyright (c) 2026 M5LEE. Original artwork. No vendor logos. -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<rect x="8" y="8" width="240" height="240" rx="52" fill="{NAVY}"/>
<rect x="12" y="12" width="232" height="232" rx="48" fill="none" stroke="#243D5B" stroke-width="2"/>
<path d="M66 145C66 65 190 65 190 145" stroke="{WHITE}" stroke-width="16" fill="none" stroke-linecap="round"/>
<path d="M66 140V170" stroke="{CYAN}" stroke-width="16" stroke-linecap="round"/><path d="M190 140V170" stroke="{GOLD}" stroke-width="16" stroke-linecap="round"/>
<circle cx="66" cy="180" r="17" fill="{CYAN}"/><circle cx="190" cy="180" r="17" fill="{GOLD}"/>
<path d="M97 211H159M97 211L107 201M159 211L149 221" fill="none" stroke="#6B87A5" stroke-width="8" stroke-linecap="round"/>
<path d="M110 62Q128 42 146 62" fill="none" stroke="{CYAN}" stroke-width="6"/><circle cx="128" cy="74" r="4" fill="{CYAN}"/>{badge}</svg>'''
def main():
 OUT.mkdir(exist_ok=True)
 for kind in ['bridge','settings','setup']:
  image=create(kind);image.save(OUT/(kind+'.png'))
  frames=[]
  for size in SIZES:
   frame=image.resize((size,size),Image.Resampling.LANCZOS)
   frame.putalpha(frame.getchannel('A').point([0 if a<4 else a for a in range(256)]));frames.append(frame)
  frames[-1].save(OUT/(kind+'.ico'),format='ICO',bitmap_format='bmp',sizes=[(n,n) for n in SIZES],append_images=frames[:-1]);(OUT/(kind+'.svg')).write_text(svg(kind))
 preview=Image.new('RGB',(960,390),'#F3F6FA');draw=ImageDraw.Draw(preview);font=ImageFont.load_default(size=20);small=ImageFont.load_default(size=15)
 for i,(kind,label) in enumerate([('bridge','Bridge launcher'),('settings','Configuration'),('setup','Installer')]):
  icon=create(kind).resize((208,208),Image.Resampling.LANCZOS);preview.paste(icon,(56+i*310,28),icon)
  draw.text((56+i*310,247),label,font=font,fill=NAVY)
  for j,size in enumerate([16,24,32,48]):
   icon=create(kind).resize((size,size),Image.Resampling.LANCZOS);preview.paste(icon,(56+i*310+j*56,286),icon)
 draw.text((56,356),'Original artwork by M5LEE | Cyan + amber radio link | No third-party logos',font=small,fill='#45607D')
 preview.save(OUT/'icon-preview.png')
 print('Created three original icon sets, each with eight Windows resolutions, plus PNG/SVG artwork.')
if __name__=='__main__':main()
