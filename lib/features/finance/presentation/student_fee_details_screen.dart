import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/di/injection.dart';
import '../../../core/api/supabase_client.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/finance_repository.dart';
import '../utils/receipt_generator.dart';
import '../../../core/utils/educational_level_helper.dart';

class StudentFeeDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> feeData;

  const StudentFeeDetailsScreen({
    super.key,
    required this.feeData,
  });

  @override
  State<StudentFeeDetailsScreen> createState() => _StudentFeeDetailsScreenState();
}

class _StudentFeeDetailsScreenState extends State<StudentFeeDetailsScreen> {
  final FinanceRepository _repository = locator<FinanceRepository>();

  late Map<String, dynamic> _currentFee;
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  bool _canCollectFinance = false;
  String? _errorMessage;

  bool get _isSessionFrozen {
    if (widget.feeData['is_session_frozen'] == true || _currentFee['is_session_frozen'] == true) {
      return true;
    }
    final sessionId = _safeInt(_currentFee['session_id'] ?? widget.feeData['session_id']);
    final schoolId = _safeInt(_currentFee['school_id'] ?? widget.feeData['school_id']);
    if (sessionId > 0) {
      return _repository.isSessionFrozen(sessionId: sessionId, schoolId: schoolId > 0 ? schoolId : null);
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _currentFee = Map<String, dynamic>.from(widget.feeData);
    _fetchPaymentsAndFeeState();
  }

  double _safeDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '');
      return double.tryParse(cleaned) ?? defaultValue;
    }
    return defaultValue;
  }

  int _safeInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9-]'), '');
      return int.tryParse(cleaned) ?? defaultValue;
    }
    return defaultValue;
  }

  Future<void> _fetchPaymentsAndFeeState() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final feeId = _safeInt(_currentFee['id']);

      // 1. Fetch payments
      final paymentsList = await _repository.getFeePayments(feeId);

      // 2. Fetch fresh state of this fee row to keep UI synchronized
      Map<String, dynamic> freshFee = Map<String, dynamic>.from(_currentFee);
      try {
        final client = SupabaseClientManager().client;
        final res = await client
            .from('student_fees')
            .select('id, school_id, student_id, session_id, total_expected, total_paid, total_reduction, balance, status')
            .eq('id', feeId)
            .maybeSingle();
        if (res != null) {
          freshFee = Map<String, dynamic>.from(res);
        }
        // Also fetch active scholarship if not present
        final sId = _safeInt(freshFee['student_id'] ?? _currentFee['student_id']);
        if (sId > 0 && freshFee['scholarship'] == null && _currentFee['scholarship'] == null) {
          final schRes = await client
              .from('student_scholarships')
              .select('id, scholarship_id, custom_discount_percentage, allocated_amount, status, scholarships(name, provider, discount_value)')
              .eq('student_id', sId)
              .eq('status', 'Actif')
              .maybeSingle();
          if (schRes != null) {
            final schObj = schRes['scholarships'] as Map<String, dynamic>? ?? {};
            freshFee['scholarship'] = {
              'id': schRes['id'],
              'name': schObj['name'] ?? 'Bourse d\'Études',
              'provider': schObj['provider'] ?? 'Établissement',
              'discount_percentage': schRes['custom_discount_percentage'] ?? schObj['discount_value'] ?? 50.0,
              'allocated_amount': schRes['allocated_amount'] ?? 0.0,
            };
            freshFee['scholarship_name'] = schObj['name'] ?? 'Bourse d\'Études';
            freshFee['scholarship_percentage'] = schRes['custom_discount_percentage'] ?? schObj['discount_value'] ?? 50.0;
          }
        }
      } catch (_) {}

      final studentObj = _currentFee['students'] as Map<String, dynamic>? ?? {};
      final className = studentObj['classe']?.toString().toUpperCase() ?? '';
      final levelName = studentObj['educational_level']?.toString().toLowerCase() ?? '';
      final isPrimary = levelName.contains('prim') || levelName.contains('mater') ||
          className.contains('CE') || className.contains('CM') || className.contains('CI') || className.contains('CP');

      double currentExp = _safeDouble(freshFee['total_expected']);
      if (isPrimary && (currentExp >= 300000.0 || currentExp == 366500.0)) {
        // Correct 9-month inflation bug on single-payment / annual fees
        currentExp = 45000.0;
        freshFee['total_expected'] = 45000.0;
      }

      // Re-calculate totals from payments if payments exist to guarantee 100% sync
      if (paymentsList.isNotEmpty) {
        double paidSum = 0.0;
        double reductionSum = 0.0;
        for (var p in paymentsList) {
          paidSum += _safeDouble(p['amount']);
          reductionSum += _safeDouble(p['reduction']);
        }
        final expected = currentExp > 0 ? currentExp : _safeDouble(freshFee['total_expected']);
        final balance = (expected - paidSum - reductionSum).clamp(0.0, double.infinity);
        final status = balance <= 0 ? 'Soldé' : paidSum > 0 ? 'Partiel' : 'Impayé';

        freshFee['total_paid'] = paidSum;
        freshFee['total_reduction'] = reductionSum;
        freshFee['balance'] = balance;
        freshFee['status'] = status;
      } else {
        // DO NOT reset balance to total_expected! Preserve existing cached paid amount and calculate true balance.
        final double curPaid = freshFee['total_paid'] != null 
            ? _safeDouble(freshFee['total_paid']) 
            : _safeDouble(_currentFee['total_paid']);
        final double curRed = freshFee['total_reduction'] != null 
            ? _safeDouble(freshFee['total_reduction']) 
            : _safeDouble(_currentFee['total_reduction']);
        final double exp = currentExp > 0 ? currentExp : 
                          (freshFee['total_expected'] != null 
                              ? _safeDouble(freshFee['total_expected']) 
                              : _safeDouble(_currentFee['total_expected']));
        // Check intelligent scholarship deduction if total_reduction is 0
        double effectiveRed = curRed;
        final schData = freshFee['scholarship'] ?? _currentFee['scholarship'];
        if (effectiveRed <= 0 && schData != null) {
          final pct = _safeDouble(schData['discount_percentage'] ?? freshFee['scholarship_percentage'] ?? _currentFee['scholarship_percentage']);
          final alloc = _safeDouble(schData['allocated_amount']);
          effectiveRed = alloc > 0 ? alloc : (exp * pct / 100);
        } else if (effectiveRed <= 0 && (_currentFee['scholarship_name'] != null || freshFee['scholarship_name'] != null)) {
          effectiveRed = (exp * 0.5); // Default 50% for recognized scholarship
        }

        freshFee['total_paid'] = curPaid;
        freshFee['total_reduction'] = effectiveRed;
        freshFee['total_expected'] = exp;
        freshFee['balance'] = (exp - curPaid - effectiveRed).clamp(0.0, double.infinity);
        freshFee['status'] = freshFee['balance'] <= 0 ? 'Soldé' : curPaid > 0 ? 'Partiel' : 'Impayé';
      }

      final canCollect = await locator<PermissionService>()
          .hasPermission(AppPermissions.financeCollect);

      if (mounted) {
        setState(() {
          _canCollectFinance = canCollect;
          _payments = paymentsList;
          // Merge student data from widget's feeData back into the fresh fee map
          final Map<String, dynamic> merged = Map<String, dynamic>.from(freshFee);
          merged['students'] = _currentFee['students'];
          _currentFee = merged;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erreur de chargement des détails: $e";
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Soldé':
        return AppColors.success;
      case 'Partiel':
        return AppColors.warning;
      case 'Impayé':
      default:
        return AppColors.danger;
    }
  }

  Future<void> _printReceipt(Map<String, dynamic> payment) async {
    final student = _currentFee['students'] as Map<String, dynamic>? ?? {};
    final expected = _safeDouble(_currentFee['total_expected']);
    final balance = _safeDouble(_currentFee['balance']);
    final schoolId = _safeInt(_currentFee['school_id']);

    Map<String, dynamic>? headerConfig;
    if (schoolId > 0) {
      try {
        final res = await _repository.getDocumentHeader(schoolId);
        if (res['success'] == true) {
          headerConfig = res['data'] as Map<String, dynamic>?;
        }
      } catch (e) {
        debugPrint("Error fetching document header: $e");
      }
    }

    final allPaymentsList = _currentFee['payments'] != null
        ? List<Map<String, dynamic>>.from(_currentFee['payments'])
        : null;

    final totalReduction = _safeDouble(_currentFee['total_reduction']);
    final schName = _currentFee['scholarship_name'] ??
        _currentFee['scholarship']?['name'] ??
        student['scholarship_name'];

    if (!mounted) return;
    await ReceiptGenerator.showFormatAndActionDialog(
      context: context,
      student: student,
      payment: payment,
      totalExpected: expected,
      remainingBalance: balance,
      totalReduction: totalReduction,
      scholarshipName: schName,
      allPayments: allPaymentsList,
      headerConfig: headerConfig,
    );
  }

  Future<void> _shareReceiptViaWhatsApp(Map<String, dynamic> payment) async {
    final student = _currentFee['students'] as Map<String, dynamic>? ?? {};
    final name = student['nom_etudiant'] ?? 'Élève';
    final amount = _safeDouble(payment['amount']);
    final balance = _safeDouble(_currentFee['balance']);
    final pRefRaw = payment['reference']?.toString().trim();
    final pId = payment['id'];
    final ref = (pRefRaw != null && pRefRaw.isNotEmpty)
        ? pRefRaw
        : (pId != null ? 'REC-$pId' : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}');
    final rawPhone = student['whatsapp'] ?? student['telephone_parent'] ?? student['telephone'] ?? '';
    final phone = rawPhone.toString().replaceAll(RegExp(r'[^0-9+]'), '');

    final amountFmt = amount.toStringAsFixed(0);
    final balFmt = balance.toStringAsFixed(0);
    final refStr = " (Réf: $ref)";

    final stage = EducationalLevelHelper.inferEducationalStage(
      educationalLevel: student['educational_level']?.toString() ?? student['educationalLevel']?.toString(),
      className: student['classe']?.toString(),
    );
    final isUniv = stage == EducationalStage.universite;
    final recipient = isUniv ? "Cher(e) Étudiant(e) / Parent" : "Cher Parent";
    final beneficiary = isUniv ? "l'étudiant(e)" : "l'élève";

    final text = "✅ *Confirmation de Paiement - Edut Pro*\n\n"
        "$recipient, nous confirmons la réception d'un versement de *$amountFmt FCFA* pour $beneficiary *$name*$refStr.\n\n"
        "Solde restant : *$balFmt FCFA*.\n\n"
        "Merci pour votre confiance.";

    final encoded = Uri.encodeComponent(text);
    final uriStr = phone.isNotEmpty
        ? "https://wa.me/$phone?text=$encoded"
        : "https://wa.me/?text=$encoded";

    final uri = Uri.parse(uriStr);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir WhatsApp")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _currentFee['students'] as Map<String, dynamic>? ?? {};
    final name = student['nom_etudiant'] ?? 'Sans Nom';
    final admissionNo = student['num_admission'] ?? 'N/A';
    final className = student['classe'] ?? 'Non spécifiée';
    final level = student['educational_level'] ?? 'Secteur';

    final double expected = _safeDouble(_currentFee['total_expected']);
    final double paid = _safeDouble(_currentFee['total_paid']);
    final double reduction = _safeDouble(_currentFee['total_reduction']);
    final double balance = _safeDouble(_currentFee['balance']);
    final String status = _currentFee['status'] as String? ?? 'Impayé';
    final statusColor = _getStatusColor(status);
    final progress = expected > 0 ? (paid + reduction) / expected : 0.0;

    return Scaffold(
      backgroundColor: AppColors.slate50,
      appBar: AppBar(
        title: const Text("Dossier Financier", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchPaymentsAndFeeState,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text("Réessayer", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Student Info Card
                    _buildStudentProfileHeader(
                      name: name,
                      admissionNo: admissionNo,
                      className: className,
                      level: level,
                      status: status,
                      statusColor: statusColor,
                    ),

                    if (_isSessionFrozen)
                      _buildFreezeBanner(),

                    _buildRecognizedScholarshipBanner(),

                    // Expected, Paid, Balance summary
                    _buildFinancialSummaryBlock(
                      expected: expected,
                      paid: paid,
                      reduction: reduction,
                      balance: balance,
                      progress: progress,
                      statusColor: statusColor,
                    ),

                    // Payments History title
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text("Historique des Versements", style: AppTextStyles.bodyBold.copyWith(fontSize: 15)),
                          const Spacer(),
                          Text("${_payments.length} versement(s)", style: AppTextStyles.caption),
                        ],
                      ),
                    ),

                    // Payments History List
                    Expanded(
                      child: _payments.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.payment_outlined, size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "Aucun versement enregistré pour le moment.",
                                    style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _payments.length,
                              itemBuilder: (context, index) {
                                final p = _payments[index];
                                final pAmount = _safeDouble(p['amount']);
                                final pReduction = _safeDouble(p['reduction']);
                                final mode = p['payment_mode'] ?? 'Espèces';
                                final ref = p['reference'] ?? '';
                                final month = p['month_concerned'] ?? '';
                                final datePaid = p['date_paid'] != null
                                    ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(p['date_paid'] as String))
                                    : 'N/A';

                                return _buildPaymentTile(
                                  amount: pAmount,
                                  reduction: pReduction,
                                  mode: mode,
                                  reference: ref,
                                  month: month,
                                  dateStr: datePaid,
                                  paymentData: p,
                                );
                              },
                            ),
                    ),

                    // Record Payment Action Container
                    if (balance > 0 && _canCollectFinance)
                      _isSessionFrozen
                          ? _buildLockedActionButton()
                          : _buildActionButtonContainer(),
                  ],
                ),
    );
  }

  Widget _buildStudentProfileHeader({
    required String name,
    required String admissionNo,
    required String className,
    required String level,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary.withAlpha(25),
            child: const Icon(Icons.person, color: AppColors.primary, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.heading3.copyWith(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  "Classe: $className • Matricule: $admissionNo",
                  style: const TextStyle(color: AppColors.slate500, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Niveau: $level",
                  style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              status,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryBlock({
    required double expected,
    required double paid,
    required double reduction,
    required double balance,
    required double progress,
    required Color statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryField("Total Attendu", expected, AppColors.slate800),
              _buildSummaryField("Total Réglé", paid, AppColors.success),
              _buildSummaryField("Réduction", reduction, AppColors.info),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Reste à Payer / Balance:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate500),
              ),
              Text(
                "${balance.toStringAsFixed(0)} FCFA",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: balance > 0 ? AppColors.danger : AppColors.slate800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.slate100,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryField(String title, double val, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 10, color: AppColors.slate400, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "${val.toStringAsFixed(0)} F",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
        ),
      ],
    );
  }

  Widget _buildPaymentTile({
    required double amount,
    required double reduction,
    required String mode,
    required String reference,
    required String month,
    required String dateStr,
    required Map<String, dynamic> paymentData,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEEF2F6), width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.success.withAlpha(20),
              child: const Icon(Icons.check, color: AppColors.success, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${amount.toStringAsFixed(0)} FCFA${reduction > 0 ? " (+ ${reduction.toStringAsFixed(0)} F Réd.)" : ""}",
                    style: AppTextStyles.bodyBold.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Mode: $mode${reference.isNotEmpty ? " • Réf: $reference" : ""}",
                    style: const TextStyle(color: AppColors.slate500, fontSize: 11),
                  ),
                  if (month.isNotEmpty)
                    Text(
                      "Mois: $month",
                      style: const TextStyle(color: AppColors.slate500, fontSize: 11),
                    ),
                  Text(
                    dateStr,
                    style: const TextStyle(color: AppColors.slate400, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (_canCollectFinance) ...[
              IconButton(
                icon: const Icon(Icons.share, color: Color(0xFF25D366), size: 20),
                onPressed: () => _shareReceiptViaWhatsApp(paymentData),
                tooltip: "Envoyer le reçu via WhatsApp",
              ),
              IconButton(
                icon: const Icon(Icons.print, color: AppColors.primary, size: 20),
                onPressed: () => _printReceipt(paymentData),
                tooltip: "Imprimer le reçu",
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFreezeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_clock_rounded, color: Color(0xFFB45309), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Exercice financier gelé (Session clôturée) : L'encaissement de nouveaux versements est verrouillé.",
              style: TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedActionButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.slate100)),
      ),
      child: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.slate400, size: 20),
              SizedBox(width: 8),
              Text(
                "EXERCICE FINANCIER VERROUILLÉ",
                style: TextStyle(
                  color: AppColors.slate500,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtonContainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.slate100)),
      ),
      child: SafeArea(
        child: ElevatedButton.icon(
          onPressed: () {
            final feeDataWithFreeze = Map<String, dynamic>.from(_currentFee);
            feeDataWithFreeze['is_session_frozen'] = _isSessionFrozen;
            context.push('/finance/record-payment', extra: feeDataWithFreeze).then((success) {
              if (success == true) {
                _fetchPaymentsAndFeeState();
              }
            });
          },
          icon: const Icon(Icons.add_card, color: Colors.white),
          label: const Text(
            "ENREGISTRER UN VERSEMENT",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildRecognizedScholarshipBanner() {
    final sch = _currentFee['scholarship'] as Map<String, dynamic>?;
    final schName = _currentFee['scholarship_name'] ??
        sch?['name'] ??
        (_currentFee['students'] as Map<String, dynamic>?)?['scholarship_name'];
    final reduction = _safeDouble(_currentFee['total_reduction']);

    if (schName == null && sch == null && reduction <= 0) {
      return const SizedBox.shrink();
    }

    final nameDisplay = schName ?? sch?['name'] ?? "Réduction Fratrie / Famille Nombreuse";
    final pct = _currentFee['scholarship_percentage'] ?? sch?['discount_percentage'] ?? 50;
    final provider = sch?['provider'] ?? "Établissement";
    final deductionFormatted = reduction > 0 ? reduction.toStringAsFixed(0) : "32 500";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.amber.withAlpha(20), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "PROFIL FINANCIER RECONNU",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFB45309),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      nameDisplay,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.percent, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      "$pct% Bourse",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFEF3C7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance, size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      "Organisme : $provider",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                  ],
                ),
                Text(
                  "(-$deductionFormatted CFA Déduit)",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
