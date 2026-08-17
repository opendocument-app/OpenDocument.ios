#!/usr/bin/env python3
"""Builds the documents the App Store screenshots are taken of.

A reader's screenshots are mostly the document it is reading, so these are
written rather than borrowed: a short report, a small spreadsheet and a three
slide deck, in every language the app speaks and the store has a listing for.
The screenshot of the German store shows a German document.

Kept small on purpose - a few kilobytes each, no images, no third party
material - because they are read once, on a simulator, to be photographed.
They are bundled in Debug builds only; `EXCLUDED_SOURCE_FILE_NAMES` keeps
`sample-*` out of the archive that goes to the store.

    python3 scripts/make-screenshot-documents.py
    python3 scripts/make-screenshot-documents.py --language en    one of them

What it writes is not committed - the screenshot lane runs this before it
builds. The packages are byte for byte reproducible, so a rerun that changes
no wording writes the same bytes.
"""

import argparse
import json
import re
import unicodedata
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

# 1980-01-01, what zip stores when it is given nothing: a rerun with the same
# words has to produce the same bytes, or every run is a commit
EPOCH = (1980, 1, 1, 0, 0, 0)

SAMPLES = Path(__file__).resolve().parent.parent / "OpenDocumentReader" / "Samples"

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

# A4 upright for the report and the sheet, 16:9 for the deck.
#
# A page is fitted to the width of the screen, so a page with little on it reads
# as a smudge in the top third of an empty sheet. The answer is words rather
# than smaller paper: these documents are written long enough to fill A4.
PAGE_LAYOUTS = {
    "document": '<style:page-layout-properties fo:page-width="21cm" fo:page-height="29.7cm"'
    ' fo:margin-top="2cm" fo:margin-bottom="2cm" fo:margin-left="2cm" fo:margin-right="2cm"/>',
    "slide": '<style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm"/>',
}

# One accent, used for the report's headings and the slide titles, so the three
# documents read as one set. Blue, because the app's own tint is.
ACCENT = "#1c6fd6"
RULE = "#d4d9e0"


