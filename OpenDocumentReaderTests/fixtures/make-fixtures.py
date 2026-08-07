#!/usr/bin/env python3
"""Builds the minimal ODF packages the page selection tests translate.

A few hundred bytes each, rather than the megabytes of third party material our
sample documents are, because all a test asks of them is how many pages a two
sheet spreadsheet turns into. Rerun when a fixture needs another sheet or slide:

    python3 OpenDocumentReaderTests/fixtures/make-fixtures.py
"""

import zipfile
from pathlib import Path

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
    here = Path(__file__).resolve().parent

    write(
        here.parent / "test.ods",
        "application/vnd.oasis.opendocument.spreadsheet",
        spreadsheet(["Alpha", "Beta", "Gamma"]),
    )
    write(
        here.parent / "test.odp",
        "application/vnd.oasis.opendocument.presentation",
        presentation(["Intro", "Outro"]),
    )


if __name__ == "__main__":
    main()
