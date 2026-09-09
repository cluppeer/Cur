# -*- coding: utf-8 -*-
import re
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER

F = "/usr/share/fonts/truetype/liberation/"
pdfmetrics.registerFont(TTFont("DJS", F + "LiberationSerif-Regular.ttf"))
pdfmetrics.registerFont(TTFont("DJS-B", F + "LiberationSerif-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DJS-I", F + "LiberationSerif-Italic.ttf"))
pdfmetrics.registerFontFamily("DJS", normal="DJS", bold="DJS-B", italic="DJS-I")

title_st = ParagraphStyle("t", fontName="DJS-B", fontSize=17, leading=23,
                          alignment=TA_CENTER, spaceAfter=6, textColor=colors.HexColor("#1a1a1a"))
sub_st = ParagraphStyle("s", fontName="DJS-I", fontSize=10, leading=14,
                        alignment=TA_CENTER, spaceAfter=14, textColor=colors.HexColor("#666666"))
basmala_st = ParagraphStyle("b", fontName="DJS-B", fontSize=12.5, leading=18,
                            alignment=TA_CENTER, spaceBefore=4, spaceAfter=12)
body_st = ParagraphStyle("p", fontName="DJS", fontSize=11.5, leading=18,
                         alignment=TA_JUSTIFY, spaceAfter=9, firstLineIndent=0)
note_st = ParagraphStyle("n", fontName="DJS-I", fontSize=9.5, leading=15,
                         alignment=TA_JUSTIFY, spaceAfter=9, leftIndent=10*mm,
                         rightIndent=10*mm, textColor=colors.HexColor("#444444"))
foot_h = ParagraphStyle("fh", fontName="DJS-B", fontSize=11, leading=16, spaceBefore=10, spaceAfter=5)
foot_st = ParagraphStyle("f", fontName="DJS", fontSize=9, leading=13.5,
                         alignment=TA_JUSTIFY, spaceAfter=5, textColor=colors.HexColor("#333333"))

src = open("hizbur_rizk.txt", encoding="utf-8").read()

title = ""
blocks = []          # (kind, payload)
for raw in src.split("\n"):
    line = raw.strip()
    if not line:
        continue
    if line.startswith("##TITLE##"):
        title = line[len("##TITLE##"):]
    elif line.startswith("##PAGE##"):
        blocks.append(("page", line[len("##PAGE##"):]))
    elif line.startswith("##BASMALA##"):
        blocks.append(("basmala", line[len("##BASMALA##"):]))
    else:
        blocks.append(("body", line))

OBS = {
    "1": "Kitaptaki bu bölüm fotoğrafta parmakla kısmen kapalı; okunamayan birkaç kelime var.",
    "2": "126. sayfanın son satırı ile 127. sayfanın ilk satırı arasında, cilt kıvrımı nedeniyle okunamayan kısa bir bölüm olabilir.",
}

def markup(text):
    # inline notes (parantez içi Türkçe açıklamalar) -> italik gri
    text = re.sub(r"##NOTE##(.*?)##",
                  lambda m: '<font color="#555555"><i>%s</i></font>' % m.group(1), text)
    # tekrar sayıları -> koyu
    text = re.sub(r"(\(?\s?Yâ Allâh\s?\)?\s?\[3 Kez\])", r"<b>\1</b>", text)
    text = re.sub(r"(Yâ Hayyu yâ Kayyûm \[30 Kez\])", r"<b>\1</b>", text)
    # dipnot işaretleri
    text = re.sub(r"##OBS##(\d+)##", lambda m: '<font color="#8a1c1c"><super>%s</super></font>' % m.group(1), text)
    text = text.replace("##REPEAT##", "")
    return text

story = [Paragraph(title, title_st),
         Paragraph("Kitaptan birebir transkripsiyon &#8212; orijinal sayfa 120-128", sub_st)]

for kind, payload in blocks:
    if kind == "page":
        story.append(Paragraph(
            '<font color="#8a1c1c" size="8.5">&#8212;&#8212;&#160;orijinal s. %s&#160;&#8212;&#8212;</font>' % payload,
            ParagraphStyle("pg", parent=body_st, alignment=TA_CENTER, spaceBefore=4, spaceAfter=6)))
    elif kind == "basmala":
        story.append(Paragraph(payload, basmala_st))
    else:
        story.append(Paragraph(markup(payload), body_st))

story.append(Spacer(1, 8*mm))
story.append(Paragraph("Transkripsiyon notlari".replace("notlari", "notları"), foot_h))
story.append(Paragraph('<font color="#8a1c1c"><super>1</super></font> ' + OBS["1"], foot_st))
story.append(Paragraph('<font color="#8a1c1c"><super>2</super></font> ' + OBS["2"], foot_st))
story.append(Paragraph("&#8226; Metin, gonderilen 5 fotograftaki 120-128. sayfalarin tamamini icerir. 129. sayfada baslayan &#8220;Hizbu&#8217;r-Rizk Meali&#8221; (Turkce anlam) bolumu fotografta kesik oldugu icin dahil edilmemistir; o sayfalarin fotograflari gonderilirse eklenebilir."
    .replace("gonderilen","gönderilen").replace("fotograftaki","fotoğraftaki").replace("sayfalarin","sayfaların")
    .replace("tamamini","tamamını").replace("icerir","içerir").replace("baslayan","başlayan")
    .replace("Rizk","Rızk").replace("Turkce","Türkçe").replace("bolumu","bölümü")
    .replace("fotografta","fotoğrafta").replace("oldugu","olduğu").replace("icin","için")
    .replace("edilmemistir","edilmemiştir").replace("fotograflari","fotoğrafları")
    .replace("gonderilirse","gönderilirse"), foot_st))

doc = BaseDocTemplate("Hizbur-Rizk-Turkce-Okunusu.pdf", pagesize=A4,
                      leftMargin=22*mm, rightMargin=22*mm, topMargin=20*mm, bottomMargin=20*mm,
                      title="Hizbu'r-Rızk Türkçe Okunuşu", author="", subject="Transkripsiyon")

def footer(canv, d):
    canv.saveState()
    canv.setFont("DJS", 9)
    canv.setFillColor(colors.HexColor("#777777"))
    canv.drawCentredString(A4[0]/2.0, 12*mm, "- %d -" % canv.getPageNumber())
    canv.restoreState()

frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="n")
doc.addPageTemplates([PageTemplate(id="all", frames=[frame], onPage=footer)])
doc.build(story)
print("ok")