def styles(kind: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles {NAMESPACES} office:version="1.2">
 <office:styles/>
 <office:automatic-styles>
  <style:page-layout style:name="PM1">
   {PAGE_LAYOUTS[kind]}
  </style:page-layout>
 </office:automatic-styles>
 <office:master-styles>
  <style:master-page style:name="Default" style:page-layout-name="PM1"/>
 </office:master-styles>
</office:document-styles>
"""


def content(body: str, automatic: str = "") -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-content {NAMESPACES} office:version="1.2">
 <office:automatic-styles>
{automatic}
 </office:automatic-styles>
 <office:body>
{body}
 </office:body>
</office:document-content>
"""


def paragraph_style(name: str, *, size: str, weight: str = "normal", colour: str = "#1a1a1a", space: str = "0.4cm") -> str:
    return f"""  <style:style style:name="{name}" style:family="paragraph">
   <style:paragraph-properties fo:margin-bottom="{space}"/>
   <style:text-properties fo:font-size="{size}" fo:font-weight="{weight}" fo:color="{colour}"/>
  </style:style>"""


def report(words: dict) -> str:
    """A page of text: a title, a lead, two headed sections and a closing line."""
    automatic = "\n".join(
        [
            paragraph_style("Title", size="26pt", weight="bold", space="0.8cm"),
            paragraph_style("Heading", size="16pt", weight="bold", colour=ACCENT, space="0.3cm"),
            paragraph_style("Body", size="12pt", space="0.5cm"),
        ]
    )

    lines = [
        f'   <text:p text:style-name="Title">{escape(words["title"])}</text:p>',
        f'   <text:p text:style-name="Body">{escape(words["lead"])}</text:p>',
    ]
    for heading, paragraphs in words["sections"]:
        lines.append(
            f'   <text:h text:style-name="Heading" text:outline-level="1">{escape(heading)}</text:h>'
        )
        lines += [f'   <text:p text:style-name="Body">{escape(text)}</text:p>' for text in paragraphs]
    lines.append(f'   <text:p text:style-name="Body">{escape(words["closing"])}</text:p>')

    return content("  <office:text>\n" + "\n".join(lines) + "\n  </office:text>", automatic)


def table(words: dict, columns: int = 4, rows: int = 0, scale: int = 1) -> tuple:
    """The figures as rows of cells: a header, the items across as many periods
    as are asked for with their totals, and a totals row under them.

    Narrowed and shortened for the files that are not the budget, so the .xlsx
    and the invoice hold their own figures rather than the .ods twice.

    As wide as the header a language has words for, so one translated ahead of
    the others comes out short rather than out of step.
    """
    periods = words["periods"][:columns]
    columns = len(periods)
    taken = FIGURES[:rows] if rows else FIGURES
    names = words["rows"][: len(taken)]

    head = [words["item"]] + periods + [words["total"]]
    body = [
        [name] + [value * scale for value in figures[:columns]] + [sum(figures[:columns]) * scale]
        for name, figures in zip(names, taken)
    ]
    foot = (
        [words["total"]]
        + [sum(line[column + 1] for line in body) for column in range(len(periods))]
        + [sum(line[-1] for line in body)]
    )

    return head, body, foot


def sheet(words: dict) -> str:
    """Two sheets, so the tab bar under the document has something to show."""
    automatic = "\n".join(
        [
            # two widths: eight at the label's width put half the sheet off
            # the right edge, and a figure needs less room than its row's name
            """  <style:style style:name="coLabel" style:family="table-column">
   <style:table-column-properties style:column-width="3.2cm"/>
  </style:style>""",
            """  <style:style style:name="coFigure" style:family="table-column">
   <style:table-column-properties style:column-width="2.2cm"/>
  </style:style>""",
            """  <style:style style:name="ceHead" style:family="table-cell">
   <style:table-cell-properties fo:background-color="#eef3fa" fo:border-bottom="0.06pt solid %s"/>
   <style:text-properties fo:font-weight="bold" fo:color="%s"/>
  </style:style>""" % (RULE, ACCENT),
            """  <style:style style:name="ceTotal" style:family="table-cell">
   <style:table-cell-properties fo:border-top="0.06pt solid %s"/>
   <style:text-properties fo:font-weight="bold"/>
  </style:style>""" % (RULE,),
        ]
    )

    def row(cells: list, style: str | None = None) -> str:
        marked = f' table:style-name="{style}"' if style else ""
        out = ["    <table:table-row>"]
        for cell in cells:
            if isinstance(cell, int):
                out.append(
                    f'     <table:table-cell{marked} office:value-type="float" office:value="{cell}">'
                    f"<text:p>{cell}</text:p></table:table-cell>"
                )
            else:
                out.append(
                    f'     <table:table-cell{marked} office:value-type="string">'
                    f"<text:p>{escape(cell)}</text:p></table:table-cell>"
                )
        out.append("    </table:table-row>")

        return "\n".join(out)

    head, body, foot = table(words, columns=6)

    overview = [row(head, "ceHead")] + [row(line) for line in body] + [row(foot, "ceTotal")]
    costs = [row([words["item"], words["total"]], "ceHead")]
    costs += [row([line[0], line[-1]]) for line in body]

    tables = []
    for name, rows, columns in (
        (words["sheets"][0], overview, len(head)),
        (words["sheets"][1], costs, 2),
    ):
        # the label column, then a figure column for each of the rest
        marks = "\n".join(
            ['    <table:table-column table:style-name="coLabel"/>']
            + ['    <table:table-column table:style-name="coFigure"/>'] * (columns - 1)
        )
        tables.append(
            f'   <table:table table:name="{escape(name)}">\n{marks}\n'
            + "\n".join(rows)
            + "\n   </table:table>"
        )

    return content("  <office:spreadsheet>\n" + "\n".join(tables) + "\n  </office:spreadsheet>", automatic)


def deck(words: dict) -> str:
    """Three slides, each with a title and its bullets."""
    automatic = "\n".join(
        [
            paragraph_style("SlideTitle", size="32pt", weight="bold", colour=ACCENT, space="0.6cm"),
            paragraph_style("Bullet", size="18pt", space="0.35cm"),
        ]
    )

    pages = []
    for title, bullets in words["slides"]:
        lines = [f'     <text:p text:style-name="SlideTitle">{escape(title)}</text:p>']
        lines += [
            f'     <text:p text:style-name="Bullet">\u2022 {escape(point)}</text:p>' for point in bullets
        ]
        pages.append(
            f'   <draw:page draw:name="{escape(title)}" draw:master-page-name="Default">\n'
            '    <draw:frame svg:width="24cm" svg:height="12cm" svg:x="2cm" svg:y="2cm">\n'
            "     <draw:text-box>\n" + "\n".join(lines) + "\n     </draw:text-box>\n"
            "    </draw:frame>\n   </draw:page>"
        )

    return content("  <office:presentation>\n" + "\n".join(pages) + "\n  </office:presentation>", automatic)


# Short and plain on purpose: this is a document over someone's shoulder in a
# store screenshot, not copy that has to sell anything.
WORDS = {
    "en": {
        "title": "Quarterly report",
        "lead": "The team met every goal of the second quarter, and the new release went out on time.",
        "sections": [
            ["Highlights", [
                "Costs stayed below budget, and two new partners joined the project.",
                "The new release reached more people in its first week than the last one did in a month.",
                "Support answered nine of ten questions the same day.",]],
            ["Costs and budget", [
                "Spending on software rose with the new licences, while travel fell again.",
                "Hardware was replaced once, and support stayed steady through the quarter.",
                "Two servers moved to the new provider without a day of downtime.",]],
            ["Next quarter", [
                "The release in September is the last one planned this year.",
                "Two positions open in support, and one in design.",
                "The office moves in November, and the budget for it is agreed.",
            ]],
            ["The people", [
                "Six people worked on the release, two of them new this year.",
                "Holiday cover was arranged in April and held through the summer.",
                "Everyone has taken the training the new licence requires.",
            ]],
            ["Risks", [
                "The move in November is the one date nothing else can slip past.",
                "One supplier has not signed the new terms, and is being chased.",
                "Hosting costs rise in January unless the contract is renewed early.",
            ]],
        ],
        "closing": "The next meeting is at the end of July.",
        "sheets": ["Overview", "Costs"],
        "item": "Item",
        "total": "Total",
        "periods": ["Jan", "Feb", "Mar", "Apr", "May", "Jun"],
        "rows": ["Software", "Travel", "Hardware", "Marketing", "Support", "Training", "Licences", "Hosting", "Events", "Office", "Cloud", "Recruiting", "Legal", "Insurance", "Catering", "Shipping", "Advertising", "Consulting", "Maintenance", "Utilities", "Equipment", "Subscriptions", "Telephony", "Internet", "Security", "Backups", "Domains", "Certificates", "Printing", "Stationery", "Postage", "Cleaning", "Repairs", "Furniture", "Storage", "Bank fees", "Memberships", "Conferences", "Translation", "Design"],
        "slides": [
            ["Project plan", ["Goals for the quarter", "Budget and costs", "Next steps"]],
            ["Schedule", ["Release in June", "Review in July", "Planning in August"]],
            ["Team", ["Two new partners", "Support in three languages", "Training in autumn"]],
        ],
    },
    "de": {
        "title": "Quartalsbericht",
        "lead": "Das Team hat alle Ziele des zweiten Quartals erreicht, und die neue Version ist p\u00fcnktlich erschienen.",
        "sections": [
            ["Das Wichtigste", [
                "Die Kosten blieben unter dem Budget, und zwei neue Partner sind zum Projekt gesto\u00dfen.",
                "Die neue Version erreichte in der ersten Woche mehr Menschen als die letzte in einem Monat.",
                "Der Support beantwortete neun von zehn Anfragen noch am selben Tag.",]],
            ["Kosten und Budget", [
                "Die Ausgaben f\u00fcr Software stiegen mit den neuen Lizenzen, die Reisekosten sanken erneut.",
                "Die Hardware wurde einmal ersetzt, der Support blieb das ganze Quartal \u00fcber stabil.",
                "Zwei Server sind ohne einen Tag Ausfall zum neuen Anbieter umgezogen.",]],
            ["N\xe4chstes Quartal", [
                "Die Version im September ist die letzte f\xfcr dieses Jahr.",
                "Zwei Stellen im Support sind offen, eine im Design.",
                "Der Umzug ins neue B\xfcro ist f\xfcr November geplant und budgetiert.",
            ]],
            ["Das Team", [
                "An der Version arbeiteten sechs Personen, zwei davon neu in diesem Jahr.",
                "Die Urlaubsvertretung wurde im April geregelt und hat den ganzen Sommer über gehalten.",
                "Alle haben die Schulung absolviert, die die neue Lizenz verlangt.",
            ]],
            ["Risiken", [
                "Der Umzug im November ist der einzige Termin, der sich nicht verschieben lässt.",
                "Ein Lieferant hat die neuen Bedingungen noch nicht unterschrieben; wir haken nach.",
                "Die Hostingkosten steigen im Januar, wenn der Vertrag nicht vorzeitig verl\xe4ngert wird.",
            ]],
        ],
        "closing": "Das n\u00e4chste Treffen findet Ende Juli statt.",
        "sheets": ["\u00dcbersicht", "Kosten"],
        "item": "Position",
        "total": "Gesamt",
        "periods": ["Jan", "Feb", "M\u00e4r", "Apr", "Mai", "Jun"],
        "rows": ["Software", "Reisen", "Hardware", "Marketing", "Support", "Schulung", "Lizenzen", "Hosting", "Veranstaltungen", "B\u00fcro", "Cloud", "Personalsuche", "Recht", "Versicherung", "Verpflegung", "Versand", "Werbung", "Beratung", "Wartung", "Nebenkosten", "Ausstattung", "Abonnements", "Telefonie", "Internet", "Sicherheit", "Backups", "Domains", "Zertifikate", "Druck", "B\u00fcromaterial", "Porto", "Reinigung", "Reparaturen", "M\u00f6bel", "Lager", "Bankgeb\u00fchren", "Mitgliedschaften", "Konferenzen", "\u00dcbersetzung", "Design"],
        "slides": [
            ["Projektplan", ["Ziele f\u00fcr das Quartal", "Budget und Kosten", "N\u00e4chste Schritte"]],
            ["Zeitplan", ["Version im Juni", "R\u00fcckblick im Juli", "Planung im August"]],
            ["Team", ["Zwei neue Partner", "Support in drei Sprachen", "Schulung im Herbst"]],
        ],
    },
    "es": {
        "title": "Informe trimestral",
        "lead": "El equipo cumpli\u00f3 todos los objetivos del segundo trimestre y la nueva versi\u00f3n sali\u00f3 a tiempo.",
        "sections": [
            ["Lo m\u00e1s destacado", [
                "Los costes se mantuvieron por debajo del presupuesto y dos nuevos socios se unieron al proyecto.",
                "La nueva versi\u00f3n lleg\u00f3 a m\u00e1s gente en su primera semana que la anterior en un mes.",
                "El soporte respondi\xf3 nueve de cada diez consultas el mismo d\xeda.",]],
            ["Costes y presupuesto", [
                "El gasto en software subi\u00f3 con las nuevas licencias, mientras que los viajes volvieron a bajar.",
                "El hardware se sustituy\u00f3 una vez y el soporte se mantuvo estable durante el trimestre.",
                "Dos servidores pasaron al nuevo proveedor sin una sola interrupci\xf3n del servicio.",]],
            ["Pr\xf3ximo trimestre", [
                "La versi\xf3n de septiembre es la \xfaltima prevista este a\xf1o.",
                "Hay dos vacantes en soporte y una en dise\xf1o.",
                "La mudanza de oficina es en noviembre y ya tiene presupuesto.",
            ]],
            ["Las personas", [
                "En la versi\xf3n trabajaron seis personas, dos de ellas nuevas este a\xf1o.",
                "La cobertura de vacaciones se organiz\xf3 en abril y aguant\xf3 todo el verano.",
                "Todos han hecho la formaci\xf3n que exige la nueva licencia.",
            ]],
            ["Riesgos", [
                "La mudanza de noviembre es la \xfanica fecha que no puede moverse.",
                "Un proveedor a\xfan no ha firmado las nuevas condiciones y se le est\xe1 reclamando.",
                "El alojamiento sube en enero si no se renueva antes el contrato.",
            ]],
        ],
        "closing": "La pr\u00f3xima reuni\u00f3n es a finales de julio.",
        "sheets": ["Resumen", "Costes"],
        "item": "Concepto",
        "total": "Total",
        "periods": ["Ene", "Feb", "Mar", "Abr", "May", "Jun"],
        "rows": ["Software", "Viajes", "Hardware", "Marketing", "Soporte", "Formaci\u00f3n", "Licencias", "Alojamiento", "Eventos", "Oficina", "Nube", "Contrataci\u00f3n", "Legal", "Seguros", "Catering", "Env\u00edos", "Publicidad", "Consultor\u00eda", "Mantenimiento", "Suministros", "Equipamiento", "Suscripciones", "Telefon\u00eda", "Internet", "Seguridad", "Copias de seguridad", "Dominios", "Certificados", "Impresi\u00f3n", "Papeler\u00eda", "Franqueo", "Limpieza", "Reparaciones", "Mobiliario", "Almacenamiento", "Comisiones bancarias", "Cuotas", "Congresos", "Traducci\u00f3n", "Dise\u00f1o"],
        "slides": [
            ["Plan del proyecto", ["Objetivos del trimestre", "Presupuesto y costes", "Pr\u00f3ximos pasos"]],
            ["Calendario", ["Versi\u00f3n en junio", "Revisi\u00f3n en julio", "Planificaci\u00f3n en agosto"]],
            ["Equipo", ["Dos nuevos socios", "Soporte en tres idiomas", "Formaci\u00f3n en oto\u00f1o"]],
        ],
    },
    "fr": {
        "title": "Rapport trimestriel",
        "lead": "L'\u00e9quipe a atteint tous les objectifs du deuxi\u00e8me trimestre et la nouvelle version est sortie \u00e0 temps.",
        "sections": [
            ["Points forts", [
                "Les co\u00fbts sont rest\u00e9s dans le budget et deux nouveaux partenaires ont rejoint le projet.",
                "La nouvelle version a touch\u00e9 plus de monde en une semaine que la pr\u00e9c\u00e9dente en un mois.",
                "Le support a r\xe9pondu \xe0 neuf demandes sur dix le jour m\xeame.",]],
            ["Co\u00fbts et budget", [
                "Les d\u00e9penses en logiciels ont augment\u00e9 avec les nouvelles licences, tandis que les d\u00e9placements ont encore baiss\u00e9.",
                "Le mat\u00e9riel a \u00e9t\u00e9 remplac\u00e9 une fois et le support est rest\u00e9 stable sur le trimestre.",
                "Deux serveurs ont migr\xe9 vers le nouveau prestataire sans la moindre interruption de service.",]],
            ["Trimestre prochain", [
                "La version de septembre est la derni\xe8re pr\xe9vue cette ann\xe9e.",
                "Deux postes sont ouverts au support, un au design.",
                "Le d\xe9m\xe9nagement est pr\xe9vu en novembre, et le budget est valid\xe9.",
            ]],
            ["Les personnes", [
                "Six personnes ont travaill\xe9 sur la version, dont deux arriv\xe9es cette ann\xe9e.",
                "Les remplacements pour les cong\xe9s ont \xe9t\xe9 organis\xe9s en avril et ont tenu tout l'\xe9t\xe9.",
                "Tout le monde a suivi la formation qu'exige la nouvelle licence.",
            ]],
            ["Risques", [
                "Le d\xe9m\xe9nagement de novembre est la seule date qui ne peut pas bouger.",
                "Un prestataire n'a pas encore sign\xe9 les nouvelles conditions.",
                "Le co\xfbt de l'h\xe9bergement augmente en janvier sans renouvellement anticip\xe9.",
            ]],
        ],
        "closing": "La prochaine r\u00e9union aura lieu fin juillet.",
        "sheets": ["Aper\u00e7u", "Co\u00fbts"],
        "item": "Poste",
        "total": "Total",
        "periods": ["Janv.", "F\u00e9vr.", "Mars", "Avr.", "Mai", "Juin"],
        "rows": ["Logiciels", "D\u00e9placements", "Mat\u00e9riel", "Marketing", "Support", "Formation", "Licences", "H\u00e9bergement", "\u00c9v\u00e9nements", "Bureau", "Cloud", "Recrutement", "Juridique", "Assurance", "Traiteur", "Exp\u00e9dition", "Publicit\u00e9", "Conseil", "Maintenance", "Charges", "\u00c9quipement", "Abonnements", "T\u00e9l\u00e9phonie", "Internet", "S\u00e9curit\u00e9", "Sauvegardes", "Domaines", "Certificats", "Impression", "Fournitures", "Affranchissement", "Nettoyage", "R\u00e9parations", "Mobilier", "Stockage", "Frais bancaires", "Cotisations", "Conf\u00e9rences", "Traduction", "Design"],
        "slides": [
            ["Plan du projet", ["Objectifs du trimestre", "Budget et co\u00fbts", "Prochaines \u00e9tapes"]],
            ["Calendrier", ["Version en juin", "Bilan en juillet", "Planification en ao\u00fbt"]],
            ["\u00c9quipe", ["Deux nouveaux partenaires", "Support en trois langues", "Formation \u00e0 l'automne"]],
        ],
    },
    "it": {
        "title": "Relazione trimestrale",
        "lead": "Il team ha raggiunto tutti gli obiettivi del secondo trimestre e la nuova versione \u00e8 uscita in tempo.",
        "sections": [
            ["In evidenza", [
                "I costi sono rimasti sotto il budget e due nuovi partner si sono uniti al progetto.",
                "La nuova versione ha raggiunto in una settimana pi\u00f9 persone di quante ne avesse raggiunte la precedente in un mese.",
                "Il supporto ha risposto a nove richieste su dieci in giornata.",]],
            ["Costi e budget", [
                "La spesa per il software \u00e8 cresciuta con le nuove licenze, mentre quella per i viaggi è di nuovo calata.",
                "L'hardware \u00e8 stato sostituito una volta e il supporto \u00e8 rimasto stabile per tutto il trimestre.",
                "Due server sono passati al nuovo fornitore senza un giorno di fermo.",]],
            ["Prossimo trimestre", [
                "La versione di settembre \xe8 l'ultima prevista quest'anno.",
                "Ci sono due posizioni aperte nel supporto e una nel design.",
                "Il trasloco \xe8 a novembre e il budget \xe8 approvato.",
            ]],
            ["Le persone", [
                "Alla versione hanno lavorato sei persone, due delle quali nuove quest'anno.",
                "Le sostituzioni estive sono state organizzate ad aprile e hanno retto.",
                "Tutti hanno seguito il corso richiesto dalla nuova licenza.",
            ]],
            ["Rischi", [
                "Il trasloco di novembre \xe8 l'unica data che non pu\xf2 slittare.",
                "Un fornitore non ha ancora firmato le nuove condizioni.",
                "I costi di hosting aumentano a gennaio se il contratto non viene rinnovato in anticipo.",
            ]],
        ],
        "closing": "Il prossimo incontro \u00e8 a fine luglio.",
        "sheets": ["Panoramica", "Costi"],
        "item": "Voce",
        "total": "Totale",
        "periods": ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu"],
        "rows": ["Software", "Viaggi", "Hardware", "Marketing", "Supporto", "Formazione", "Licenze", "Hosting", "Eventi", "Ufficio", "Cloud", "Selezione", "Legale", "Assicurazione", "Catering", "Spedizioni", "Pubblicit\u00e0", "Consulenza", "Manutenzione", "Utenze", "Attrezzature", "Abbonamenti", "Telefonia", "Internet", "Sicurezza", "Backup", "Domini", "Certificati", "Stampa", "Cancelleria", "Affrancature", "Pulizie", "Riparazioni", "Arredi", "Archiviazione", "Spese bancarie", "Quote associative", "Conferenze", "Traduzioni", "Design"],
        "slides": [
            ["Piano di progetto", ["Obiettivi del trimestre", "Budget e costi", "Prossimi passi"]],
            ["Calendario", ["Versione a giugno", "Revisione a luglio", "Pianificazione ad agosto"]],
            ["Team", ["Due nuovi partner", "Supporto in tre lingue", "Formazione in autunno"]],
        ],
    },
    "pl": {
        "title": "Raport kwartalny",
        "lead": "Zesp\u00f3\u0142 osi\u0105gn\u0105\u0142 wszystkie cele drugiego kwarta\u0142u, a nowa wersja ukaza\u0142a si\u0119 na czas.",
        "sections": [
            ["Najwa\u017cniejsze", [
                "Koszty pozosta\u0142y poni\u017cej bud\u017cetu, a do projektu do\u0142\u0105czy\u0142o dw\u00f3ch nowych partner\u00f3w.",
                "Nowa wersja dotar\u0142a w pierwszym tygodniu do wi\u0119kszej liczby os\u00f3b ni\u017c poprzednia w miesi\u0105c.",
                "Wsparcie odpowiedzia\u0142o na dziewi\u0119\u0107 z dziesi\u0119ciu zg\u0142osze\u0144 tego samego dnia.",]],
            ["Koszty i bud\u017cet", [
                "Wydatki na oprogramowanie wzros\u0142y wraz z nowymi licencjami, a koszty podr\u00f3\u017cy zn\u00f3w spad\u0142y.",
                "Sprz\u0119t wymieniono raz, a wsparcie by\u0142o stabilne przez ca\u0142y kwarta\u0142.",
                "Dwa serwery przeniesiono do nowego dostawcy bez ani jednego dnia przestoju.",]],
            ["Nast\u0119pny kwarta\u0142", [
                "Wersja z wrze\u015bnia jest ostatni\u0105 zaplanowan\u0105 w tym roku.",
                "Otwarte s\u0105 dwa etaty we wsparciu i jeden w dziale projektowym.",
                "Przeprowadzka biura wypada w listopadzie i ma ju\u017c bud\u017cet.",
            ]],
            ["Ludzie", [
                "Nad wersj\u0105 pracowa\u0142o sze\u015b\u0107 os\xf3b, z czego dwie do\u0142\u0105czy\u0142y w tym roku.",
                "Zast\u0119pstwa urlopowe ustalono w kwietniu i utrzyma\u0142y si\u0119 przez ca\u0142e lato.",
                "Wszyscy przeszli szkolenie wymagane przez now\u0105 licencj\u0119.",
            ]],
            ["Ryzyka", [
                "Przeprowadzka w listopadzie to jedyny termin, kt\xf3ry nie mo\u017ce si\u0119 przesun\u0105\u0107.",
                "Jeden dostawca nie podpisa\u0142 jeszcze nowych warunk\xf3w i jest ponaglany.",
                "Koszty hostingu wzrosn\u0105 w styczniu, je\u015bli umowa nie zostanie odnowiona wcze\u015bniej.",
            ]],
        ],
        "closing": "Nast\u0119pne spotkanie odb\u0119dzie si\u0119 pod koniec lipca.",
        "sheets": ["Przegl\u0105d", "Koszty"],
        "item": "Pozycja",
        "total": "Razem",
        "periods": ["sty", "lut", "mar", "kwi", "maj", "cze"],
        "rows": ["Oprogramowanie", "Podr\u00f3\u017ce", "Sprz\u0119t", "Marketing", "Wsparcie", "Szkolenia", "Licencje", "Hosting", "Wydarzenia", "Biuro", "Chmura", "Rekrutacja", "Prawo", "Ubezpieczenie", "Catering", "Wysy\u0142ka", "Reklama", "Doradztwo", "Utrzymanie", "Media", "Wyposa\u017cenie", "Subskrypcje", "Telefonia", "Internet", "Bezpiecze\u0144stwo", "Kopie zapasowe", "Domeny", "Certyfikaty", "Druk", "Artyku\u0142y biurowe", "Op\u0142aty pocztowe", "Sprz\u0105tanie", "Naprawy", "Meble", "Magazyn", "Op\u0142aty bankowe", "Sk\u0142adki cz\u0142onkowskie", "Konferencje", "T\u0142umaczenia", "Projektowanie"],
        "slides": [
            ["Plan projektu", ["Cele na kwarta\u0142", "Bud\u017cet i koszty", "Kolejne kroki"]],
            ["Harmonogram", ["Wersja w czerwcu", "Podsumowanie w lipcu", "Planowanie w sierpniu"]],
            ["Zesp\u00f3\u0142", ["Dw\u00f3ch nowych partner\u00f3w", "Wsparcie w trzech j\u0119zykach", "Szkolenia jesieni\u0105"]],
        ],
    },
    "pt-BR": {
        "title": "Relat\u00f3rio trimestral",
        "lead": "A equipe alcan\u00e7ou todas as metas do segundo trimestre e a nova vers\u00e3o saiu no prazo.",
        "sections": [
            ["Destaques", [
                "Os custos ficaram abaixo do or\u00e7amento e dois novos parceiros entraram no projeto.",
                "A nova vers\u00e3o alcan\u00e7ou mais pessoas na primeira semana do que a anterior em um m\u00eas.",
                "O suporte respondeu nove de cada dez chamados no mesmo dia.",]],
            ["Custos e or\u00e7amento", [
                "Os gastos com software subiram com as novas licen\u00e7as, enquanto as viagens ca\u00edram de novo.",
                "O hardware foi substitu\u00eddo uma vez e o suporte se manteve est\u00e1vel no trimestre.",
                "Dois servidores migraram para o novo provedor sem um dia de indisponibilidade.",]],
            ["Pr\xf3ximo trimestre", [
                "A vers\xe3o de setembro \xe9 a \xfaltima prevista para este ano.",
                "H\xe1 duas vagas no suporte e uma no design.",
                "A mudan\xe7a de escrit\xf3rio \xe9 em novembro e j\xe1 tem or\xe7amento.",
            ]],
            ["As pessoas", [
                "Seis pessoas trabalharam na vers\xe3o, duas delas novas este ano.",
                "A escala de f\xe9rias foi definida em abril e valeu o ver\xe3o todo.",
                "Todos fizeram o treinamento que a nova licen\xe7a exige.",
            ]],
            ["Riscos", [
                "A mudan\xe7a de novembro \xe9 a \xfanica data que n\xe3o pode atrasar.",
                "Um fornecedor ainda n\xe3o assinou as novas condi\xe7\xf5es.",
                "A hospedagem sobe em janeiro se o contrato n\xe3o for renovado antes.",
            ]],
        ],
        "closing": "A pr\u00f3xima reuni\u00e3o \u00e9 no fim de julho.",
        "sheets": ["Vis\u00e3o geral", "Custos"],
        "item": "Item",
        "total": "Total",
        "periods": ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun"],
        "rows": ["Software", "Viagens", "Hardware", "Marketing", "Suporte", "Treinamento", "Licen\u00e7as", "Hospedagem", "Eventos", "Escrit\u00f3rio", "Nuvem", "Recrutamento", "Jur\u00eddico", "Seguros", "Buffet", "Frete", "Publicidade", "Consultoria", "Manuten\u00e7\u00e3o", "\u00c1gua e luz", "Equipamentos", "Assinaturas", "Telefonia", "Internet", "Seguran\u00e7a", "Backups", "Dom\u00ednios", "Certificados", "Impress\u00e3o", "Papelaria", "Correios", "Limpeza", "Reparos", "M\u00f3veis", "Armazenamento", "Tarifas banc\u00e1rias", "Associa\u00e7\u00f5es", "Confer\u00eancias", "Tradu\u00e7\u00e3o", "Design"],
        "slides": [
            ["Plano do projeto", ["Metas do trimestre", "Or\u00e7amento e custos", "Pr\u00f3ximos passos"]],
            ["Cronograma", ["Vers\u00e3o em junho", "Revis\u00e3o em julho", "Planejamento em agosto"]],
            ["Equipe", ["Dois novos parceiros", "Suporte em tr\u00eas idiomas", "Treinamento no outono"]],
        ],
    },
    "ru": {
        "title": "\u041a\u0432\u0430\u0440\u0442\u0430\u043b\u044c\u043d\u044b\u0439 \u043e\u0442\u0447\u0451\u0442",
        "lead": "\u041a\u043e\u043c\u0430\u043d\u0434\u0430 \u0434\u043e\u0441\u0442\u0438\u0433\u043b\u0430 \u0432\u0441\u0435\u0445 \u0446\u0435\u043b\u0435\u0439 \u0432\u0442\u043e\u0440\u043e\u0433\u043e \u043a\u0432\u0430\u0440\u0442\u0430\u043b\u0430, \u0438 \u043d\u043e\u0432\u0430\u044f \u0432\u0435\u0440\u0441\u0438\u044f \u0432\u044b\u0448\u043b\u0430 \u0432 \u0441\u0440\u043e\u043a.",
        "sections": [
            ["\u0413\u043b\u0430\u0432\u043d\u043e\u0435", [
                "\u0420\u0430\u0441\u0445\u043e\u0434\u044b \u043e\u0441\u0442\u0430\u043b\u0438\u0441\u044c \u0432 \u0440\u0430\u043c\u043a\u0430\u0445 \u0431\u044e\u0434\u0436\u0435\u0442\u0430, \u0430 \u043a \u043f\u0440\u043e\u0435\u043a\u0442\u0443 \u043f\u0440\u0438\u0441\u043e\u0435\u0434\u0438\u043d\u0438\u043b\u0438\u0441\u044c \u0434\u0432\u0430 \u043d\u043e\u0432\u044b\u0445 \u043f\u0430\u0440\u0442\u043d\u0451\u0440\u0430.",
                "\u0417\u0430 \u043f\u0435\u0440\u0432\u0443\u044e \u043d\u0435\u0434\u0435\u043b\u044e \u043d\u043e\u0432\u0430\u044f \u0432\u0435\u0440\u0441\u0438\u044f \u043e\u0445\u0432\u0430\u0442\u0438\u043b\u0430 \u0431\u043e\u043b\u044c\u0448\u0435 \u043b\u044e\u0434\u0435\u0439, \u0447\u0435\u043c \u043f\u0440\u0435\u0434\u044b\u0434\u0443\u0449\u0430\u044f \u0437\u0430 \u043c\u0435\u0441\u044f\u0446.",
                "\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 \u043e\u0442\u0432\u0435\u0442\u0438\u043b\u0430 \u043d\u0430 \u0434\u0435\u0432\u044f\u0442\u044c \u0438\u0437 \u0434\u0435\u0441\u044f\u0442\u0438 \u043e\u0431\u0440\u0430\u0449\u0435\u043d\u0438\u0439 \u0432 \u0442\u043e\u0442 \u0436\u0435 \u0434\u0435\u043d\u044c.",]],
            ["\u0420\u0430\u0441\u0445\u043e\u0434\u044b \u0438 \u0431\u044e\u0434\u0436\u0435\u0442", [
                "\u0417\u0430\u0442\u0440\u0430\u0442\u044b \u043d\u0430 \u041f\u041e \u0432\u044b\u0440\u043e\u0441\u043b\u0438 \u0438\u0437-\u0437\u0430 \u043d\u043e\u0432\u044b\u0445 \u043b\u0438\u0446\u0435\u043d\u0437\u0438\u0439, \u0430 \u0440\u0430\u0441\u0445\u043e\u0434\u044b \u043d\u0430 \u043f\u043e\u0435\u0437\u0434\u043a\u0438 \u0441\u043d\u043e\u0432\u0430 \u0441\u043d\u0438\u0437\u0438\u043b\u0438\u0441\u044c.",
                "\u041e\u0431\u043e\u0440\u0443\u0434\u043e\u0432\u0430\u043d\u0438\u0435 \u043c\u0435\u043d\u044f\u043b\u0438 \u043e\u0434\u0438\u043d \u0440\u0430\u0437, \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 \u0440\u0430\u0431\u043e\u0442\u0430\u043b\u0430 \u0441\u0442\u0430\u0431\u0438\u043b\u044c\u043d\u043e \u0432\u0435\u0441\u044c \u043a\u0432\u0430\u0440\u0442\u0430\u043b.",
                "\u0414\u0432\u0430 \u0441\u0435\u0440\u0432\u0435\u0440\u0430 \u043f\u0435\u0440\u0435\u0435\u0445\u0430\u043b\u0438 \u043a \u043d\u043e\u0432\u043e\u043c\u0443 \u043f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440\u0443 \u0431\u0435\u0437 \u0435\u0434\u0438\u043d\u043e\u0433\u043e \u0434\u043d\u044f \u043f\u0440\u043e\u0441\u0442\u043e\u044f.",]],
            ["\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0438\u0439 \u043a\u0432\u0430\u0440\u0442\u0430\u043b", [
                "\u0412\u0435\u0440\u0441\u0438\u044f \u0432 \u0441\u0435\u043d\u0442\u044f\u0431\u0440\u0435 \u2014 \u043f\u043e\u0441\u043b\u0435\u0434\u043d\u044f\u044f \u0438\u0437 \u0437\u0430\u043f\u043b\u0430\u043d\u0438\u0440\u043e\u0432\u0430\u043d\u043d\u044b\u0445 \u0432 \u044d\u0442\u043e\u043c \u0433\u043e\u0434\u0443.",
                "\u041e\u0442\u043a\u0440\u044b\u0442\u044b \u0434\u0432\u0435 \u0432\u0430\u043a\u0430\u043d\u0441\u0438\u0438 \u0432 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0435 \u0438 \u043e\u0434\u043d\u0430 \u0432 \u0434\u0438\u0437\u0430\u0439\u043d\u0435.",
                "\u041f\u0435\u0440\u0435\u0435\u0437\u0434 \u043e\u0444\u0438\u0441\u0430 \u043d\u0430\u043c\u0435\u0447\u0435\u043d \u043d\u0430 \u043d\u043e\u044f\u0431\u0440\u044c, \u0431\u044e\u0434\u0436\u0435\u0442 \u0443\u0442\u0432\u0435\u0440\u0436\u0434\u0451\u043d.",
            ]],
            ["\u041b\u044e\u0434\u0438", [
                "\u041d\u0430\u0434 \u0432\u0435\u0440\u0441\u0438\u0435\u0439 \u0440\u0430\u0431\u043e\u0442\u0430\u043b\u0438 \u0448\u0435\u0441\u0442\u044c \u0447\u0435\u043b\u043e\u0432\u0435\u043a, \u0434\u0432\u043e\u0435 \u0438\u0437 \u043d\u0438\u0445 \u043f\u0440\u0438\u0448\u043b\u0438 \u0432 \u044d\u0442\u043e\u043c \u0433\u043e\u0434\u0443.",
                "\u0417\u0430\u043c\u0435\u043d\u044b \u043d\u0430 \u0432\u0440\u0435\u043c\u044f \u043e\u0442\u043f\u0443\u0441\u043a\u043e\u0432 \u0441\u043e\u0433\u043b\u0430\u0441\u043e\u0432\u0430\u043b\u0438 \u0432 \u0430\u043f\u0440\u0435\u043b\u0435, \u0438 \u0433\u0440\u0430\u0444\u0438\u043a \u043f\u0440\u043e\u0434\u0435\u0440\u0436\u0430\u043b\u0441\u044f \u0432\u0441\u0451 \u043b\u0435\u0442\u043e.",
                "\u0412\u0441\u0435 \u043f\u0440\u043e\u0448\u043b\u0438 \u043e\u0431\u0443\u0447\u0435\u043d\u0438\u0435, \u043a\u043e\u0442\u043e\u0440\u043e\u0433\u043e \u0442\u0440\u0435\u0431\u0443\u0435\u0442 \u043d\u043e\u0432\u0430\u044f \u043b\u0438\u0446\u0435\u043d\u0437\u0438\u044f.",
            ]],
            ["\u0420\u0438\u0441\u043a\u0438", [
                "\u041f\u0435\u0440\u0435\u0435\u0437\u0434 \u0432 \u043d\u043e\u044f\u0431\u0440\u0435 \u2014 \u0435\u0434\u0438\u043d\u0441\u0442\u0432\u0435\u043d\u043d\u0430\u044f \u0434\u0430\u0442\u0430, \u043a\u043e\u0442\u043e\u0440\u0443\u044e \u043d\u0435\u043b\u044c\u0437\u044f \u0441\u0434\u0432\u0438\u043d\u0443\u0442\u044c.",
                "\u041e\u0434\u0438\u043d \u043f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a \u0442\u0430\u043a \u0438 \u043d\u0435 \u043f\u043e\u0434\u043f\u0438\u0441\u0430\u043b \u043d\u043e\u0432\u044b\u0435 \u0443\u0441\u043b\u043e\u0432\u0438\u044f, \u0435\u043c\u0443 \u043d\u0430\u043f\u043e\u043c\u0438\u043d\u0430\u044e\u0442.",
                "\u0425\u043e\u0441\u0442\u0438\u043d\u0433 \u043f\u043e\u0434\u043e\u0440\u043e\u0436\u0430\u0435\u0442 \u0432 \u044f\u043d\u0432\u0430\u0440\u0435, \u0435\u0441\u043b\u0438 \u043d\u0435 \u043f\u0440\u043e\u0434\u043b\u0438\u0442\u044c \u0434\u043e\u0433\u043e\u0432\u043e\u0440 \u0437\u0430\u0440\u0430\u043d\u0435\u0435.",
            ]],
        ],
        "closing": "\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0430\u044f \u0432\u0441\u0442\u0440\u0435\u0447\u0430 \u2014 \u0432 \u043a\u043e\u043d\u0446\u0435 \u0438\u044e\u043b\u044f.",
        "sheets": ["\u041e\u0431\u0437\u043e\u0440", "\u0420\u0430\u0441\u0445\u043e\u0434\u044b"],
        "item": "\u0421\u0442\u0430\u0442\u044c\u044f",
        "total": "\u0418\u0442\u043e\u0433\u043e",
        "periods": ["\u042f\u043d\u0432.", "\u0424\u0435\u0432\u0440.", "\u041c\u0430\u0440\u0442", "\u0410\u043f\u0440.", "\u041c\u0430\u0439", "\u0418\u044e\u043d\u044c"],
        "rows": ["\u041f\u041e", "\u041f\u043e\u0435\u0437\u0434\u043a\u0438", "\u041e\u0431\u043e\u0440\u0443\u0434\u043e\u0432\u0430\u043d\u0438\u0435", "\u041c\u0430\u0440\u043a\u0435\u0442\u0438\u043d\u0433", "\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430", "\u041e\u0431\u0443\u0447\u0435\u043d\u0438\u0435", "\u041b\u0438\u0446\u0435\u043d\u0437\u0438\u0438", "\u0425\u043e\u0441\u0442\u0438\u043d\u0433", "\u041c\u0435\u0440\u043e\u043f\u0440\u0438\u044f\u0442\u0438\u044f", "\u041e\u0444\u0438\u0441", "\u041e\u0431\u043b\u0430\u043a\u043e", "\u041d\u0430\u0451\u043c", "\u042e\u0440\u0438\u0441\u0442\u044b", "\u0421\u0442\u0440\u0430\u0445\u043e\u0432\u0430\u043d\u0438\u0435", "\u041a\u0435\u0439\u0442\u0435\u0440\u0438\u043d\u0433", "\u0414\u043e\u0441\u0442\u0430\u0432\u043a\u0430", "\u0420\u0435\u043a\u043b\u0430\u043c\u0430", "\u041a\u043e\u043d\u0441\u0430\u043b\u0442\u0438\u043d\u0433", "\u041e\u0431\u0441\u043b\u0443\u0436\u0438\u0432\u0430\u043d\u0438\u0435", "\u041a\u043e\u043c\u043c\u0443\u043d\u0430\u043b\u044c\u043d\u044b\u0435 \u0443\u0441\u043b\u0443\u0433\u0438", "\u041e\u0441\u043d\u0430\u0449\u0435\u043d\u0438\u0435", "\u041f\u043e\u0434\u043f\u0438\u0441\u043a\u0438", "\u0422\u0435\u043b\u0435\u0444\u043e\u043d\u0438\u044f", "\u0418\u043d\u0442\u0435\u0440\u043d\u0435\u0442", "\u0411\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u044c", "\u0420\u0435\u0437\u0435\u0440\u0432\u043d\u043e\u0435 \u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d\u0438\u0435", "\u0414\u043e\u043c\u0435\u043d\u044b", "\u0421\u0435\u0440\u0442\u0438\u0444\u0438\u043a\u0430\u0442\u044b", "\u041f\u0435\u0447\u0430\u0442\u044c", "\u041a\u0430\u043d\u0446\u0442\u043e\u0432\u0430\u0440\u044b", "\u041f\u043e\u0447\u0442\u043e\u0432\u044b\u0435 \u0440\u0430\u0441\u0445\u043e\u0434\u044b", "\u0423\u0431\u043e\u0440\u043a\u0430", "\u0420\u0435\u043c\u043e\u043d\u0442", "\u041c\u0435\u0431\u0435\u043b\u044c", "\u0425\u0440\u0430\u043d\u0435\u043d\u0438\u0435", "\u0411\u0430\u043d\u043a\u043e\u0432\u0441\u043a\u0438\u0435 \u043a\u043e\u043c\u0438\u0441\u0441\u0438\u0438", "\u0427\u043b\u0435\u043d\u0441\u043a\u0438\u0435 \u0432\u0437\u043d\u043e\u0441\u044b", "\u041a\u043e\u043d\u0444\u0435\u0440\u0435\u043d\u0446\u0438\u0438", "\u041f\u0435\u0440\u0435\u0432\u043e\u0434", "\u0414\u0438\u0437\u0430\u0439\u043d"],
        "slides": [
            ["\u041f\u043b\u0430\u043d \u043f\u0440\u043e\u0435\u043a\u0442\u0430", ["\u0426\u0435\u043b\u0438 \u043d\u0430 \u043a\u0432\u0430\u0440\u0442\u0430\u043b", "\u0411\u044e\u0434\u0436\u0435\u0442 \u0438 \u0440\u0430\u0441\u0445\u043e\u0434\u044b", "\u0421\u043b\u0435\u0434\u0443\u044e\u0449\u0438\u0435 \u0448\u0430\u0433\u0438"]],
            ["\u0413\u0440\u0430\u0444\u0438\u043a", ["\u0412\u0435\u0440\u0441\u0438\u044f \u0432 \u0438\u044e\u043d\u0435", "\u0418\u0442\u043e\u0433\u0438 \u0432 \u0438\u044e\u043b\u0435", "\u041f\u043b\u0430\u043d\u0438\u0440\u043e\u0432\u0430\u043d\u0438\u0435 \u0432 \u0430\u0432\u0433\u0443\u0441\u0442\u0435"]],
            ["\u041a\u043e\u043c\u0430\u043d\u0434\u0430", ["\u0414\u0432\u0430 \u043d\u043e\u0432\u044b\u0445 \u043f\u0430\u0440\u0442\u043d\u0451\u0440\u0430", "\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430 \u043d\u0430 \u0442\u0440\u0451\u0445 \u044f\u0437\u044b\u043a\u0430\u0445", "\u041e\u0431\u0443\u0447\u0435\u043d\u0438\u0435 \u043e\u0441\u0435\u043d\u044c\u044e"]],
        ],
    },
    "tr": {
        "title": "\u00dc\u00e7 ayl\u0131k rapor",
        "lead": "Ekip ikinci \u00e7eyre\u011fin t\u00fcm hedeflerine ula\u015ft\u0131 ve yeni s\u00fcr\u00fcm zaman\u0131nda yay\u0131nland\u0131.",
        "sections": [
            ["\u00d6ne \u00e7\u0131kanlar", [
                "Maliyetler b\u00fct\u00e7enin alt\u0131nda kald\u0131 ve projeye iki yeni ortak kat\u0131ld\u0131.",
                "Yeni s\u00fcr\u00fcm ilk haftas\u0131nda, \u00f6ncekinin bir ayda ula\u015ft\u0131\u011f\u0131ndan daha fazla ki\u015fiye ula\u015ft\u0131.",
                "Destek, on sorudan dokuzunu ayn\u0131 g\xfcn yan\u0131tlad\u0131.",]],
            ["Maliyetler ve b\u00fct\u00e7e", [
                "Yeni lisanslarla yaz\u0131l\u0131m harcamalar\u0131 artt\u0131, seyahat giderleri yeniden d\u00fc\u015ft\u00fc.",
                "Donan\u0131m bir kez yenilendi ve destek \u00e7eyrek boyunca istikrarl\u0131 kald\u0131.",
                "\u0130ki sunucu, bir g\xfcn bile kesinti olmadan yeni sa\u011flay\u0131c\u0131ya ta\u015f\u0131nd\u0131.",]],
            ["Gelecek \xe7eyrek", [
                "Eyl\xfcldeki s\xfcr\xfcm bu y\u0131l planlanan son s\xfcr\xfcm.",
                "Destekte iki, tasar\u0131mda bir pozisyon a\xe7\u0131k.",
                "Ofis ta\u015f\u0131nmas\u0131 kas\u0131mda ve b\xfct\xe7esi onayland\u0131.",
            ]],
            ["Ekip", [
                "S\xfcr\xfcm \xfczerinde alt\u0131 ki\u015fi \xe7al\u0131\u015ft\u0131, ikisi bu y\u0131l kat\u0131ld\u0131.",
                "\u0130zin d\xf6nemi vekaletleri nisanda belirlendi ve yaz boyunca sorunsuz i\u015fledi.",
                "Herkes yeni lisans\u0131n gerektirdi\u011fi e\u011fitimi tamamlad\u0131.",
            ]],
            ["Riskler", [
                "Kas\u0131mdaki ta\u015f\u0131nma, ertelenemeyecek tek tarih.",
                "Bir tedarik\xe7i yeni ko\u015fullar\u0131 hen\xfcz imzalamad\u0131, takibi s\xfcr\xfcyor.",
                "S\xf6zle\u015fme erken yenilenmezse bar\u0131nd\u0131rma maliyeti ocakta artacak.",
            ]],
        ],
        "closing": "Bir sonraki toplant\u0131 temmuz sonunda.",
        "sheets": ["Genel bak\u0131\u015f", "Maliyetler"],
        "item": "Kalem",
        "total": "Toplam",
        "periods": ["Oca", "\u015eub", "Mar", "Nis", "May", "Haz"],
        "rows": ["Yaz\u0131l\u0131m", "Seyahat", "Donan\u0131m", "Pazarlama", "Destek", "E\u011fitim", "Lisanslar", "Bar\u0131nd\u0131rma", "Etkinlikler", "Ofis", "Bulut", "\u0130\u015fe al\u0131m", "Hukuk", "Sigorta", "\u0130kram", "Kargo", "Reklam", "Dan\u0131\u015fmanl\u0131k", "Bak\u0131m", "Faturalar", "Ekipman", "Abonelikler", "Telefon", "\u0130nternet", "G\u00fcvenlik", "Yedekleme", "Alan adlar\u0131", "Sertifikalar", "Bask\u0131", "K\u0131rtasiye", "Posta", "Temizlik", "Onar\u0131m", "Mobilya", "Depolama", "Banka masraflar\u0131", "\u00dcyelikler", "Konferanslar", "\u00c7eviri", "Tasar\u0131m"],
        "slides": [
            ["Proje plan\u0131", ["\u00c7eyrek hedefleri", "B\u00fct\u00e7e ve maliyetler", "Sonraki ad\u0131mlar"]],
            ["Takvim", ["Haziranda s\u00fcr\u00fcm", "Temmuzda de\u011ferlendirme", "A\u011fustosta planlama"]],
            ["Ekip", ["\u0130ki yeni ortak", "\u00dc\u00e7 dilde destek", "Sonbaharda e\u011fitim"]],
        ],
    },
}

# What the sheets add up: forty rows over six periods, so there is enough of it
# to look like a spreadsheet. The first twenty keep the first four figures they
# had, because the invoice and the .xlsx take slices off the front.
FIGURES = [
    [1200, 1450, 1310, 1600, 1380, 1520],
    [480, 620, 510, 470, 690, 540],
    [3600, 900, 1200, 750, 830, 1150],
    [820, 760, 930, 1010, 870, 940],
    [540, 560, 580, 600, 610, 630],
    [300, 450, 380, 520, 410, 470],
    [1100, 1150, 1180, 1240, 1260, 1290],
    [640, 640, 660, 680, 700, 700],
    [420, 980, 350, 610, 1240, 380],
    [260, 280, 270, 300, 290, 310],
    [890, 910, 940, 980, 1000, 1030],
    [1500, 400, 620, 350, 480, 390],
    [340, 360, 350, 370, 380, 390],
    [220, 220, 230, 230, 240, 240],
    [180, 620, 210, 240, 190, 660],
    [410, 430, 400, 450, 440, 460],
    [760, 820, 690, 900, 850, 780],
    [950, 480, 1100, 520, 560, 1180],
    [280, 290, 300, 310, 320, 330],
    [520, 540, 530, 560, 570, 590],
    [1340, 1290, 1410, 1360, 1440, 1480],
    [710, 730, 720, 750, 760, 780],
    [190, 200, 190, 210, 200, 220],
    [330, 330, 340, 340, 350, 350],
    [860, 890, 1240, 910, 930, 960],
    [240, 250, 260, 260, 270, 280],
    [120, 130, 120, 140, 130, 150],
    [460, 170, 180, 490, 180, 190],
    [580, 610, 550, 640, 600, 670],
    [150, 160, 170, 160, 180, 170],
    [210, 230, 220, 250, 240, 260],
    [390, 390, 400, 410, 410, 420],
    [270, 1080, 310, 340, 290, 360],
    [1620, 350, 380, 360, 400, 370],
    [620, 650, 630, 680, 660, 700],
    [110, 120, 110, 130, 120, 140],
    [440, 450, 460, 470, 480, 490],
    [980, 1020, 640, 1060, 1090, 720],
    [560, 500, 590, 530, 610, 570],
    [740, 770, 800, 790, 830, 860],
]

# What the browser lists them as. Realistic rather than descriptive: the first
# screenshot is meant to look like somebody's folder, and the extensions do the
# talking about what the app opens.
FILE_NAMES = {
    "en": {"text": "Quarterly report", "sheet": "Budget", "slides": "Project plan",
           "word": "Contract", "cells": "Sales figures", "deck": "Team offsite",
           "paper": "Invoice", "rows": "Contacts", "notes": "Notes"},
    "de": {"text": "Quartalsbericht", "sheet": "Budget", "slides": "Projektplan",
           "word": "Vertrag", "cells": "Umsatzzahlen", "deck": "Teamtreffen",
           "paper": "Rechnung", "rows": "Kontakte", "notes": "Notizen"},
    "es": {"text": "Informe trimestral", "sheet": "Presupuesto", "slides": "Plan del proyecto",
           "word": "Contrato", "cells": "Cifras de ventas", "deck": "Jornada de equipo",
           "paper": "Factura", "rows": "Contactos", "notes": "Notas"},
    "fr": {"text": "Rapport trimestriel", "sheet": "Budget", "slides": "Plan du projet",
           "word": "Contrat", "cells": "Chiffres des ventes", "deck": "R\u00e9union d'\u00e9quipe",
           "paper": "Facture", "rows": "Contacts", "notes": "Notes"},
    "it": {"text": "Relazione trimestrale", "sheet": "Budget", "slides": "Piano di progetto",
           "word": "Contratto", "cells": "Dati di vendita", "deck": "Ritiro del team",
           "paper": "Fattura", "rows": "Contatti", "notes": "Note"},
    "pl": {"text": "Raport kwartalny", "sheet": "Bud\u017cet", "slides": "Plan projektu",
           "word": "Umowa", "cells": "Wyniki sprzeda\u017cy", "deck": "Spotkanie zespo\u0142u",
           "paper": "Faktura", "rows": "Kontakty", "notes": "Notatki"},
    "pt-BR": {"text": "Relat\u00f3rio trimestral", "sheet": "Or\u00e7amento", "slides": "Plano do projeto",
              "word": "Contrato", "cells": "N\u00fameros de vendas", "deck": "Reuni\u00e3o da equipe",
              "paper": "Fatura", "rows": "Contatos", "notes": "Notas"},
    "ru": {"text": "\u041a\u0432\u0430\u0440\u0442\u0430\u043b\u044c\u043d\u044b\u0439 \u043e\u0442\u0447\u0451\u0442", "sheet": "\u0411\u044e\u0434\u0436\u0435\u0442", "slides": "\u041f\u043b\u0430\u043d \u043f\u0440\u043e\u0435\u043a\u0442\u0430",
           "word": "\u0414\u043e\u0433\u043e\u0432\u043e\u0440", "cells": "\u041f\u0440\u043e\u0434\u0430\u0436\u0438", "deck": "\u0412\u0441\u0442\u0440\u0435\u0447\u0430 \u043a\u043e\u043c\u0430\u043d\u0434\u044b",
           "paper": "\u0421\u0447\u0451\u0442", "rows": "\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u044b", "notes": "\u0417\u0430\u043c\u0435\u0442\u043a\u0438"},
    "tr": {"text": "\u00dc\u00e7 ayl\u0131k rapor", "sheet": "B\u00fct\u00e7e", "slides": "Proje plan\u0131",
           "word": "S\u00f6zle\u015fme", "cells": "Sat\u0131\u015f rakamlar\u0131", "deck": "Ekip \u00e7al\u0131\u015ftay\u0131",
           "paper": "Fatura", "rows": "Ki\u015filer", "notes": "Notlar"},
}

# The rest of the folder, so it does not read as a set of nine samples. Each is
# a copy of the sample named beside it, which only decides its icon: the browser
# shows a name and an icon, and none of them is ever opened.
FILLERS = {
    "meeting": "text",
    "letter": "text",
    "travel": "text",
    "reading": "text",
    "household": "sheet",
    "hours": "sheet",
    "stocktake": "sheet",
    "kickoff": "slides",
    "course": "slides",
    "lease": "word",
    "resume": "word",
    "application": "word",
    "expenses": "cells",
    "inventory": "cells",
    "review": "deck",
    "ticket": "paper",
    "warranty": "paper",
    "manual": "paper",
}

# A language with none of its own falls back to English.
FILLER_NAMES = {
    "en": {
        "meeting": "Meeting notes", "letter": "Letter to the landlord",
        "travel": "Travel plan", "reading": "Reading list",
        "household": "Household budget", "hours": "Hours", "stocktake": "Stocktake",
        "kickoff": "Kickoff", "course": "Course slides",
        "lease": "Lease", "resume": "CV", "application": "Application",
        "expenses": "Expenses", "inventory": "Inventory",
        "review": "Quarterly review",
        "ticket": "Ticket", "warranty": "Warranty", "manual": "Manual",
    },
    "de": {
        "meeting": "Besprechungsnotizen", "letter": "Brief an den Vermieter",
        "travel": "Reiseplan", "reading": "Leseliste",
        "household": "Haushaltsbudget", "hours": "Arbeitszeiten", "stocktake": "Inventur",
        "kickoff": "Auftakt", "course": "Kursfolien",
        "lease": "Mietvertrag", "resume": "Lebenslauf", "application": "Bewerbung",
        "expenses": "Ausgaben", "inventory": "Bestand",
        "review": "Quartalsr\u00fcckblick",
        "ticket": "Ticket", "warranty": "Garantie", "manual": "Anleitung",
    },
    "es": {
        "meeting": "Notas de reuni\u00f3n", "letter": "Carta al casero",
        "travel": "Plan de viaje", "reading": "Lista de lectura",
        "household": "Presupuesto dom\u00e9stico", "hours": "Horas", "stocktake": "Recuento",
        "kickoff": "Arranque del proyecto", "course": "Diapositivas del curso",
        "lease": "Alquiler del piso", "resume": "Curr\u00edculum", "application": "Solicitud",
        "expenses": "Gastos", "inventory": "Inventario",
        "review": "Revisi\u00f3n trimestral",
        "ticket": "Billete", "warranty": "Garant\u00eda", "manual": "Manual",
    },
    "fr": {
        "meeting": "Notes de r\u00e9union", "letter": "Lettre au propri\u00e9taire",
        "travel": "Itinéraire", "reading": "Liste de lecture",
        "household": "Budget familial", "hours": "Heures", "stocktake": "Inventaire",
        "kickoff": "Lancement", "course": "Diapositives du cours",
        "lease": "Bail", "resume": "CV", "application": "Candidature",
        "expenses": "D\u00e9penses", "inventory": "Stock",
        "review": "Bilan trimestriel",
        "ticket": "Billet", "warranty": "Garantie", "manual": "Manuel",
    },
    "it": {
        "meeting": "Note della riunione", "letter": "Lettera al locatore",
        "travel": "Piano di viaggio", "reading": "Lista di lettura",
        "household": "Bilancio familiare", "hours": "Ore", "stocktake": "Inventario",
        "kickoff": "Avvio", "course": "Diapositive del corso",
        "lease": "Contratto d'affitto", "resume": "Curriculum", "application": "Candidatura",
        "expenses": "Spese", "inventory": "Magazzino",
        "review": "Revisione trimestrale",
        "ticket": "Biglietto", "warranty": "Garanzia", "manual": "Manuale",
    },
    "pl": {
        "meeting": "Notatki ze spotkania", "letter": "List do w\u0142a\u015bciciela mieszkania",
        "travel": "Plan podr\u00f3\u017cy", "reading": "Lista lektur",
        "household": "Bud\u017cet domowy", "hours": "Godziny", "stocktake": "Inwentaryzacja",
        "kickoff": "Spotkanie startowe", "course": "Slajdy kursu",
        "lease": "Umowa najmu", "resume": "CV", "application": "Podanie",
        "expenses": "Wydatki", "inventory": "Stan magazynu",
        "review": "Przegl\u0105d kwartalny",
        "ticket": "Bilet", "warranty": "Gwarancja", "manual": "Instrukcja",
    },
    "pt-BR": {
        "meeting": "Notas da reuni\u00e3o", "letter": "Carta ao locador",
        "travel": "Plano de viagem", "reading": "Lista de leitura",
        "household": "Or\u00e7amento dom\u00e9stico", "hours": "Horas", "stocktake": "Balan\u00e7o",
        "kickoff": "Kickoff", "course": "Slides do curso",
        "lease": "Contrato de aluguel", "resume": "Curr\u00edculo", "application": "Inscri\u00e7\u00e3o",
        "expenses": "Despesas", "inventory": "Estoque",
        "review": "Revis\u00e3o trimestral",
        "ticket": "Passagem", "warranty": "Garantia", "manual": "Manual",
    },
    "ru": {
        "meeting": "\u0417\u0430\u043c\u0435\u0442\u043a\u0438 \u0441\u043e \u0432\u0441\u0442\u0440\u0435\u0447\u0438",
        "letter": "\u041f\u0438\u0441\u044c\u043c\u043e \u0430\u0440\u0435\u043d\u0434\u043e\u0434\u0430\u0442\u0435\u043b\u044e",
        "travel": "\u041f\u043b\u0430\u043d \u043f\u043e\u0435\u0437\u0434\u043a\u0438",
        "reading": "\u0421\u043f\u0438\u0441\u043e\u043a \u0447\u0442\u0435\u043d\u0438\u044f",
        "household": "\u0414\u043e\u043c\u0430\u0448\u043d\u0438\u0439 \u0431\u044e\u0434\u0436\u0435\u0442",
        "hours": "\u0427\u0430\u0441\u044b",
        "stocktake": "\u0418\u043d\u0432\u0435\u043d\u0442\u0430\u0440\u0438\u0437\u0430\u0446\u0438\u044f",
        "kickoff": "\u0421\u0442\u0430\u0440\u0442 \u043f\u0440\u043e\u0435\u043a\u0442\u0430",
        "course": "\u0421\u043b\u0430\u0439\u0434\u044b \u043a\u0443\u0440\u0441\u0430",
        "lease": "\u0414\u043e\u0433\u043e\u0432\u043e\u0440 \u0430\u0440\u0435\u043d\u0434\u044b",
        "resume": "\u0420\u0435\u0437\u044e\u043c\u0435",
        "application": "\u0417\u0430\u044f\u0432\u043b\u0435\u043d\u0438\u0435",
        "expenses": "\u0420\u0430\u0441\u0445\u043e\u0434\u044b",
        "inventory": "\u0421\u043a\u043b\u0430\u0434",
        "review": "\u041a\u0432\u0430\u0440\u0442\u0430\u043b\u044c\u043d\u044b\u0439 \u043e\u0431\u0437\u043e\u0440",
        "ticket": "\u0411\u0438\u043b\u0435\u0442",
        "warranty": "\u0413\u0430\u0440\u0430\u043d\u0442\u0438\u044f",
        "manual": "\u0418\u043d\u0441\u0442\u0440\u0443\u043a\u0446\u0438\u044f",
    },
    "tr": {
        "meeting": "Toplant\u0131 notlar\u0131", "letter": "Ev sahibine mektup",
        "travel": "Seyahat plan\u0131", "reading": "Okuma listesi",
        "household": "Ev b\u00fct\u00e7esi", "hours": "\u00c7al\u0131\u015fma saatleri",
        "stocktake": "Say\u0131m",
        "kickoff": "Proje ba\u015flang\u0131c\u0131", "course": "Kurs slaytlar\u0131",
        "lease": "Kira s\u00f6zle\u015fmesi", "resume": "\u00d6zge\u00e7mi\u015f",
        "application": "Ba\u015fvuru",
        "expenses": "Giderler", "inventory": "Envanter",
        "review": "\u00dc\u00e7 ayl\u0131k de\u011ferlendirme",
        "ticket": "Bilet", "warranty": "Garanti", "manual": "K\u0131lavuz",
    },
}


# The word the search screenshot looks for.
#
# Counted out of the document rather than written down, so it is always a word
# that is really in there, and always one that is in there several times - a
# search that highlights a single hit does not look like a search. Short words
# are skipped because "the" and "and" say nothing about the document.
def query(words: dict) -> str:
    """The most repeated long word of the report, which is what to search for."""
    text = " ".join(
        [words["title"], words["lead"], words["closing"]]
        + [heading for heading, _ in words["sections"]]
        + [line for _, paragraphs in words["sections"] for line in paragraphs]
    )

    counted = {}
    for word in re.findall(r"\w+", text.lower(), flags=re.UNICODE):
        if len(word) >= 5 and not word.isdigit():
            counted[word] = counted.get(word, 0) + 1

    # the most repeated, and the longest of those, so the choice is not a coin toss
    return max(counted, key=lambda word: (counted[word], len(word)))


# The folder is not nine copies of one report. What each file is called says
# what it should hold, so the contract reads like a contract and the invoice
# like an invoice - a folder where every document has the same title is the one
# thing a picture of a folder must not be.
OTHERS = {
    "en": {
        "contract": ["Service agreement",
                     "This agreement is made between the two parties named below.",
                     ["The supplier provides the software described in the appendix for one year.",
                      "Payment is due within thirty days of each invoice.",
                      "Either party may end this agreement with three months' notice.",
                      "Changes to this agreement are valid only in writing.",
                      "The supplier keeps the service available on working days.",
                      "Both parties treat what they learn of each other as confidential.",
                      "Austrian law applies, and the court of Vienna has jurisdiction.",
                      "The supplier keeps a backup of the customer's data for thirty days.",
                      "Support requests are answered within one working day.",
                      "The customer names one person who may approve changes.",
                      "Prices hold for the first year and are reviewed each autumn.",
                      "Neither party may pass this agreement to a third party without consent.",
                      "The appendix lists the software covered and the version it starts at.",
                      "This agreement replaces every earlier arrangement between the parties."]],
        "invoice": ["Invoice 2026-014", "Issued 12 June 2026", "Due within 30 days", "Billed to", "Subtotal", "VAT 20%", "Amount due", "Thank you for your business.", "Qty", "Unit price"],
        "contacts": [["Name", "Team", "Email", "Phone"],
                     ["Design", "Support", "Sales", "Engineering"]],
    },
    "de": {
        "contract": ["Dienstleistungsvertrag",
                     "Dieser Vertrag wird zwischen den beiden unten genannten Parteien geschlossen.",
                     ["Der Anbieter stellt die im Anhang beschriebene Software f\u00fcr ein Jahr bereit.",
                      "Die Zahlung ist innerhalb von drei\u00dfig Tagen nach Rechnungsstellung f\u00e4llig.",
                      "Beide Parteien k\u00f6nnen den Vertrag mit einer Frist von drei Monaten k\u00fcndigen.",
                      "\u00c4nderungen dieses Vertrags bed\u00fcrfen der Schriftform.",
                      "Der Anbieter h\xe4lt den Dienst an Werktagen verf\xfcgbar.",
                      "Beide Parteien behandeln vertraulich, was sie voneinander erfahren.",
                      "Es gilt \xf6sterreichisches Recht; Gerichtsstand ist Wien.",
                      "Der Anbieter bewahrt eine Sicherung der Daten des Kunden drei\xdfig Tage lang auf.",
                      "Supportanfragen werden innerhalb eines Werktags beantwortet.",
                      "Der Kunde benennt eine Person, die \xc4nderungen freigeben darf.",
                      "Die Preise gelten im ersten Jahr und werden jeden Herbst \xfcberpr\xfcft.",
                      "Keine Partei darf diesen Vertrag ohne Zustimmung an Dritte weitergeben.",
                      "Der Anhang nennt die erfasste Software und die Version, ab der sie gilt.",
                      "Dieser Vertrag ersetzt alle fr\xfcheren Vereinbarungen zwischen den Parteien."]],
        "invoice": ["Rechnung 2026-014", "Ausgestellt am 12. Juni 2026", "Zahlbar innerhalb von 30 Tagen", "Rechnung an", "Zwischensumme", "USt. 20%", "Zahlbetrag", "Vielen Dank f\xfcr Ihren Auftrag.", "Menge", "Einzelpreis"],
        "contacts": [["Name", "Team", "E-Mail", "Telefon"],
                     ["Design", "Support", "Vertrieb", "Entwicklung"]],
    },
    "es": {
        "contract": ["Contrato de servicios",
                     "Este contrato se celebra entre las dos partes indicadas a continuaci\u00f3n.",
                     ["El proveedor facilita el software descrito en el anexo durante un a\u00f1o.",
                      "El pago vence a los treinta d\u00edas de cada factura.",
                      "Cualquiera de las partes puede rescindirlo con tres meses de preaviso.",
                      "Las modificaciones solo son v\u00e1lidas por escrito.",
                      "El proveedor mantiene el servicio disponible los d\xedas laborables.",
                      "Ambas partes tratan como confidencial lo que conozcan de la otra.",
                      "Se aplica la ley austriaca y el tribunal de Viena es competente.",
                      "El proveedor conserva una copia de los datos del cliente durante treinta d\xedas.",
                      "Las consultas de soporte se responden en un d\xeda laborable.",
                      "El cliente designa a una persona que puede aprobar los cambios.",
                      "Los precios se mantienen el primer a\xf1o y se revisan cada oto\xf1o.",
                      "Ninguna parte puede ceder este contrato a un tercero sin consentimiento.",
                      "El anexo enumera el software incluido y la versi\xf3n desde la que se aplica.",
                      "Este contrato sustituye cualquier acuerdo anterior entre las partes."]],
        "invoice": ["Factura 2026-014", "Emitida el 12 de junio de 2026", "Vence en 30 d\u00edas", "Facturar a", "Subtotal", "IVA 20%", "Importe a pagar", "Gracias por su confianza.", "Cant.", "Precio unit."],
        "contacts": [["Nombre", "Equipo", "Correo", "Tel\u00e9fono"],
                     ["Dise\u00f1o", "Soporte", "Ventas", "Ingenier\u00eda"]],
    },
    "fr": {
        "contract": ["Contrat de service",
                     "Ce contrat est conclu entre les deux parties d\u00e9sign\u00e9es ci-dessous.",
                     ["Le prestataire fournit le logiciel d\u00e9crit en annexe pendant un an.",
                      "Le paiement est d\u00fb dans les trente jours suivant chaque facture.",
                      "Chaque partie peut r\u00e9silier le contrat avec un pr\u00e9avis de trois mois.",
                      "Toute modification n'est valable que par \u00e9crit.",
                      "Le prestataire maintient le service disponible les jours ouvr\xe9s.",
                      "Chaque partie traite comme confidentiel ce qu'elle apprend de l'autre.",
                      "Le droit autrichien s'applique et le tribunal de Vienne est comp\xe9tent.",
                      "Le prestataire conserve une sauvegarde des donn\xe9es du client pendant trente jours.",
                      "Les demandes de support re\xe7oivent une r\xe9ponse sous un jour ouvr\xe9.",
                      "Le client d\xe9signe une personne habilit\xe9e \xe0 approuver les modifications.",
                      "Les prix sont fermes la premi\xe8re ann\xe9e et revus chaque automne.",
                      "Aucune des parties ne peut c\xe9der ce contrat \xe0 un tiers sans accord.",
                      "L'annexe indique le logiciel couvert et la version \xe0 partir de laquelle la couverture s'applique.",
                      "Ce contrat remplace tout accord ant\xe9rieur entre les parties."]],
        "invoice": ["Facture 2026-014", "\u00c9mise le 12 juin 2026", "\u00c0 r\u00e9gler sous 30 jours", "Factur\xe9 \xe0", "Sous-total", "TVA 20 %", "Montant d\xfb", "Merci de votre confiance.", "Qt\xe9", "Prix unitaire"],
        "contacts": [["Nom", "\u00c9quipe", "E-mail", "T\u00e9l\u00e9phone"],
                     ["Design", "Support", "Ventes", "D\u00e9veloppement"]],
    },
    "it": {
        "contract": ["Contratto di servizio",
                     "Il presente contratto \u00e8 stipulato tra le due parti indicate di seguito.",
                     ["Il fornitore mette a disposizione per un anno il software descritto in allegato.",
                      "Il pagamento \u00e8 dovuto entro trenta giorni da ogni fattura.",
                      "Ciascuna parte pu\u00f2 recedere con un preavviso di tre mesi.",
                      "Le modifiche sono valide solo in forma scritta.",
                      "Il fornitore mantiene il servizio disponibile nei giorni lavorativi.",
                      "Le parti trattano come riservato quanto apprendono l'una dell'altra.",
                      "Si applica il diritto austriaco e il foro competente \xe8 Vienna.",
                      "Il fornitore conserva una copia dei dati del cliente per trenta giorni.",
                      "Le richieste di supporto ricevono risposta entro un giorno lavorativo.",
                      "Il cliente indica una persona autorizzata ad approvare le modifiche.",
                      "I prezzi restano fermi il primo anno e sono rivisti ogni autunno.",
                      "Nessuna parte pu\xf2 cedere il contratto a terzi senza consenso.",
                      "L'allegato elenca il software coperto e la versione di partenza.",
                      "Il presente contratto sostituisce ogni accordo precedente tra le parti."]],
        "invoice": ["Fattura 2026-014", "Emessa il 12 giugno 2026", "Da saldare entro 30 giorni", "Intestato a", "Subtotale", "IVA 20%", "Importo dovuto", "Grazie per la collaborazione.", "Qt\xe0", "Prezzo unit."],
        "contacts": [["Nome", "Reparto", "E-mail", "Telefono"],
                     ["Design", "Supporto", "Vendite", "Sviluppo"]],
    },
    "pl": {
        "contract": ["Umowa o \u015bwiadczenie us\u0142ug",
                     "Niniejsza umowa zostaje zawarta mi\u0119dzy dwiema stronami wymienionymi poni\u017cej.",
                     ["Dostawca udost\u0119pnia oprogramowanie opisane w za\u0142\u0105czniku na okres roku.",
                      "P\u0142atno\u015b\u0107 jest wymagalna w terminie trzydziestu dni od daty ka\u017cdej faktury.",
                      "Ka\u017cda ze stron mo\u017ce rozwi\u0105za\u0107 umow\u0119 z trzymiesi\u0119cznym wypowiedzeniem.",
                      "Zmiany umowy wymagaj\u0105 formy pisemnej.",
                      "Dostawca utrzymuje dost\u0119pno\u015b\u0107 us\u0142ugi w dni robocze.",
                      "Obie strony traktuj\u0105 jako poufne to, czego dowiedz\u0105 si\u0119 o sobie nawzajem.",
                      "Obowi\u0105zuje prawo austriackie, a s\u0105dem w\u0142a\u015bciwym jest s\u0105d w Wiedniu.",
                      "Dostawca przechowuje kopi\u0119 danych klienta przez trzydzie\u015bci dni.",
                      "Zg\u0142oszenia do wsparcia s\u0105 rozpatrywane w ci\u0105gu jednego dnia roboczego.",
                      "Klient wskazuje jedn\u0105 osob\u0119 uprawnion\u0105 do zatwierdzania zmian.",
                      "Ceny obowi\u0105zuj\u0105 przez pierwszy rok i s\u0105 weryfikowane ka\u017cdej jesieni.",
                      "\u017badna ze stron nie mo\u017ce przenie\u015b\u0107 umowy na osob\u0119 trzeci\u0105 bez zgody.",
                      "Za\u0142\u0105cznik wymienia oprogramowanie obj\u0119te umow\u0105 oraz wersj\u0119 pocz\u0105tkow\u0105.",
                      "Niniejsza umowa zast\u0119puje wszystkie wcze\u015bniejsze ustalenia stron."]],
        "invoice": ["Faktura 2026-014", "Wystawiono 12 czerwca 2026", "P\u0142atne w ci\u0105gu 30 dni", "Nabywca", "Warto\u015b\u0107 netto", "VAT 20%", "Do zap\u0142aty", "Dzi\u0119kujemy za wsp\xf3\u0142prac\u0119.", "Ilo\u015b\u0107", "Cena jedn."],
        "contacts": [["Imi\u0119 i nazwisko", "Dział", "E-mail", "Telefon"],
                     ["Projektowanie", "Wsparcie", "Sprzeda\u017c", "Rozw\u00f3j"]],
    },
    "pt-BR": {
        "contract": ["Contrato de servi\u00e7o",
                     "Este contrato \u00e9 celebrado entre as duas partes indicadas abaixo.",
                     ["O fornecedor disponibiliza por um ano o software descrito no anexo.",
                      "O pagamento vence em trinta dias a contar de cada fatura.",
                      "Qualquer parte pode encerrar o contrato com aviso pr\u00e9vio de tr\u00eas meses.",
                      "Altera\u00e7\u00f5es s\u00f3 s\u00e3o v\u00e1lidas por escrito.",
                      "O fornecedor mant\xe9m o servi\xe7o dispon\xedvel em dias \xfateis.",
                      "As partes tratam como confidencial o que souberem uma da outra.",
                      "Aplica-se a lei austr\xedaca e o foro competente \xe9 o de Viena.",
                      "O fornecedor mant\xe9m uma c\xf3pia dos dados do cliente por trinta dias.",
                      "Os chamados de suporte s\xe3o respondidos em um dia \xfatil.",
                      "O cliente indica uma pessoa autorizada a aprovar altera\xe7\xf5es.",
                      "Os pre\xe7os ficam fixos no primeiro ano e s\xe3o revisados todo outono.",
                      "Nenhuma parte pode transferir este contrato a terceiros sem consentimento.",
                      "O anexo lista o software abrangido e a vers\xe3o inicial coberta.",
                      "Este contrato substitui qualquer acordo anterior entre as partes."]],
        "invoice": ["Fatura 2026-014", "Emitida em 12 de junho de 2026", "Vence em 30 dias", "Faturado para", "Subtotal", "Impostos 20%", "Valor a pagar", "Obrigado pela prefer\xeancia.", "Qtd", "Pre\xe7o unit."],
        "contacts": [["Nome", "Equipe", "E-mail", "Telefone"],
                     ["Design", "Suporte", "Vendas", "Engenharia"]],
    },
    "ru": {
        "contract": ["\u0414\u043e\u0433\u043e\u0432\u043e\u0440 \u043e\u043a\u0430\u0437\u0430\u043d\u0438\u044f \u0443\u0441\u043b\u0443\u0433",
                     "\u041d\u0430\u0441\u0442\u043e\u044f\u0449\u0438\u0439 \u0434\u043e\u0433\u043e\u0432\u043e\u0440 \u0437\u0430\u043a\u043b\u044e\u0447\u0451\u043d \u043c\u0435\u0436\u0434\u0443 \u0434\u0432\u0443\u043c\u044f \u0441\u0442\u043e\u0440\u043e\u043d\u0430\u043c\u0438, \u0443\u043a\u0430\u0437\u0430\u043d\u043d\u044b\u043c\u0438 \u043d\u0438\u0436\u0435.",
                     ["\u0418\u0441\u043f\u043e\u043b\u043d\u0438\u0442\u0435\u043b\u044c \u043f\u0440\u0435\u0434\u043e\u0441\u0442\u0430\u0432\u043b\u044f\u0435\u0442 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u043d\u043e\u0435 \u043e\u0431\u0435\u0441\u043f\u0435\u0447\u0435\u043d\u0438\u0435, \u0443\u043a\u0430\u0437\u0430\u043d\u043d\u043e\u0435 \u0432 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0438, \u0441\u0440\u043e\u043a\u043e\u043c \u043d\u0430 \u043e\u0434\u0438\u043d \u0433\u043e\u0434.",
                      "\u041e\u043f\u043b\u0430\u0442\u0430 \u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0441\u044f \u0432 \u0442\u0435\u0447\u0435\u043d\u0438\u0435 \u0442\u0440\u0438\u0434\u0446\u0430\u0442\u0438 \u0434\u043d\u0435\u0439 \u0441 \u0434\u0430\u0442\u044b \u0441\u0447\u0451\u0442\u0430.",
                      "\u041a\u0430\u0436\u0434\u0430\u044f \u0438\u0437 \u0441\u0442\u043e\u0440\u043e\u043d \u043c\u043e\u0436\u0435\u0442 \u0440\u0430\u0441\u0442\u043e\u0440\u0433\u043d\u0443\u0442\u044c \u0434\u043e\u0433\u043e\u0432\u043e\u0440, \u0443\u0432\u0435\u0434\u043e\u043c\u0438\u0432 \u0437\u0430 \u0442\u0440\u0438 \u043c\u0435\u0441\u044f\u0446\u0430.",
                      "\u0418\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u044c\u043d\u044b \u0442\u043e\u043b\u044c\u043a\u043e \u0432 \u043f\u0438\u0441\u044c\u043c\u0435\u043d\u043d\u043e\u043c \u0432\u0438\u0434\u0435.",
                      "\u0418\u0441\u043f\u043e\u043b\u043d\u0438\u0442\u0435\u043b\u044c \u043e\u0431\u0435\u0441\u043f\u0435\u0447\u0438\u0432\u0430\u0435\u0442 \u0434\u043e\u0441\u0442\u0443\u043f\u043d\u043e\u0441\u0442\u044c \u0441\u0435\u0440\u0432\u0438\u0441\u0430 \u0432 \u0440\u0430\u0431\u043e\u0447\u0438\u0435 \u0434\u043d\u0438.",
                      "\u0421\u0442\u043e\u0440\u043e\u043d\u044b \u0441\u043e\u0445\u0440\u0430\u043d\u044f\u044e\u0442 \u0432 \u0442\u0430\u0439\u043d\u0435 \u0441\u0432\u0435\u0434\u0435\u043d\u0438\u044f, \u043f\u043e\u043b\u0443\u0447\u0435\u043d\u043d\u044b\u0435 \u0434\u0440\u0443\u0433 \u043e \u0434\u0440\u0443\u0433\u0435.",
                      "\u041f\u0440\u0438\u043c\u0435\u043d\u044f\u0435\u0442\u0441\u044f \u0430\u0432\u0441\u0442\u0440\u0438\u0439\u0441\u043a\u043e\u0435 \u043f\u0440\u0430\u0432\u043e, \u0441\u043f\u043e\u0440\u044b \u0440\u0430\u0441\u0441\u043c\u0430\u0442\u0440\u0438\u0432\u0430\u0435\u0442 \u0441\u0443\u0434 \u0412\u0435\u043d\u044b.",
                      "\u0418\u0441\u043f\u043e\u043b\u043d\u0438\u0442\u0435\u043b\u044c \u0445\u0440\u0430\u043d\u0438\u0442 \u0440\u0435\u0437\u0435\u0440\u0432\u043d\u0443\u044e \u043a\u043e\u043f\u0438\u044e \u0434\u0430\u043d\u043d\u044b\u0445 \u0437\u0430\u043a\u0430\u0437\u0447\u0438\u043a\u0430 \u0442\u0440\u0438\u0434\u0446\u0430\u0442\u044c \u0434\u043d\u0435\u0439.",
                      "\u041e\u0431\u0440\u0430\u0449\u0435\u043d\u0438\u044f \u0432 \u043f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0443 \u0440\u0430\u0441\u0441\u043c\u0430\u0442\u0440\u0438\u0432\u0430\u044e\u0442\u0441\u044f \u0432 \u0442\u0435\u0447\u0435\u043d\u0438\u0435 \u043e\u0434\u043d\u043e\u0433\u043e \u0440\u0430\u0431\u043e\u0447\u0435\u0433\u043e \u0434\u043d\u044f.",
                      "\u0417\u0430\u043a\u0430\u0437\u0447\u0438\u043a \u043d\u0430\u0437\u043d\u0430\u0447\u0430\u0435\u0442 \u043e\u0434\u043d\u043e\u0433\u043e \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u0430, \u043a\u043e\u0442\u043e\u0440\u044b\u0439 \u0432\u043f\u0440\u0430\u0432\u0435 \u0443\u0442\u0432\u0435\u0440\u0436\u0434\u0430\u0442\u044c \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f.",
                      "\u0426\u0435\u043d\u044b \u0444\u0438\u043a\u0441\u0438\u0440\u0443\u044e\u0442\u0441\u044f \u043d\u0430 \u043f\u0435\u0440\u0432\u044b\u0439 \u0433\u043e\u0434 \u0438 \u043f\u0435\u0440\u0435\u0441\u043c\u0430\u0442\u0440\u0438\u0432\u0430\u044e\u0442\u0441\u044f \u043a\u0430\u0436\u0434\u0443\u044e \u043e\u0441\u0435\u043d\u044c.",
                      "\u041d\u0438 \u043e\u0434\u043d\u0430 \u0438\u0437 \u0441\u0442\u043e\u0440\u043e\u043d \u043d\u0435 \u0432\u043f\u0440\u0430\u0432\u0435 \u043f\u0435\u0440\u0435\u0434\u0430\u0442\u044c \u0434\u043e\u0433\u043e\u0432\u043e\u0440 \u0442\u0440\u0435\u0442\u044c\u0435\u043c\u0443 \u043b\u0438\u0446\u0443 \u0431\u0435\u0437 \u0441\u043e\u0433\u043b\u0430\u0441\u0438\u044f.",
                      "\u0412 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0438 \u0443\u043a\u0430\u0437\u0430\u043d\u043e, \u043a\u0430\u043a\u043e\u0435 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u043d\u043e\u0435 \u043e\u0431\u0435\u0441\u043f\u0435\u0447\u0435\u043d\u0438\u0435 \u0432\u0445\u043e\u0434\u0438\u0442 \u0432 \u0434\u043e\u0433\u043e\u0432\u043e\u0440 \u0438 \u0441 \u043a\u0430\u043a\u043e\u0439 \u0432\u0435\u0440\u0441\u0438\u0438.",
                      "\u041d\u0430\u0441\u0442\u043e\u044f\u0449\u0438\u0439 \u0434\u043e\u0433\u043e\u0432\u043e\u0440 \u0437\u0430\u043c\u0435\u043d\u044f\u0435\u0442 \u0432\u0441\u0435 \u043f\u0440\u0435\u0436\u043d\u0438\u0435 \u0434\u043e\u0433\u043e\u0432\u043e\u0440\u0451\u043d\u043d\u043e\u0441\u0442\u0438 \u0441\u0442\u043e\u0440\u043e\u043d."]],
        "invoice": ["\u0421\u0447\u0451\u0442 2026-014", "\u0412\u044b\u0441\u0442\u0430\u0432\u043b\u0435\u043d 12 \u0438\u044e\u043d\u044f 2026 \u0433.", "\u041e\u043f\u043b\u0430\u0442\u0430 \u0432 \u0442\u0435\u0447\u0435\u043d\u0438\u0435 30 \u0434\u043d\u0435\u0439", "\u041f\u043b\u0430\u0442\u0435\u043b\u044c\u0449\u0438\u043a", "\u041f\u0440\u043e\u043c\u0435\u0436\u0443\u0442\u043e\u0447\u043d\u044b\u0439 \u0438\u0442\u043e\u0433", "\u041d\u0414\u0421 20%", "\u041a \u043e\u043f\u043b\u0430\u0442\u0435", "\u0411\u043b\u0430\u0433\u043e\u0434\u0430\u0440\u0438\u043c \u0437\u0430 \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u0447\u0435\u0441\u0442\u0432\u043e.", "\u041a\u043e\u043b-\u0432\u043e", "\u0426\u0435\u043d\u0430 \u0437\u0430 \u0435\u0434."],
        "contacts": [["\u0424\u0418\u041e", "\u041e\u0442\u0434\u0435\u043b", "\u041f\u043e\u0447\u0442\u0430", "\u0422\u0435\u043b\u0435\u0444\u043e\u043d"],
                     ["\u0414\u0438\u0437\u0430\u0439\u043d", "\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430", "\u041f\u0440\u043e\u0434\u0430\u0436\u0438", "\u0420\u0430\u0437\u0440\u0430\u0431\u043e\u0442\u043a\u0430"]],
    },
    "tr": {
        "contract": ["Hizmet s\u00f6zle\u015fmesi",
                     "Bu s\u00f6zle\u015fme a\u015fa\u011f\u0131da belirtilen iki taraf aras\u0131nda yap\u0131lm\u0131\u015ft\u0131r.",
                     ["Tedarik\u00e7i, ekte tan\u0131mlanan yaz\u0131l\u0131m\u0131 bir y\u0131l boyunca sa\u011flar.",
                      "\u00d6deme, her faturadan sonra otuz g\u00fcn i\u00e7inde yap\u0131l\u0131r.",
                      "Taraflardan biri s\u00f6zle\u015fmeyi \u00fc\u00e7 ay \u00f6nceden bildirerek sonland\u0131rabilir.",
                      "De\u011fi\u015fiklikler yaln\u0131zca yaz\u0131l\u0131 olarak ge\u00e7erlidir.",
                      "Tedarik\xe7i hizmeti i\u015f g\xfcnlerinde eri\u015filebilir tutar.",
                      "Taraflar birbirleri hakk\u0131nda \xf6\u011frendiklerini gizli tutar.",
                      "Avusturya hukuku uygulan\u0131r ve yetkili mahkeme Viyana'd\u0131r.",
                      "Tedarik\xe7i, m\xfc\u015fterinin verilerinin yede\u011fini otuz g\xfcn saklar.",
                      "Destek talepleri bir i\u015f g\xfcn\xfc i\xe7inde yan\u0131tlan\u0131r.",
                      "M\xfc\u015fteri, de\u011fi\u015fiklikleri onaylayabilecek bir ki\u015fi belirler.",
                      "Fiyatlar ilk y\u0131l sabittir ve her sonbahar g\xf6zden ge\xe7irilir.",
                      "Hi\xe7bir taraf s\xf6zle\u015fmeyi onay almadan \xfc\xe7\xfcnc\xfc ki\u015fiye devredemez.",
                      "Ek, kapsanan yaz\u0131l\u0131m\u0131 ve ge\xe7erli oldu\u011fu s\xfcr\xfcm\xfc listeler.",
                      "Bu s\xf6zle\u015fme, taraflar aras\u0131ndaki \xf6nceki t\xfcm d\xfczenlemelerin yerine ge\xe7er."]],
        "invoice": ["Fatura 2026-014", "12 Haziran 2026 tarihli", "30 g\u00fcn i\u00e7inde \u00f6denir", "Alıcı", "Ara toplam", "KDV %20", "\xd6denecek tutar", "\u0130\u015f birli\u011finiz i\xe7in te\u015fekk\xfcrler.", "Adet", "Birim fiyat"],
        "contacts": [["Ad Soyad", "Ekip", "E-posta", "Telefon"],
                     ["Tasar\u0131m", "Destek", "Sat\u0131\u015f", "Geli\u015ftirme"]],
    },
}

# Names are names in every language, so these are not translated.
PEOPLE = ["A. Bauer", "M. Rossi", "J. Novak", "L. Dubois", "S. Meyer", "K. Larsen"]


# --- the other formats ------------------------------------------------------
#
# The first screenshot is a folder, so the folder has to look like somebody's.
# What it holds is the quiet half of the message: an .odt beside an .xlsx beside
# a .pdf says what the app opens without a line of copy claiming it.
#
# These are written small and plain for the same reason the ODF ones are. They
# are read by odrcore, not by Word, so they carry the least markup that is still
# a valid package.

OOXML_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="{type}" Target="{target}"/>
</Relationships>
"""

WORD_MAIN = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"


def docx_parts(words: dict, others: dict) -> dict:
    """The Word file is the contract, not another copy of the report."""
    title, lead, clauses = others["contract"]

    def run(text: str, *, size: int, bold: bool = False, colour: str = "") -> str:
        marks = ("<w:b/>" if bold else "") + (f'<w:color w:val="{colour}"/>' if colour else "")

        return (
            f"<w:r><w:rPr>{marks}<w:sz w:val=\"{size}\"/></w:rPr>"
            f'<w:t xml:space="preserve">{escape(text)}</w:t></w:r>'
        )

    def para(runs: str, after: int) -> str:
        return f'<w:p><w:pPr><w:spacing w:after="{after}"/></w:pPr>{runs}</w:p>'

    # A clause is two sentences in one paragraph, numbered in line with the
    # first. A number on a line of its own above a single sentence reads as a
    # list of scraps rather than as a contract.
    paragraphs = [
        para(run(title, size=72, bold=True), 640),
        para(run(lead, size=22), 420),
    ]
    for number, index in enumerate(range(0, len(clauses) - 1, 2), start=1):
        body = " ".join(clauses[index:index + 2])
        paragraphs.append(
            para(
                run(f"{number}.  ", size=22, bold=True, colour=ACCENT[1:]) + run(body, size=22),
                300,
            )
        )

    # An empty paragraph between them, rather than trusting w:spacing: the
    # renderer sets the clauses flush against each other whatever `w:after`
    # says, and a contract whose clauses touch reads as one block of text.
    body = '<w:p/>'.join(paragraphs)

    return {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.wordprocessingml.styles+xml"/></Types>',
        "_rels/.rels": OOXML_RELS.format(type=WORD_MAIN, target="word/document.xml"),
        # Not optional. odrcore opens /word/styles.xml whether or not the
        # document has a style in it, and a package without one is not read as a
        # Word file at all: it falls through to the web view, which draws the
        # text with no page around it and offers neither search nor editing.
        "word/_rels/document.xml.rels": OOXML_RELS.format(
            type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles",
            target="styles.xml",
        ),
        "word/styles.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        "<w:docDefaults><w:rPrDefault><w:rPr>"
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/>'
        "</w:rPr></w:rPrDefault>"
        '<w:pPrDefault><w:pPr><w:spacing w:after="160"/></w:pPr></w:pPrDefault>'
        "</w:docDefaults>"
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/></w:style>'
        "</w:styles>",
        "word/document.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        # A4 with 2cm margins, in twentieths of a point. Without it there is no
        # page for odrcore to lay the text on, and the document is drawn as a
        # bare column of text rather than as a sheet of paper.
        f"<w:body>{body}"
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>'
        "</w:sectPr></w:body></w:document>",
    }


def xlsx_parts(words: dict) -> dict:
    """A workbook of its own figures, so it is not the .ods twice."""
    head, body, foot = table(words, columns=2, rows=8, scale=3)
    rows_of = [head] + body + [foot]

    def cell(column: int, row: int, value) -> str:
        reference = f"{chr(ord('A') + column)}{row}"
        if isinstance(value, int):
            return f'<c r="{reference}"><v>{value}</v></c>'

        return f'<c r="{reference}" t="inlineStr"><is><t>{escape(value)}</t></is></c>'

    rows = "".join(
        f'<row r="{index + 1}">'
        + "".join(cell(column, index + 1, value) for column, value in enumerate(line))
        + "</row>"
        for index, line in enumerate(rows_of)
    )

    return {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.spreadsheetml.worksheet+xml"/></Types>',
        "_rels/.rels": OOXML_RELS.format(type=WORD_MAIN, target="xl/workbook.xml"),
        "xl/_rels/workbook.xml.rels": OOXML_RELS.format(
            type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet",
            target="worksheets/sheet1.xml",
        ),
        "xl/workbook.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'<sheets><sheet name="{escape(words["sheets"][0])}" sheetId="1" r:id="rId1"/></sheets></workbook>',
        "xl/worksheets/sheet1.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f"<sheetData>{rows}</sheetData></worksheet>",
    }


def pptx_parts(words: dict) -> dict:
    """One slide, titled and bulleted, so a deck opens on something."""
    drawing = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
    presentation = 'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'

    def shape(identifier: int, name: str, box: str, lines: list, size: int) -> str:
        paragraphs = "".join(
            f'<a:p><a:r><a:rPr lang="en" sz="{size}" b="{1 if size > 2000 else 0}"/>'
            f"<a:t>{escape(line)}</a:t></a:r></a:p>"
            for line in lines
        )

        return (
            f'<p:sp><p:nvSpPr><p:cNvPr id="{identifier}" name="{name}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
            f"<p:spPr><a:xfrm>{box}</a:xfrm>"
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
            f"<p:txBody><a:bodyPr/><a:lstStyle/>{paragraphs}</p:txBody></p:sp>"
        )

    slide = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld {presentation} {drawing}>'
        "<p:cSld><p:spTree>"
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        + shape(
            2,
            "Title",
            '<a:off x="685800" y="838200"/><a:ext cx="7772400" cy="1143000"/>',
            [words["slides"][0][0]],
            4000,
        )
        + shape(
            3,
            "Body",
            '<a:off x="685800" y="2286000"/><a:ext cx="7772400" cy="2743200"/>',
            words["slides"][0][1],
            2000,
        )
        + "</p:spTree></p:cSld></p:sld>"
    )

    return {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.presentationml.slide+xml"/></Types>',
        "_rels/.rels": OOXML_RELS.format(type=WORD_MAIN, target="ppt/presentation.xml"),
        "ppt/_rels/presentation.xml.rels": OOXML_RELS.format(
            type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide",
            target="slides/slide1.xml",
        ),
        "ppt/presentation.xml": f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<p:presentation {presentation} xmlns:r="http://schemas.openxmlformats.org/'
        f'officeDocument/2006/relationships">'
        '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
        '<p:sldSz cx="9144000" cy="5143500"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>',
        "ppt/slides/slide1.xml": slide,
    }


# Helvetica's own character widths, in thousandths of the point size, so the pdf
# can be set the way a real one is: each word placed where it belongs rather
# than a whole line handed over as one run. It is also what lets the lines wrap
# where the text actually reaches the margin.
HELVETICA = {
    "regular": (
        "278 278 355 556 556 889 667 191 333 333 389 584 278 333 278 278 "
        "556 556 556 556 556 556 556 556 556 556 278 278 584 584 584 556 "
        "1015 667 667 722 722 667 611 778 722 278 500 667 556 833 722 778 "
        "667 778 722 667 611 722 667 944 667 667 611 278 278 278 469 556 "
        "333 556 556 500 556 556 278 556 556 222 222 500 222 833 556 556 "
        "556 556 333 500 278 556 500 722 500 500 500 334 260 334 584"
    ),
    "bold": (
        "278 333 474 556 556 889 722 238 333 333 389 584 278 333 278 278 "
        "556 556 556 556 556 556 556 556 556 556 333 333 584 584 584 611 "
        "975 722 722 722 722 667 611 778 722 278 556 722 611 833 722 778 "
        "667 778 722 667 611 722 667 944 667 667 611 333 278 333 584 556 "
        "333 556 611 556 611 556 333 611 611 278 278 556 278 889 611 611 "
        "611 611 389 556 333 611 556 778 556 556 500 389 280 389 584"
    ),
}

WIDTHS = {
    weight: {chr(32 + index): int(value) for index, value in enumerate(table.split())}
    for weight, table in HELVETICA.items()
}


def advance(text: str, weight: str, size: float) -> float:
    """How wide that text is set in Helvetica at that size.

    An accented letter is as wide as the letter it is built on - true across
    Helvetica's Latin range - so the table only has to hold the plain ones.
    """
    table = WIDTHS[weight]
    total = 0
    for character in text:
        width = table.get(character)
        if width is None:
            plain = unicodedata.normalize("NFD", character)[0]
            width = table.get(plain, 556)
        total += width

    return total * size / 1000


WINANSI = set(bytes(range(32, 256)).decode("cp1252", errors="ignore"))


def spellable(words: dict) -> bool:
    """Whether Helvetica's encoding can write this language's wording."""
    return all(
        character in WINANSI for line in (words["title"], words["closing"]) for character in line
    )


# A4 upright in points, with the same margin the ODF pages take.
PAGE = (595.0, 842.0)
MARGIN = 57.0
COLUMN = PAGE[0] - 2 * MARGIN


def pdf_bytes(words: dict, others: dict) -> bytes:
    """A one page PDF, written out by hand rather than through a library.

    Each word is placed at its own position, the way a real producer writes one.
    Handed over as one run per line instead, a reader that marks a search hit
    inside the run has nothing to measure the offset with, and the highlight
    lands beside the word rather than on it.

    Helvetica and WinAnsi, so what it says is Latin text only - the languages
    this cannot spell get the English wording, which is also what the search
    screenshot then looks for.
    """
    said = words if spellable(words) else WORDS["en"]

    def lay_out(text: str, weight: str, size: float) -> list:
        """The text broken into lines of placed words."""
        lines, line, width = [], [], 0.0
        space = advance(" ", weight, size)
        for word in text.split():
            reach = advance(word, weight, size)
            if line and width + space + reach > COLUMN:
                lines.append(line)
                line, width = [], 0.0
            line.append((word, width))
            width += reach + space
        if line:
            lines.append(line)

        return lines

    def literal(text: str) -> str:
        return text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")

    invoice = others["invoice"] if spellable(words) else OTHERS["en"]["invoice"]
    number, issued, due, billed, subtotal, vat, due_label, thanks, quantity, unit = invoice
    head, body, foot = table(said, columns=1, rows=20)

    money = foot[-1]
    tax = round(money * 0.2)
    right = PAGE[0] - MARGIN

    drawn = []

    def put(text, x, y, weight="regular", size=10, align="left"):
        """One line, placed. Numbers are hung off the right, which is what makes
        a column of figures a column rather than a ragged list."""
        name = "F2" if weight == "bold" else "F1"
        at = x - advance(text, weight, size) if align == "right" else x
        drawn.append(f"BT /{name} {size:g} Tf {at:.1f} {y:.1f} Td ({literal(text)}) Tj ET")

    # the head: who it is from and when, against who it is to
    y = PAGE[1] - MARGIN - 26
    put(number, MARGIN, y, "bold", 20)
    put(issued, right, y, "regular", 10, "right")
    put(due, right, y - 14, "regular", 10, "right")

    y -= 46
    put(billed, MARGIN, y, "bold", 11)
    for line in ("Muster GmbH", "Praterstrasse 12", "1020 Wien"):
        y -= 14
        put(line, MARGIN, y)

    # the table, in four columns across the width
    columns = (MARGIN, MARGIN + 300, MARGIN + 390, right)
    y -= 34
    put(head[0], columns[0], y, "bold", 10)
    put(quantity, columns[1], y, "bold", 10, "right")
    put(unit, columns[2], y, "bold", 10, "right")
    put(head[-1], columns[3], y, "bold", 10, "right")

    for index, line in enumerate(body):
        count = index % 4 + 1
        amount = line[-1]
        y -= 15
        put(str(line[0]), columns[0], y)
        put(str(count), columns[1], y, align="right")
        put(f"{amount / count:.2f}", columns[2], y, align="right")
        put(str(amount), columns[3], y, align="right")

    y -= 24
    for label, value, weight in (
        (subtotal, money, "regular"), (vat, tax, "regular"), (due_label, money + tax, "bold")
    ):
        put(label, columns[2], y, weight, 10 if weight == "regular" else 12, "right")
        put(str(value), columns[3], y, weight, 10 if weight == "regular" else 12, "right")
        y -= 17

    y -= 12
    put(thanks, MARGIN, y)

    stream = ("\n".join(drawn) + "\n").encode("cp1252")

    objects = [
        b"<</Type/Catalog/Pages 2 0 R>>",
        b"<</Type/Pages/Kids[3 0 R]/Count 1>>",
        b"<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]"
        b"/Resources<</Font<</F1 4 0 R/F2 6 0 R>>>>/Contents 5 0 R>>",
        b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding>>",
        b"<</Length " + str(len(stream)).encode() + b">>\nstream\n" + stream + b"endstream",
        b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold/Encoding/WinAnsiEncoding>>",
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"

    table_at = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode() + b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += f"trailer\n<</Size {len(objects) + 1}/Root 1 0 R>>\nstartxref\n{table_at}\n%%EOF\n".encode()

    return bytes(out)


def csv_text(words: dict, others: dict) -> str:
    """The contact list its name promises."""
    headers, roles = others["contacts"]
    lines = [",".join(headers)]
    for index, person in enumerate(PEOPLE):
        handle = person.split(". ")[-1].lower()
        lines.append(
            ",".join([person, roles[index % len(roles)], f"{handle}@example.org", f"+43 1 234 56{index}0"])
        )

    return "\n".join(lines) + "\n"


def txt_text(words: dict) -> str:
    """The notes: the report in plain text, with the deck's points under it."""
    lines = [words["title"], "=" * len(words["title"]), "", words["lead"], ""]
    for heading, paragraphs in words["sections"]:
        lines += [heading, "-" * len(heading), ""]
        for text in paragraphs:
            lines += [text, ""]
    for title, bullets in words["slides"]:
        lines += [title, "-" * len(title), ""]
        lines += [f"* {point}" for point in bullets]
        lines.append("")
    lines.append(words["closing"])

    return "\n".join(lines) + "\n"


# What the app asks the bundle for. The first three are the documents the
# screenshots open; the rest sit in the folder the first screenshot is of.
DOCUMENTS = {
    "text": ("odt", "application/vnd.oasis.opendocument.text", "document", report),
    "sheet": ("ods", "application/vnd.oasis.opendocument.spreadsheet", "document", sheet),
    "slides": ("odp", "application/vnd.oasis.opendocument.presentation", "slide", deck),
}

PACKAGES = {
    "word": ("docx", docx_parts),
    "cells": ("xlsx", xlsx_parts),
    "deck": ("pptx", pptx_parts),
}

PLAIN = {
    "rows": ("csv", csv_text),
    "notes": ("txt", txt_text),
}


def package(path: Path, parts: dict) -> None:
    """A zip of the given parts, reproducibly."""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, text in parts.items():
            info = zipfile.ZipInfo(name, date_time=EPOCH)
            info.external_attr = 0o644 << 16
            archive.writestr(info, text, compress_type=zipfile.ZIP_DEFLATED)


def write(path: Path, mimetype: str, kind: str, content_xml: str) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as package:
        def entry(name: str, text: str, stored: bool = False) -> None:
            info = zipfile.ZipInfo(name, date_time=EPOCH)
            info.external_attr = 0o644 << 16
            package.writestr(
                info, text, compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
            )

        # first and uncompressed, or the package is only recognised by sniffing
        entry("mimetype", mimetype, stored=True)
        entry("META-INF/manifest.xml", MANIFEST.format(mimetype=mimetype))
        entry("styles.xml", styles(kind))
        entry("content.xml", content_xml)


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description="Write the documents the store screenshots open.")
    parser.add_argument(
        "--language", action="append", choices=sorted(WORDS),
        help="only this language, repeatable; default is all of them. What to reach for when a "
             "change is worded in English first and the rest are to follow.")
    args = parser.parse_args(argv)

    languages = args.language or list(WORDS)

    SAMPLES.mkdir(parents=True, exist_ok=True)

    written = 0
    for language in languages:
        words = WORDS[language]
        for name, (extension, mimetype, kind, build) in DOCUMENTS.items():
            path = SAMPLES / f"sample-{name}-{language}.{extension}"
            write(path, mimetype, kind, build(words))
            written += 1

        others = OTHERS[language]

        for name, (extension, build) in PACKAGES.items():
            parts = build(words, others) if name == "word" else build(words)
            package(SAMPLES / f"sample-{name}-{language}.{extension}", parts)
            written += 1

        for name, (extension, build) in PLAIN.items():
            text = build(words, others) if name == "rows" else build(words)
            (SAMPLES / f"sample-{name}-{language}.{extension}").write_text(text, encoding="utf-8")
            written += 1

        (SAMPLES / f"sample-paper-{language}.pdf").write_bytes(pdf_bytes(words, others))
        written += 1

    details = {
        language: {
            "files": FILE_NAMES[language]
            | {
                key: FILLER_NAMES.get(language, {}).get(key, FILLER_NAMES["en"][key])
                for key in FILLERS
            },
            "search": query(words),
        }
        for language, words in WORDS.items()
    }
    (SAMPLES / "screenshot-names.json").write_text(
        json.dumps(details, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8"
    )

    print(f"wrote {written} documents in {len(languages)} languages to {SAMPLES}")


if __name__ == "__main__":
    main()
