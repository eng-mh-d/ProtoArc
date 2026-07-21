#!/usr/bin/env python3
"""Build ProtoArc_T1_Plus_Developer_Guide.pdf (English + Arabic) from embedded content."""
from pathlib import Path

import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
)

DIR = Path(__file__).resolve().parent
FONT_PATH = DIR / "fonts" / "NotoSansArabic-Regular.ttf"
OUT_PDF = DIR / "ProtoArc_T1_Plus_Developer_Guide.pdf"


def ar(text: str) -> str:
    """Shape Arabic for PDF (ReportLab LTR canvas)."""
    shaped = arabic_reshaper.reshape(text)
    return get_display(shaped)


def main() -> None:
    if not FONT_PATH.is_file():
        raise SystemExit(f"Missing font: {FONT_PATH}\nRun from repo: curl -fsSL -o docs/fonts/NotoSansArabic-Regular.ttf ...")

    pdfmetrics.registerFont(TTFont("NotoArabic", str(FONT_PATH)))

    doc = SimpleDocTemplate(
        str(OUT_PDF),
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
    )

    en_body = ParagraphStyle(
        "en_body",
        fontName="Helvetica",
        fontSize=10,
        leading=14,
        alignment=TA_LEFT,
    )
    en_h1 = ParagraphStyle("en_h1", parent=en_body, fontName="Helvetica-Bold", fontSize=18, leading=22, spaceAfter=8)
    en_h2 = ParagraphStyle("en_h2", parent=en_body, fontName="Helvetica-Bold", fontSize=13, leading=16, spaceBefore=12, spaceAfter=6)
    en_mono = ParagraphStyle("en_mono", parent=en_body, fontName="Courier", fontSize=8.5, leading=11)

    ar_body = ParagraphStyle(
        "ar_body",
        fontName="NotoArabic",
        fontSize=11,
        leading=16,
        alignment=TA_RIGHT,
    )
    ar_h1 = ParagraphStyle("ar_h1", parent=ar_body, fontSize=16, leading=20, spaceAfter=8)
    ar_h2 = ParagraphStyle("ar_h2", parent=ar_body, fontSize=12.5, leading=17, spaceBefore=10, spaceAfter=5)

    story: list = []

    # ----- English -----
    story.append(Paragraph("ProtoArc T1 Plus — Developer &amp; Study Guide", en_h1))
    story.append(Paragraph("<i>English section</i>", en_body))
    story.append(Spacer(1, 6))

    story.append(Paragraph("1. Overview", en_h2))
    story.append(
        Paragraph(
            "This macOS SwiftUI app drives the <b>ProtoArc T1 Plus</b> Bluetooth touchpad from "
            "<b>user space</b> (no DriverKit, no SIP changes). It uses <font name='Courier'>IOHIDManager</font> "
            "to match Vendor ID 1256 (0x04E8) and Product ID 28705 (0x7021), reads raw HID digitizer reports, "
            "parses them into <font name='Courier'>TouchFrame</font>, runs a gesture state machine, and posts "
            "<font name='Courier'>CGEvent</font> for pointer, clicks, scroll, and system shortcuts.",
            en_body,
        )
    )

    story.append(Paragraph("2. Architecture (data flow)", en_h2))
    story.append(
        Paragraph(
            "<font name='Courier'>Bluetooth HID &rarr; IOHIDManager (HIDRunLoop thread)<br/>"
            "&nbsp;&nbsp;&darr; report callback<br/>"
            "TouchpadController &rarr; ReportParser &rarr; TouchFrame<br/>"
            "GestureEngine &rarr; EventSynthesizer &rarr; CGEvent<br/>"
            "SwiftUI on main: MenuBarExtra, Settings, TouchpadUIState</font>",
            en_mono,
        )
    )

    story.append(Paragraph("3. How to build", en_h2))
    story.append(
        Paragraph(
            "Open <font name='Courier'>ProtoArc T1 Plus.xcodeproj</font> in Xcode 26+, select scheme "
            "<b>ProtoArc T1 Plus</b>, press <b>&#8984;R</b> to run or <b>&#8984;B</b> to build. "
            "Command line:",
            en_body,
        )
    )
    story.append(
        Paragraph(
            "<font name='Courier'>xcodebuild -project \"ProtoArc T1 Plus.xcodeproj\" \\<br/>"
            "&nbsp;&nbsp;-scheme \"ProtoArc T1 Plus\" -configuration Debug build</font>",
            en_mono,
        )
    )
    story.append(
        Paragraph(
            "On first launch: grant <b>Input Monitoring</b> and <b>Accessibility</b>; activate a serial from "
            "<font name='Courier'>SerialNumbers.txt</font>; pair the touchpad; press <b>Start Driver</b>.",
            en_body,
        )
    )

    story.append(Paragraph("4. Permissions &amp; licensing", en_h2))
    story.append(
        Paragraph(
            "The app target is not sandboxed (HID + event injection). <font name='Courier'>SerialManager</font> "
            "loads weekly (7 days from activation) and permanent serials from the bundled "
            "<font name='Courier'>SerialNumbers.txt</font>.",
            en_body,
        )
    )

    story.append(Paragraph("5. Source files (study map)", en_h2))
    rows = [
        ["File", "Purpose"],
        ["ProtoArc_T1_PlusApp.swift", "@main SwiftUI: controller, MenuBarExtra, windows"],
        ["AppDelegate.swift", "Accessory app policy, startup, unstick pointer"],
        ["MenuBarView.swift", "Menu UI, AppStartup (auto-start, login item sync)"],
        ["ContentView.swift", "Settings UI, live touch panel, toggles"],
        ["LicenseView.swift", "Serial activation UI"],
        ["TouchpadController.swift", "IOHIDManager lifecycle, HID thread, parser + engine"],
        ["HIDRunLoop.swift", "Dedicated CFRunLoop for HID callbacks"],
        ["ReportParser.swift", "Bytes → TouchFrame, ReportLayout"],
        ["GestureEngine.swift", "Gestures, taps, scroll, swipes, timing windows"],
        ["EventSynthesizer.swift", "CGEvent posting (thread-safe lock)"],
        ["TouchModels.swift", "DeviceIDs, TouchFrame, TouchpadSettings"],
        ["TouchpadUIState.swift", "Throttled live display + raw log"],
        ["Permissions.swift", "AX + Input Monitoring checks"],
        ["LaunchAtLogin.swift", "SMAppService login item"],
        ["SerialManager.swift", "License validation"],
        ["SerialNumbers.txt", "Allowed serial catalog"],
        ["TouchpadManager.swift", "Reference / notes (not main HID path)"],
    ]
    t = Table(rows, colWidths=[52 * mm, 118 * mm])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
                ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    story.append(t)
    story.append(Spacer(1, 6))
    story.append(
        Paragraph(
            "<b>Note:</b> DriverKit files at repo root (<font name='Courier'>ProtoArcTouchpadDriver.*</font>) "
            "are reference only — not linked into this app target. See README.md for HID report byte layout.",
            en_body,
        )
    )

    story.append(Paragraph("6. Suggested study order", en_h2))
    story.append(
        Paragraph(
            "README.md &rarr; TouchModels.swift &rarr; ReportParser.swift &rarr; GestureEngine.swift &rarr; "
            "EventSynthesizer.swift &rarr; TouchpadController + HIDRunLoop &rarr; SwiftUI files.",
            en_body,
        )
    )

    story.append(PageBreak())

    # ----- Arabic -----
    story.append(Paragraph(ar("بروتوأرك T1 بلس — دليل المطور والدراسة"), ar_h1))
    story.append(Paragraph(ar("القسم العربي"), ar_body))
    story.append(Spacer(1, 8))

    story.append(Paragraph(ar("١. نظرة عامة"), ar_h2))
    story.append(
        Paragraph(
            ar(
                "تطبيق SwiftUI على macOS يشغّل لوحة ProtoArc T1 Plus عبر مساحة المستخدم باستخدام "
                "IOHIDManager لمطابقة الجهاز، ثم تحليل تقارير HID الخام إلى TouchFrame، ثم GestureEngine "
                "لإصدار أحداث CGEvent للمؤشر والنقر والتمرير واختصارات النظام."
            ),
            ar_body,
        )
    )

    story.append(Paragraph(ar("٢. البنية وتدفق البيانات"), ar_h2))
    story.append(
        Paragraph(
            ar(
                "بلوتوث HID إلى IOHIDManager على خيط HIDRunLoop، ثم TouchpadController يستدعي ReportParser "
                "ثم GestureEngine ثم EventSynthesizer. واجهة SwiftUI على الخيط الرئيسي للعرض والإعدادات."
            ),
            ar_body,
        )
    )

    story.append(Paragraph(ar("٣. البناء والتشغيل"), ar_h2))
    story.append(
        Paragraph(
            ar(
                "افتح ملف المشروع في Xcode 26 أو أحدث، اختر المخطط ProtoArc T1 Plus، اضغط تشغيل أو بناء. "
                "يمكن استخدام xcodebuild من الطرفية كما في القسم الإنجليزي."
            ),
            ar_body,
        )
    )
    story.append(
        Paragraph(
            ar(
                "عند أول تشغيل: امنح أذونات مراقبة الإدخال وإمكانية الوصول، فعّل رقمًا تسلسليًا من "
                "SerialNumbers.txt، اربط اللوحة، ثم ابدأ السائق من شريط القوائم أو الإعدادات."
            ),
            ar_body,
        )
    )

    story.append(Paragraph(ar("٤. الأذونات والترخيص"), ar_h2))
    story.append(
        Paragraph(
            ar(
                "التطبيق يحتاج قراءة HID وحقن الأحداث؛ SerialManager يحمّل الأرقام المسموحة من الملف "
                "المرفق مع الحزمة (أسبوعي أو دائم)."
            ),
            ar_body,
        )
    )

    story.append(Paragraph(ar("٥. ملفات المصدر"), ar_h2))
    rows_ar = [
        [ar("الملف"), ar("الوظيفة")],
        ["ProtoArc_T1_PlusApp.swift", ar("نقطة الدخول والنوافذ")],
        ["AppDelegate.swift", ar("سياسة التطبيق وبدء التشغيل")],
        ["MenuBarView.swift", ar("قائمة شريط القوائم")],
        ["ContentView.swift", ar("نافذة الإعدادات واللوحة الحية")],
        ["LicenseView.swift", ar("تفعيل الترخيص")],
        ["TouchpadController.swift", ar("إدارة IOHIDManager والخيوط")],
        ["HIDRunLoop.swift", ar("حلقة تشغيل HID خلفية")],
        ["ReportParser.swift", ar("تحليل التقارير")],
        ["GestureEngine.swift", ar("منطق الإيماءات")],
        ["EventSynthesizer.swift", ar("إرسال CGEvent")],
        ["TouchModels.swift", ar("النماذج والإعدادات")],
        ["TouchpadUIState.swift", ar("حالة واجهة العرض")],
        ["Permissions.swift", ar("الأذونات")],
        ["LaunchAtLogin.swift", ar("التشغيل عند الدخول")],
        ["SerialManager.swift", ar("التحقق من الترخيص")],
        ["SerialNumbers.txt", ar("قائمة الأرقام")],
        ["TouchpadManager.swift", ar("مرجعية — ليس المسار الرئيسي")],
    ]
    # Table with Arabic headers — use reshaped cells
    ta = Table(rows_ar, colWidths=[55 * mm, 115 * mm])
    ta.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
                ("FONTNAME", (0, 0), (-1, -1), "NotoArabic"),
                ("FONTSIZE", (0, 0), (-1, -1), 8.5),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(ta)

    story.append(Spacer(1, 8))
    story.append(Paragraph(ar("٦. ترتيب الدراسة المقترح"), ar_h2))
    story.append(
        Paragraph(
            ar(
                "README ثم TouchModels ثم ReportParser ثم GestureEngine ثم EventSynthesizer ثم "
                "TouchpadController و HIDRunLoop ثم ملفات SwiftUI."
            ),
            ar_body,
        )
    )
    story.append(Spacer(1, 10))
    story.append(
        Paragraph(
            "<i>HTML version (print to PDF from Safari): ProtoArc_T1_Plus_Developer_Guide.html<br/>"
            "Regenerate this file: python3 docs/build_guide_pdf.py</i>",
            en_body,
        )
    )

    doc.build(story)
    print(f"Wrote {OUT_PDF}")


if __name__ == "__main__":
    main()
