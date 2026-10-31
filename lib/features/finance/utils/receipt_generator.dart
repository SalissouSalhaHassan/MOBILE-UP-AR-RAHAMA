import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/educational_level_helper.dart';

class ReceiptGenerator {
  static Future<Uint8List> generatePdfBytes({
    required Map<String, dynamic> student,
    required Map<String, dynamic> payment,
    required double totalExpected,
    required double remainingBalance,
    double totalReduction = 0.0,
    String? scholarshipName,
    List<Map<String, dynamic>>? allPayments,
    Map<String, dynamic>? headerConfig,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
  }) async {
    final pdf = pw.Document();
    final isA5 = pageFormat == PdfPageFormat.a5;

    // Load custom fonts to support Arabic/Unicode text with offline fallback
    pw.Font amiriFont;
    pw.Font amiriBold;
    try {
      amiriFont = await PdfGoogleFonts.amiriRegular().timeout(const Duration(seconds: 2));
      amiriBold = await PdfGoogleFonts.amiriBold().timeout(const Duration(seconds: 2));
    } catch (_) {
      amiriFont = pw.Font.helvetica();
      amiriBold = pw.Font.helveticaBold();
    }

    final studentName = student['nom_etudiant'] ?? student['name'] ?? 'Élève';
    final admissionNo = student['num_admission'] ?? student['matricule'] ?? '—';
    final className = student['classe'] ?? student['className'] ?? '—';
    final rawLevel = student['educational_level']?.toString() ??
        student['educationalLevel']?.toString() ??
        student['niveau']?.toString() ??
        '';
    final schoolYear = student['session_name'] ?? student['school_year'] ?? '2024–2025';

    final stage = EducationalLevelHelper.inferEducationalStage(
      educationalLevel: rawLevel,
      className: className,
      sectionName: student['section']?.toString(),
      filiere: student['filiere']?.toString(),
    );

    // Resolve matching level profile from headerConfig
    final resolvedHeader = EducationalLevelHelper.getActiveLevelHeaderConfig(
      headerConfig,
      targetLevel: rawLevel.isNotEmpty ? rawLevel : className,
    );

    final pRefRaw = payment['reference']?.toString().trim();
    final paymentId = payment['id'];
    final receiptRef = (pRefRaw != null && pRefRaw.isNotEmpty)
        ? pRefRaw
        : (paymentId != null
            ? 'REC-$paymentId'
            : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}');

    double _safeNum(dynamic v, [double d = 0.0]) {
      if (v == null) return d;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? d;
      return d;
    }

    final effectiveReduction = totalReduction > 0
        ? totalReduction
        : _safeNum(student['total_reduction'] ?? payment['reduction'] ?? student['reduction']);
    final effectiveScholarshipName = scholarshipName ??
        student['scholarship_name'] ??
        student['scholarship']?['name'] ??
        student['scholarship']?['scholarshipName'] ??
        payment['scholarship_name'];

    final totalPaid = (totalExpected - effectiveReduction - remainingBalance) > 0
        ? (totalExpected - effectiveReduction - remainingBalance)
        : _safeNum(payment['amount']);
    final isSolde = remainingBalance <= 0;

    final datePaidStr = payment['date_paid'] != null
        ? DateFormat('dd/MM/yyyy')
            .format(DateTime.parse(payment['date_paid'].toString()))
        : DateFormat('dd/MM/yyyy').format(DateTime.now());

    // Prepare payments list for the History table
    final paymentsList = (allPayments != null && allPayments.isNotEmpty)
        ? allPayments
        : [payment];

    // Decode logos
    pw.MemoryImage? centerLogoImage;
    final logoSource = resolvedHeader['centerLogo'] ??
        resolvedHeader['leftLogo'] ??
        resolvedHeader['customLogo'] ??
        resolvedHeader['logoPath'] ??
        headerConfig?['centerLogo'] ??
        headerConfig?['leftLogo'] ??
        headerConfig?['logoPath'];
    if (logoSource != null && logoSource.toString().startsWith('data:image/')) {
      try {
        final base64Str = logoSource.toString().split(',').last;
        centerLogoImage = pw.MemoryImage(base64.decode(base64Str));
      } catch (e) {
        debugPrint("Error decoding receipt logo: $e");
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(isA5 ? 16 : 26),
        build: (context) {
          const darkNavy = PdfColor.fromInt(0xFF0F172A);
          const primaryIndigo = PdfColor.fromInt(0xFF4F46E5);
          const emeraldGreen = PdfColor.fromInt(0xFF10B981);
          const royalBlue = PdfColor.fromInt(0xFF2563EB);
          const greyColor = PdfColor.fromInt(0xFF64748B);
          const lightBorder = PdfColor.fromInt(0xFFE2E8F0);
          const lightBg = PdfColor.fromInt(0xFFF8FAFC);

          // 1. Header layout (level-aware)
          final country = resolvedHeader['country']?.toString() ?? 'RÉPUBLIQUE DU NIGER';
          final ministry = resolvedHeader['ministry']?.toString() ??
              EducationalLevelHelper.getDefaultMinistry(stage, isArabic: false);
          final school = resolvedHeader['schoolName']?.toString() ??
              (stage == EducationalStage.universite ? 'UNIVERSITÉ EXCELLENCE' : 'ÉCOLE EXCELLENCE');
          final service = resolvedHeader['service']?.toString() ??
              EducationalLevelHelper.getDefaultService(stage, isArabic: false);
          final phone = resolvedHeader['phone']?.toString() ??
              resolvedHeader['schoolPhone']?.toString() ??
              '+227 90 12 34 56';
          final email = resolvedHeader['email']?.toString() ??
              resolvedHeader['schoolEmail']?.toString() ??
              'contact@edutacademy.ne';

          final countryAr = resolvedHeader['countryAr']?.toString() ?? 'جمهورية النيجر';
          final ministryAr = resolvedHeader['ministryAr']?.toString() ??
              EducationalLevelHelper.getDefaultMinistry(stage, isArabic: true);
          final schoolAr = resolvedHeader['schoolNameAr']?.toString() ?? school;
          final serviceAr = resolvedHeader['serviceAr']?.toString() ??
              EducationalLevelHelper.getDefaultService(stage, isArabic: true);
          final phoneAr = resolvedHeader['phoneAr']?.toString() ??
              resolvedHeader['schoolPhoneAr']?.toString() ??
              'الهاتف: 56 34 12 90 227+';
          final emailAr = resolvedHeader['emailAr']?.toString() ??
              resolvedHeader['schoolEmailAr']?.toString() ??
              'البريد: contact@edutacademy.ne';

          final receiptTitle = EducationalLevelHelper.getReceiptTitle(stage);
          final receiptSubtitle = EducationalLevelHelper.getReceiptSubtitle(stage);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Top Header Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left French
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(country, style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6.5 : 8, color: darkNavy)),
                        pw.Text(ministry, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 7, color: greyColor)),
                        pw.SizedBox(height: 1),
                        pw.Text(school, style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 7 : 8.5, color: darkNavy)),
                        if (service.isNotEmpty) pw.Text(service, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                        pw.Text('Tél: $phone', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                        pw.Text('Email: $email', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                      ],
                    ),
                  ),

                  // Center Logo
                  if (centerLogoImage != null)
                    pw.Container(
                      margin: pw.EdgeInsets.symmetric(horizontal: isA5 ? 6 : 10),
                      width: isA5 ? 36 : 46,
                      height: isA5 ? 36 : 46,
                      child: pw.Image(centerLogoImage),
                    )
                  else
                    pw.Container(width: isA5 ? 36 : 46, height: isA5 ? 36 : 46),

                  // Right Arabic
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(countryAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6.5 : 8, color: darkNavy)),
                        pw.Text(ministryAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 7, color: greyColor)),
                        pw.SizedBox(height: 1),
                        pw.Text(schoolAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 7 : 8.5, color: darkNavy)),
                        if (serviceAr.isNotEmpty) pw.Text(serviceAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                        pw.Text(phoneAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                        pw.Text(emailAr, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5.5 : 6.5, color: greyColor)),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: isA5 ? 6 : 8),

              // Title Banner: Stage-Aware REÇU DE PAIEMENT + ORIGINAL Badge
              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 8 : 12, vertical: isA5 ? 5 : 7),
                decoration: const pw.BoxDecoration(
                  color: darkNavy,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          receiptTitle,
                          style: pw.TextStyle(
                            font: amiriBold,
                            fontSize: isA5 ? 9.5 : 11.5,
                            color: PdfColors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.Text(
                          receiptSubtitle,
                          style: pw.TextStyle(
                            font: amiriFont,
                            fontSize: isA5 ? 5.5 : 6.5,
                            color: const PdfColor.fromInt(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 8 : 10, vertical: isA5 ? 2 : 3),
                      decoration: const pw.BoxDecoration(
                        color: royalBlue,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
                      ),
                      child: pw.Text(
                        'ORIGINAL',
                        style: pw.TextStyle(
                          font: amiriBold,
                          fontSize: isA5 ? 6 : 7.5,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: isA5 ? 4 : 6),

              // Reference Badge
              pw.Center(
                child: pw.Container(
                  padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 16 : 22, vertical: isA5 ? 2.5 : 4),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF1F5FF),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFC8D2FF)),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'RÉFÉRENCE : $receiptRef',
                    style: pw.TextStyle(
                      font: amiriBold,
                      fontSize: isA5 ? 7 : 8.5,
                      color: primaryIndigo,
                    ),
                  ),
                ),
              ),

              pw.SizedBox(height: isA5 ? 6 : 8),

              // Student Info + Date & Financial Situation (2 Cards side by side)
              pw.Container(
                padding: pw.EdgeInsets.all(isA5 ? 8 : 10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: lightBorder),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left Column: Student Info
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            EducationalLevelHelper.getReceiptStudentSectionTitle(stage),
                            style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6.5 : 7.5, color: primaryIndigo),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            studentName,
                            style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 9.5 : 11, color: darkNavy),
                          ),
                          pw.SizedBox(height: 3),
                          _buildDetailRow(EducationalLevelHelper.getReceiptClassLabel(stage), className, amiriFont, amiriBold, isA5: isA5),
                          pw.SizedBox(height: 1.5),
                          _buildDetailRow('Matricule', admissionNo, amiriFont, amiriBold, isA5: isA5),
                          pw.SizedBox(height: 1.5),
                          _buildDetailRow(EducationalLevelHelper.getReceiptYearLabel(stage), schoolYear, amiriFont, amiriBold, isA5: isA5),
                        ],
                      ),
                    ),

                    // Divider
                    pw.Container(
                      width: 1,
                      height: isA5 ? 58 : 68,
                      color: lightBorder,
                      margin: pw.EdgeInsets.symmetric(horizontal: isA5 ? 6 : 10),
                    ),

                    // Right Column: Date du reçu & Situation Financière
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'DATE DU REÇU',
                            style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6.5 : 7.5, color: emeraldGreen),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            datePaidStr,
                            style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 9.5 : 11, color: darkNavy),
                          ),
                          pw.SizedBox(height: 3),
                          _buildDetailRow(
                            effectiveReduction > 0 ? 'Scolarit\u00e9 Brute' : EducationalLevelHelper.getReceiptExpectedFeeLabel(stage),
                            _formatCfa(totalExpected),
                            amiriFont,
                            amiriBold,
                            isA5: isA5,
                          ),
                          if (effectiveReduction > 0) ...[
                            pw.SizedBox(height: 1.5),
                            _buildDetailRow(
                              effectiveScholarshipName != null && effectiveScholarshipName.isNotEmpty
                                  ? 'Bourse ($effectiveScholarshipName)'
                                  : 'Bourse / D\u00e9duction',
                              '-${_formatCfa(effectiveReduction)}',
                              amiriFont,
                              amiriBold,
                              isA5: isA5,
                              valueColor: emeraldGreen,
                            ),
                          ],
                          pw.SizedBox(height: 1.5),
                          _buildDetailRow('Total D\u00e9j\u00e0 Pay\u00e9', _formatCfa(totalPaid), amiriFont, amiriBold, isA5: isA5),pw.SizedBox(height: 2.5),
                          pw.Container(
                            padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 5 : 8, vertical: isA5 ? 2 : 3),
                            decoration: const pw.BoxDecoration(
                              color: royalBlue,
                              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('SOLDE RESTANT', style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6 : 7.5, color: PdfColors.white)),
                                pw.Text(_formatCfa(remainingBalance), style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6.5 : 8, color: PdfColors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: isA5 ? 6 : 8),

              // Table: HISTORIQUE DES VERSEMENTS (6 Columns)
              pw.TableHelper.fromTextArray(
                headers: [
                  'N°',
                  'Date de Paiement',
                  'Référence Paiement',
                  'Mode de Paiement',
                  'Montant (CFA)',
                  'Reçu par',
                ],
                data: paymentsList.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final p = entry.value;
                  final pId = p['id'] ?? idx;
                  final pDate = p['date_paid'] != null
                      ? DateFormat('dd/MM/yyyy').format(DateTime.parse(p['date_paid'].toString()))
                      : datePaidStr;
                  final pRef = (p['reference'] != null && p['reference'].toString().trim().isNotEmpty)
                      ? p['reference'].toString().trim()
                      : 'PAY-${pId.toString().padLeft(6, '0')}';
                  final pMode = p['payment_mode'] ?? 'Espèces';
                  final pAmount = _safeNum(p['amount']);
                  final pRec = p['recorded_by'] ?? 'Admin Scolarité';
                  return [
                    '$idx',
                    pDate,
                    pRef,
                    pMode,
                    _formatCfa(pAmount).replaceAll(' CFA', ''),
                    pRec,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  font: amiriBold,
                  fontSize: isA5 ? 6.5 : 7.5,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: darkNavy),
                cellStyle: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 6 : 7.5),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                },
                headerAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                },
                cellPadding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 4 : 6, vertical: isA5 ? 3 : 4),
              ),

              // Table Footer Row: Total Versé
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: lightBorder),
                  color: lightBg,
                ),
                padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 8 : 10, vertical: isA5 ? 3.5 : 5),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL VERSÉ', style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 7 : 8.5, color: darkNavy)),
                    pw.Text(_formatCfa(totalPaid), style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 7.5 : 9, color: darkNavy)),
                  ],
                ),
              ),

              pw.SizedBox(height: isA5 ? 8 : 10),

              // Footer: 3 Cards (Certification | Stamp | QR Code)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Left Card: Certification
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      height: isA5 ? 64 : 76,
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: lightBorder),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('CERTIFICATION OFFICIELLE', style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6 : 7, color: emeraldGreen)),
                          pw.Text('Quittance conforme émise par le système automatisé de l\'établissement.', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: darkNavy)),
                          pw.Text('Opérateur : ${payment['recorded_by'] ?? 'Agent Caisse'}', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: greyColor)),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(width: 8),

                  // Middle Card: Stamp Box
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      height: isA5 ? 64 : 76,
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: lightBorder),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text('CACHE DU SERVICE FINANCIER', style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 5.5 : 6.5, color: darkNavy)),
                          pw.SizedBox(height: 4),
                          pw.Text('[ Cachet et Signature Électronique ]', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 4.5 : 5.5, color: greyColor)),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(width: 8),

                  // Right Card: QR Code
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      height: isA5 ? 64 : 76,
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: lightBorder),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: '$receiptRef|$studentName|$className|${_formatCfa(totalPaid)}|${_formatCfa(remainingBalance)}',
                            width: isA5 ? 38 : 46,
                            height: isA5 ? 38 : 46,
                          ),
                          pw.SizedBox(width: 6),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              children: [
                                pw.Text('Scannez pour vérifier l\'authenticité', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: greyColor)),
                                pw.SizedBox(height: 2),
                                pw.Text(receiptRef, style: pw.TextStyle(font: amiriBold, fontSize: isA5 ? 6 : 7, color: royalBlue)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: isA5 ? 6 : 8),

              // Security & Legal Footer
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Émis le : $datePaidStr', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: greyColor)),
                  pw.Text('Ce reçu est généré électroniquement et ne nécessite pas de signature manuscrite.', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: greyColor)),
                  pw.Text('Merci pour votre confiance. $school', style: pw.TextStyle(font: amiriFont, fontSize: isA5 ? 5 : 6, color: greyColor)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> showFormatAndActionDialog({
    required BuildContext context,
    required Map<String, dynamic> student,
    required Map<String, dynamic> payment,
    required double totalExpected,
    required double remainingBalance,
    double totalReduction = 0.0,
    String? scholarshipName,
    List<Map<String, dynamic>>? allPayments,
    Map<String, dynamic>? headerConfig,
  }) async {
    final resolvedPayment = Map<String, dynamic>.from(payment);
    final pRefRaw = resolvedPayment['reference']?.toString().trim();
    final pId = resolvedPayment['id'];
    final displayRef = (pRefRaw != null && pRefRaw.isNotEmpty)
        ? pRefRaw
        : (pId != null ? 'REC-$pId' : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}');
    resolvedPayment['reference'] = displayRef;

    PdfPageFormat selectedFormat = PdfPageFormat.a5;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Exporter / Imprimer le Reçu',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'N° Quittance : $displayRef',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Format du papier :',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(
                            child: Text('A5 — Reçu standard (Défaut)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          selected: selectedFormat == PdfPageFormat.a5,
                          selectedColor: const Color(0xFF4F46E5),
                          labelStyle: TextStyle(
                            color: selectedFormat == PdfPageFormat.a5 ? Colors.white : const Color(0xFF1E293B),
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedFormat = PdfPageFormat.a5);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(
                            child: Text('A4 — Reçu détaillé', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          selected: selectedFormat == PdfPageFormat.a4,
                          selectedColor: const Color(0xFF4F46E5),
                          labelStyle: TextStyle(
                            color: selectedFormat == PdfPageFormat.a4 ? Colors.white : const Color(0xFF1E293B),
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedFormat = PdfPageFormat.a4);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Imprimer', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await generateAndPrint(
                              student: student,
                              payment: resolvedPayment,
                              totalExpected: totalExpected,
                              remainingBalance: remainingBalance,
                              totalReduction: totalReduction,
                              scholarshipName: scholarshipName,
                              allPayments: allPayments,
                              headerConfig: headerConfig,
                              pageFormat: selectedFormat,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4F46E5),
                            side: const BorderSide(color: Color(0xFFC8D2FF)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Partager', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await generateAndShare(
                              student: student,
                              payment: resolvedPayment,
                              totalExpected: totalExpected,
                              remainingBalance: remainingBalance,
                              totalReduction: totalReduction,
                              scholarshipName: scholarshipName,
                              allPayments: allPayments,
                              headerConfig: headerConfig,
                              pageFormat: selectedFormat,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> generateAndPrint({
    required Map<String, dynamic> student,
    required Map<String, dynamic> payment,
    required double totalExpected,
    required double remainingBalance,
    double totalReduction = 0.0,
    String? scholarshipName,
    List<Map<String, dynamic>>? allPayments,
    Map<String, dynamic>? headerConfig,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
  }) async {
    final pRefRaw = payment['reference']?.toString().trim();
    final paymentId = payment['id'];
    final receiptRef = (pRefRaw != null && pRefRaw.isNotEmpty)
        ? pRefRaw
        : (paymentId != null ? 'REC-$paymentId' : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}');

    final bytes = await generatePdfBytes(
      student: student,
      payment: payment,
      totalExpected: totalExpected,
      remainingBalance: remainingBalance,
      totalReduction: totalReduction,
      scholarshipName: scholarshipName,
      allPayments: allPayments,
      headerConfig: headerConfig,
      pageFormat: pageFormat,
    );

    final rawLevel = student['educational_level']?.toString() ??
        student['educationalLevel']?.toString() ??
        student['niveau']?.toString() ??
        '';
    final className = student['classe'] ?? student['className'] ?? '';
    final stage = EducationalLevelHelper.inferEducationalStage(
      educationalLevel: rawLevel,
      className: className,
    );
    final prefix = stage == EducationalStage.universite ? 'recu_universitaire' : 'recu_scolaire';

    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: '${prefix}_$receiptRef.pdf',
    );
  }

  static Future<void> generateAndShare({
    required Map<String, dynamic> student,
    required Map<String, dynamic> payment,
    required double totalExpected,
    required double remainingBalance,
    double totalReduction = 0.0,
    String? scholarshipName,
    List<Map<String, dynamic>>? allPayments,
    Map<String, dynamic>? headerConfig,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
  }) async {
    final pRefRaw = payment['reference']?.toString().trim();
    final paymentId = payment['id'];
    final receiptRef = (pRefRaw != null && pRefRaw.isNotEmpty)
        ? pRefRaw
        : (paymentId != null ? 'REC-$paymentId' : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}');

    final bytes = await generatePdfBytes(
      student: student,
      payment: payment,
      totalExpected: totalExpected,
      remainingBalance: remainingBalance,
      totalReduction: totalReduction,
      scholarshipName: scholarshipName,
      allPayments: allPayments,
      headerConfig: headerConfig,
      pageFormat: pageFormat,
    );

    final rawLevel = student['educational_level']?.toString() ??
        student['educationalLevel']?.toString() ??
        student['niveau']?.toString() ??
        '';
    final className = student['classe'] ?? student['className'] ?? '';
    final stage = EducationalLevelHelper.inferEducationalStage(
      educationalLevel: rawLevel,
      className: className,
    );
    final isUniv = stage == EducationalStage.universite;
    final prefix = isUniv ? 'recu_universitaire' : 'recu_scolaire';
    final shareText = isUniv
        ? 'Reçu officiel de paiement des droits universitaires'
        : 'Reçu officiel de paiement des frais scolaires';

    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: '${prefix}_$receiptRef.pdf',
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDetailRow(
    String label,
    String value,
    pw.Font font,
    pw.Font boldFont, {
    bool isA5 = false,
    PdfColor? valueColor,
  }) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: isA5 ? 68 : 80,
          child: pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: isA5 ? 5.5 : 7, color: const PdfColor.fromInt(0xFF64748B)),
          ),
        ),
        pw.Text(': ', style: pw.TextStyle(font: font, fontSize: isA5 ? 5.5 : 7, color: const PdfColor.fromInt(0xFF94A3B8))),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: isA5 ? 6 : 7.5,
              color: valueColor ?? const PdfColor.fromInt(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatCfa(double amount) {
    final formatter = NumberFormat('#,##0', 'fr_FR');
    return '${formatter.format(amount).replaceAll('\u00A0', ' ').replaceAll('\u202F', ' ')} CFA';
  }
}
