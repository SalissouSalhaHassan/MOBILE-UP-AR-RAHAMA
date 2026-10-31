import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/educational_level_helper.dart';

class SmartBoursesPdfGenerator {
  static String formatCfa(num amount) {
    final formatter = NumberFormat('#,##0', 'fr_FR');
    return '${formatter.format(amount).replaceAll('\u00A0', ' ').replaceAll('\u202F', ' ')} FCFA';
  }

  /// Generate Official Scholarship Attestation PDF
  static Future<Uint8List> generateAttestationBoursePdf({
    required Map<String, dynamic> student,
    required Map<String, dynamic> scholarship,
    Map<String, dynamic>? headerConfig,
  }) async {
    final pdf = pw.Document();

    pw.Font amiriFont;
    pw.Font amiriBold;
    try {
      amiriFont = await PdfGoogleFonts.amiriRegular().timeout(const Duration(seconds: 2));
      amiriBold = await PdfGoogleFonts.amiriBold().timeout(const Duration(seconds: 2));
    } catch (_) {
      amiriFont = pw.Font.helvetica();
      amiriBold = pw.Font.helveticaBold();
    }

    final studentName = (student['nomEtudiant'] ?? student['nom_etudiant'] ?? student['name'] ?? 'Élève').toString();
    final matricule = (student['numAdmission'] ?? student['num_admission'] ?? student['matricule'] ?? '-').toString();
    final classe = (student['classe'] ?? '-').toString();
    final rawLevel = (student['educationalLevel'] ?? student['educational_level'] ?? '').toString();
    final stage = EducationalLevelHelper.inferEducationalStage(
      educationalLevel: rawLevel,
      className: classe,
    );
    final isUniv = stage == EducationalStage.universite;

    final resolvedHeader = EducationalLevelHelper.getActiveLevelHeaderConfig(
      headerConfig,
      targetLevel: rawLevel.isNotEmpty ? rawLevel : classe,
    );

    final country = resolvedHeader['country']?.toString() ?? 'RÉPUBLIQUE DU NIGER';
    final ministry = resolvedHeader['ministry']?.toString() ??
        EducationalLevelHelper.getDefaultMinistry(stage, isArabic: false);
    final school = resolvedHeader['schoolName']?.toString() ??
        (isUniv ? 'UNIVERSITÉ PRIVÉE AR-RAHAMA (U P AR-RAHAMA)' : 'GROUPE SCOLAIRE & UNIVERSITAIRE U P AR-RAHAMA');

    final schName = (scholarship['scholarshipName'] ?? scholarship['name'] ?? 'Bourse d\'Études').toString();
    final provider = (scholarship['scholarshipProvider'] ?? scholarship['provider'] ?? 'Direction Générale').toString();
    final discountVal = scholarship['customDiscountPercentage'] ?? scholarship['discountValue'] ?? 50;
    final allocated = num.tryParse(scholarship['allocatedAmount']?.toString() ?? '0') ?? 0;
    final decisionRef = scholarship['decisionReference']?.toString() ?? 'DEC-BRS-${DateTime.now().year}';
    final academicYear = scholarship['academicYear']?.toString() ?? '2025–2026';

    num gross = num.tryParse(student['totalExpected']?.toString() ?? '0') ?? 0;
    if (gross <= 0 && allocated > 0 && discountVal > 0) {
      gross = ((allocated * 100) / discountVal).round();
    }
    if (gross <= 0) gross = 700000;
    final finalAllocated = allocated > 0 ? allocated : ((gross * discountVal) / 100).round();
    final netToPay = (gross - finalAllocated).clamp(0, double.infinity);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          const darkNavy = PdfColor.fromInt(0xFF0F172A);
          const primaryIndigo = PdfColor.fromInt(0xFF4F46E5);
          const emeraldGreen = PdfColor.fromInt(0xFF059669);
          const lightBorder = PdfColor.fromInt(0xFFCBD5E1);

          return pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFD97706), width: 2),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Top Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(country, style: pw.TextStyle(font: amiriBold, fontSize: 9, color: darkNavy)),
                        pw.Text(ministry, style: pw.TextStyle(font: amiriFont, fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(school, style: pw.TextStyle(font: amiriBold, fontSize: 9, color: darkNavy)),
                        pw.Text(
                          isUniv ? 'SERVICE DE L\'INTENDANCE & DE LA SCOLARITÉ' : 'SERVICE INTENDANCE & COMPTABILITÉ',
                          style: pw.TextStyle(font: amiriFont, fontSize: 7.5, color: const PdfColor.fromInt(0xFFD97706)),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),

                // Main Title Banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: const pw.BoxDecoration(
                    color: darkNavy,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'ATTESTATION OFFICIELLE D\'ATTRIBUTION DE BOURSE D\'ÉTUDES',
                        style: pw.TextStyle(font: amiriBold, fontSize: 11.5, color: PdfColors.white, letterSpacing: 0.5),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Exonération Financière & Prise en Charge Pédagogique • Année $academicYear',
                        style: pw.TextStyle(font: amiriFont, fontSize: 8, color: const PdfColor.fromInt(0xFFFDE68A)),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 18),

                pw.Text(
                  'La Commission des Bourses et la Direction Financière attestent que :',
                  style: pw.TextStyle(font: amiriFont, fontSize: 9.5, color: darkNavy),
                ),
                pw.SizedBox(height: 10),

                // Student Identity Card
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF8FAFC),
                    border: pw.Border.all(color: lightBorder),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildInfoLine('Nom & Prénoms', studentName, amiriFont, amiriBold),
                            pw.SizedBox(height: 4),
                            _buildInfoLine('Filière & Classe', classe, amiriFont, amiriBold),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildInfoLine('N° Matricule / INE', matricule, amiriFont, amiriBold, valueColor: primaryIndigo),
                            pw.SizedBox(height: 4),
                            _buildInfoLine('Réf. Décision', decisionRef, amiriFont, amiriBold),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                pw.Text(
                  'Bénéficie d\'une bourse d\'études officielle et d\'une exonération financière pour son cursus :',
                  style: pw.TextStyle(font: amiriFont, fontSize: 9.5, color: darkNavy),
                ),
                pw.SizedBox(height: 10),

                // Scholarship Program Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFFFFBEB),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A), width: 1.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        schName.toUpperCase(),
                        style: pw.TextStyle(font: amiriBold, fontSize: 13, color: const PdfColor.fromInt(0xFFB45309)),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Organisme financeur : $provider',
                        style: pw.TextStyle(font: amiriBold, fontSize: 9, color: darkNavy),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Taux d\'Exonération : $discountVal % des Frais de Scolarité',
                        style: pw.TextStyle(font: amiriBold, fontSize: 10, color: darkNavy),
                      ),
                      pw.SizedBox(height: 14),

                      // Breakdown 3 Columns
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                        children: [
                          _buildFinancialBox('SCOLARITÉ BRUTE', formatCfa(gross), darkNavy, amiriFont, amiriBold),
                          _buildFinancialBox('DÉDUCTION BOURSE', '- ${formatCfa(finalAllocated)}', emeraldGreen, amiriFont, amiriBold),
                          _buildFinancialBox('NET À PAYER (ÉTUDIANT)', formatCfa(netToPay), primaryIndigo, amiriFont, amiriBold),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                pw.Text(
                  'La présente attestation est délivrée pour servir et valoir de prise en charge financière auprès des services académiques et comptables.',
                  style: pw.TextStyle(font: amiriFont, fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),

                pw.Spacer(),

                // Signatures & Stamp
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Fait le : ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: amiriFont, fontSize: 8)),
                        pw.SizedBox(height: 4),
                        pw.Text('Le Chef du Service de la Scolarité', style: pw.TextStyle(font: amiriBold, fontSize: 8.5, color: darkNavy)),
                        pw.SizedBox(height: 36),
                        pw.Text('[ Signature & Cachet ]', style: pw.TextStyle(font: amiriFont, fontSize: 7, color: PdfColors.grey600)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Pour la Direction Générale / Rectorat', style: pw.TextStyle(font: amiriBold, fontSize: 8.5, color: darkNavy)),
                        pw.SizedBox(height: 4),
                        pw.Text('L\'Agent Comptable Principal', style: pw.TextStyle(font: amiriFont, fontSize: 8, color: darkNavy)),
                        pw.SizedBox(height: 36),
                        pw.Text('[ Signature Autorisée ]', style: pw.TextStyle(font: amiriFont, fontSize: 7, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generate Payment Schedule (Échéancier) Report PDF
  static Future<Uint8List> generateScheduleReportPdf({
    required List<Map<String, dynamic>> schedules,
    Map<String, dynamic>? headerConfig,
    String? sessionName,
  }) async {
    final pdf = pw.Document();

    pw.Font amiriFont;
    pw.Font amiriBold;
    try {
      amiriFont = await PdfGoogleFonts.amiriRegular().timeout(const Duration(seconds: 2));
      amiriBold = await PdfGoogleFonts.amiriBold().timeout(const Duration(seconds: 2));
    } catch (_) {
      amiriFont = pw.Font.helvetica();
      amiriBold = pw.Font.helveticaBold();
    }

    final resolvedHeader = EducationalLevelHelper.getActiveLevelHeaderConfig(headerConfig);
    final school = resolvedHeader['schoolName']?.toString() ?? 'UNIVERSITÉ PRIVÉE AR-RAHAMA (U P AR-RAHAMA)';
    final year = sessionName ?? '2025–2026';

    num totalGross = 0;
    num totalDeduction = 0;
    num totalNet = 0;
    num totalPaid = 0;
    num totalBalance = 0;

    for (final s in schedules) {
      totalGross += num.tryParse(s['grossAmount']?.toString() ?? '0') ?? 0;
      totalDeduction += num.tryParse(s['scholarshipDeduction']?.toString() ?? '0') ?? 0;
      totalNet += num.tryParse(s['netAmount']?.toString() ?? '0') ?? 0;
      totalPaid += num.tryParse(s['paidAmount']?.toString() ?? '0') ?? 0;
      totalBalance += num.tryParse(s['balance']?.toString() ?? '0') ?? 0;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          const darkNavy = PdfColor.fromInt(0xFF0F172A);

          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(school, style: pw.TextStyle(font: amiriBold, fontSize: 11, color: darkNavy)),
                    pw.Text('PLANNING GLOBAL DES ÉCHÉANCIERS & RECOUVREMENT', style: pw.TextStyle(font: amiriBold, fontSize: 13, color: const PdfColor.fromInt(0xFF4F46E5))),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Session : $year', style: pw.TextStyle(font: amiriBold, fontSize: 9)),
                    pw.Text('Édité le : ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: pw.TextStyle(font: amiriFont, fontSize: 8)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Table of schedules
            pw.TableHelper.fromTextArray(
              headers: [
                'N°',
                'Étudiant / Matricule',
                'Classe',
                'Échéance',
                'Date Limite',
                'Montant Net',
                'Versé',
                'Reste Dû',
                'Statut',
              ],
              data: schedules.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final s = entry.value;
                final student = '${s['studentNom'] ?? '-'}\n(${s['studentMatricule'] ?? '-'})';
                final classe = s['studentClasse'] ?? '-';
                final label = s['label'] ?? 'Tranche';
                final dueDate = s['dueDate'] != null
                    ? DateFormat('dd/MM/yyyy').format(DateTime.parse(s['dueDate'].toString()))
                    : '-';
                final net = formatCfa(num.tryParse(s['netAmount']?.toString() ?? '0') ?? 0);
                final paid = formatCfa(num.tryParse(s['paidAmount']?.toString() ?? '0') ?? 0);
                final bal = formatCfa(num.tryParse(s['balance']?.toString() ?? '0') ?? 0);
                final status = s['status'] ?? 'À échoir';

                return [
                  '$idx',
                  student,
                  classe,
                  label,
                  dueDate,
                  net,
                  paid,
                  bal,
                  status,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(font: amiriBold, fontSize: 7.5, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: darkNavy),
              cellStyle: pw.TextStyle(font: amiriFont, fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.center,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 12),

            // Summary Footer
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF1F5F9),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL ÉCHÉANCES : ${schedules.length}', style: pw.TextStyle(font: amiriBold, fontSize: 8.5)),
                  pw.Text('TOTAL NET ATTENDU : ${formatCfa(totalNet)}', style: pw.TextStyle(font: amiriBold, fontSize: 8.5, color: darkNavy)),
                  pw.Text('TOTAL ENCAISSÉ : ${formatCfa(totalPaid)}', style: pw.TextStyle(font: amiriBold, fontSize: 8.5, color: const PdfColor.fromInt(0xFF059669))),
                  pw.Text('RESTE RECOUVREMENT : ${formatCfa(totalBalance)}', style: pw.TextStyle(font: amiriBold, fontSize: 8.5, color: const PdfColor.fromInt(0xFFDC2626))),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildInfoLine(String label, String value, pw.Font font, pw.Font boldFont, {PdfColor? valueColor}) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 85,
          child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
        ),
        pw.Text(': ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(font: boldFont, fontSize: 8.5, color: valueColor ?? const PdfColor.fromInt(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFinancialBox(String label, String val, PdfColor color, pw.Font font, pw.Font boldFont) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(val, style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: color)),
      ],
    );
  }

  static Future<void> printAttestationBourse({
    required Map<String, dynamic> student,
    required Map<String, dynamic> scholarship,
    Map<String, dynamic>? headerConfig,
  }) async {
    final bytes = await generateAttestationBoursePdf(
      student: student,
      scholarship: scholarship,
      headerConfig: headerConfig,
    );
    final name = (student['nomEtudiant'] ?? student['nom_etudiant'] ?? 'eleve').toString().replaceAll(' ', '_');
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'attestation_bourse_$name.pdf',
    );
  }

  static Future<void> shareAttestationBourse({
    required Map<String, dynamic> student,
    required Map<String, dynamic> scholarship,
    Map<String, dynamic>? headerConfig,
  }) async {
    final bytes = await generateAttestationBoursePdf(
      student: student,
      scholarship: scholarship,
      headerConfig: headerConfig,
    );
    final name = (student['nomEtudiant'] ?? student['nom_etudiant'] ?? 'eleve').toString().replaceAll(' ', '_');
    final fileName = 'attestation_bourse_$name.pdf';

    await SharePlus.instance.share(
      ShareParams(
        text: 'Attestation Officielle d\'Attribution de Bourse d\'Études - Edut Pro',
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
      ),
    );
  }

  static Future<void> printScheduleReport({
    required List<Map<String, dynamic>> schedules,
    Map<String, dynamic>? headerConfig,
    String? sessionName,
  }) async {
    final bytes = await generateScheduleReportPdf(
      schedules: schedules,
      headerConfig: headerConfig,
      sessionName: sessionName,
    );
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'echeancier_recouvrement_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static Future<void> shareScheduleReport({
    required List<Map<String, dynamic>> schedules,
    Map<String, dynamic>? headerConfig,
    String? sessionName,
  }) async {
    final bytes = await generateScheduleReportPdf(
      schedules: schedules,
      headerConfig: headerConfig,
      sessionName: sessionName,
    );
    final fileName = 'echeancier_recouvrement_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await SharePlus.instance.share(
      ShareParams(
        text: 'Rapport des Échéanciers et Recouvrement - Edut Pro',
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
      ),
    );
  }
}
