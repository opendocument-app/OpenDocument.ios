#!/usr/bin/env python3
"""Builds the minimal ODF packages the page selection tests translate.

A few hundred bytes each, rather than the megabytes of third party material our
sample documents are, because all a test asks of them is how many pages a two
sheet spreadsheet turns into. Rerun when a fixture needs another sheet or slide:

    python3 scripts/make-test-fixtures.py
"""

import shutil
import subprocess
import zipfile
from pathlib import Path

# what test-encrypted.pdf is locked with
USER_PASSWORD = "secret"
OWNER_PASSWORD = "owner"

NAMESPACES = " ".join(
    [
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"',
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"',
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"',
        'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"',
        'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"',
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"',
        'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"',
    ]
)

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:media-type="{mimetype}"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>
"""

STYLES = f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles {NAMESPACES} office:version="1.2">
 <office:styles/>
 <office:automatic-styles>
  <style:page-layout style:name="PM1">
   <style:page-layout-properties fo:page-width="28cm" fo:page-height="21cm"/>
  </style:page-layout>
 </office:automatic-styles>
 <office:master-styles>
  <style:master-page style:name="Default" style:page-layout-name="PM1"/>
 </office:master-styles>
</office:document-styles>
"""


def content(body: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-content {NAMESPACES} office:version="1.2">
 <office:body>
{body}
 </office:body>
</office:document-content>
"""


def spreadsheet(sheets: list[str]) -> str:
    tables = "\n".join(
        f"""   <table:table table:name="{sheet}">
    <table:table-column/>
    <table:table-row>
     <table:table-cell office:value-type="string"><text:p>{sheet} A1</text:p></table:table-cell>
    </table:table-row>
   </table:table>"""
        for sheet in sheets
    )
    return content(f"  <office:spreadsheet>\n{tables}\n  </office:spreadsheet>")


def presentation(slides: list[str]) -> str:
    pages = "\n".join(
        f"""   <draw:page draw:name="{slide}" draw:master-page-name="Default">
    <draw:frame svg:width="10cm" svg:height="2cm" svg:x="1cm" svg:y="1cm">
     <draw:text-box><text:p>{slide}</text:p></draw:text-box>
    </draw:frame>
   </draw:page>"""
        for slide in slides
    )
    return content(f"  <office:presentation>\n{pages}\n  </office:presentation>")


def pdf(pages: list[str]) -> bytes:
    """A page per string, each showing it in Helvetica.

    Assembled by hand rather than with a library, because the trailer carries the
    byte offset of every object and nothing else about the file is hard.
    """
    font = 3
    # 1 catalog, 2 pages, 3 font, then a page and its content stream each
    page_numbers = [4 + 2 * index for index in range(len(pages))]

    kids = " ".join(f"{number} 0 R" for number in page_numbers)
    bodies = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]

    for number, text in zip(page_numbers, pages):
        stream = f"BT /F1 24 Tf 72 700 Td ({text}) Tj ET"
        bodies.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]"
            f" /Resources << /Font << /F1 {font} 0 R >> >>"
            f" /Contents {number + 1} 0 R >>"
        )
        bodies.append(f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream")

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(bodies, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n{body}\nendobj\n".encode("latin-1")

    startxref = len(out)
    out += f"xref\n0 {len(bodies) + 1}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode("latin-1")
    out += (
        f"trailer\n<< /Size {len(bodies) + 1} /Root 1 0 R >>\n"
        f"startxref\n{startxref}\n%%EOF\n"
    ).encode("latin-1")

    return bytes(out)


def encrypt_pdf(source: Path, target: Path) -> None:
    """AES-256, the standard security handler odrcore reads as `V 5`, `R 6`.

    Through qpdf rather than by hand: AES is not in the standard library, and
    R6 derives its key with it. Needs `brew install qpdf` to rerun.
    """
    if shutil.which("qpdf") is None:
        raise SystemExit("qpdf not found; it writes the encrypted pdf fixture")

    subprocess.run(
        [
            "qpdf",
            "--encrypt",
            f"--user-password={USER_PASSWORD}",
            f"--owner-password={OWNER_PASSWORD}",
            "--bits=256",
            "--",
            str(source),
            str(target),
        ],
        check=True,
    )


def write(path: Path, mimetype: str, content_xml: str) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as package:
        # first and uncompressed, or the package is only recognised by sniffing
        package.writestr(
            zipfile.ZipInfo("mimetype"), mimetype, compress_type=zipfile.ZIP_STORED
        )
        package.writestr("META-INF/manifest.xml", MANIFEST.format(mimetype=mimetype))
        package.writestr("styles.xml", STYLES)
        package.writestr("content.xml", content_xml)
    print(f"wrote {path}")


def main() -> None:
    tests = Path(__file__).resolve().parent.parent / "OpenDocumentReaderTests"

    write(
        tests / "test.ods",
        "application/vnd.oasis.opendocument.spreadsheet",
        spreadsheet(["Alpha", "Beta", "Gamma"]),
    )
    write(
        tests / "test.odp",
        "application/vnd.oasis.opendocument.presentation",
        presentation(["Intro", "Outro"]),
    )

    path = tests / "test.pdf"
    path.write_bytes(pdf(["First", "Second"]))
    print(f"wrote {path}")

    encrypted = tests / "test-encrypted.pdf"
    encrypt_pdf(path, encrypted)
    print(f"wrote {encrypted}")


if __name__ == "__main__":
    main()
