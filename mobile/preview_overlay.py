from PIL import Image, ImageDraw
path = 'assets/onboarding/popular_tasks.png'
img = Image.open(path)
w, h = img.size
kTilesStart = 0.33
kTilesEnd = 0.90
naturalH = w * (1672/941)
showHeight = int(naturalH * (kTilesEnd - kTilesStart))
subtitleMaskFrac = 0.045
rowHeightFrac = 0.245
colLeft = lambda c: int((0.045 + c * 0.245) * w)
colWidth = int(0.19 * w)
rowTop = lambda r: int((subtitleMaskFrac + r * rowHeightFrac + rowHeightFrac * 0.60) * showHeight)
rowHeight = int(rowHeightFrac * showHeight)
print('w', w, 'h', h, 'showHeight', showHeight, 'rowHeight', rowHeight, 'colWidth', colWidth)
print('boxes:')
data = [(0,0,'A'), (0,1,'B'), (0,2,'C'), (1,1,'D'), (1,3,'E')]
for r, c, t in data:
    left = colLeft(c)
    top = rowTop(r)
    right = left + colWidth
    bottom = top + int(rowHeight * 0.3)
    print(r, c, t, left, top, right, bottom)
    draw = ImageDraw.Draw(img)
    draw.rectangle([left, top, right, bottom], outline='red', width=4)
    draw.text((left, top), t, fill='red')
img.crop((0, int(naturalH * kTilesStart), w, int(naturalH * kTilesEnd))).save('assets/onboarding/preview_overlay.png')
print('saved preview_overlay.png')
