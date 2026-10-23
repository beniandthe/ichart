#!/usr/bin/env python3
"""Create self-authored, genuine PDF pages for the offline import proof.

Requires reportlab. Run from the repository root; no app or customer data is read.
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas


OUTPUT = Path(__file__).resolve().parents[1] / "output/pdf/ichart-pdf-import-offline-proof.pdf"
PAGES = (
    ("FIRST HALF", ("Cmaj7", "Am7", "Dm7", "G7", "Cmaj7", "A7", "Dm7", "G7")),
    ("SECOND HALF", ("F#m7b5", "B7", "Em7", "A7", "Dm7", "G7", "C6", "C6")),
)


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(OUTPUT), pagesize=letter, invariant=True)
    pdf.setTitle("PDF Import Offline Proof")
    pdf.setAuthor("iChart QA - self-authored test material")
    width, height = letter
    margin = 44
    blue = colors.HexColor("#164C77")
    gray = colors.HexColor("#53616D")
    for page_index, (section, chords) in enumerate(PAGES, start=1):
        pdf.setFillColor(blue)
        pdf.setFont("Helvetica-Bold", 25)
        pdf.drawString(margin, height - 64, "PDF Import Offline Proof")
        pdf.setFillColor(gray)
        pdf.setFont("Helvetica", 12)
        pdf.drawString(margin, height - 87, f"4/4  |  {section}  |  Page {page_index} of 2")
        pdf.setStrokeColor(blue)
        pdf.setLineWidth(2)
        pdf.line(margin, height - 105, width - margin, height - 105)

        top = height - 165
        cell_width = (width - 2 * margin) / 4
        cell_height = 112
        for row in range(2):
            y = top - row * cell_height
            pdf.setStrokeColor(colors.HexColor("#A8B7C5"))
            pdf.setLineWidth(0.8)
            pdf.rect(margin, y - cell_height, width - 2 * margin, cell_height)
            for column in range(4):
                x = margin + column * cell_width
                if column:
                    pdf.line(x, y, x, y - cell_height)
                measure = (page_index - 1) * 8 + row * 4 + column + 1
                pdf.setFillColor(gray)
                pdf.setFont("Helvetica", 10)
                pdf.drawString(x + 10, y - 20, str(measure))
                pdf.setFillColor(colors.black)
                chord = chords[row * 4 + column]
                pdf.setFont("Helvetica-Bold", 22 if len(chord) > 5 else 26)
                pdf.drawCentredString(x + cell_width / 2, y - 67, chord)

        pdf.setFillColor(blue)
        pdf.setFont("Helvetica-Bold", 15)
        pdf.drawString(margin, 300, f"OFFLINE CHECK {page_index}/2")
        pdf.setFillColor(gray)
        pdf.setFont("Helvetica", 12)
        pdf.drawString(margin, 277, f"This page must still be readable after restarting iChart offline.")
        pdf.drawString(margin, 257, f"Expected first chord: {chords[0]}     Expected last chord: {chords[-1]}")
        pdf.setFont("Helvetica", 10)
        pdf.drawString(margin, 69, "Self-authored test material. Use a disposable copy for the external-file deletion check.")
        pdf.drawString(margin, 53, "Document import preserves the PDF. It does not convert its chords into editable notation.")
        pdf.drawRightString(width - margin, 30, f"{page_index} / 2")
        pdf.showPage()
    pdf.save()
    print(OUTPUT)


if __name__ == "__main__":
    main()
