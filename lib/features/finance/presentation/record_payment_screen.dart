import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/finance_repository.dart';
import '../utils/receipt_generator.dart';

class RecordPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> feeData;

  const RecordPaymentScreen({
    super.key,
    required this.feeData,
  });

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final FinanceRepository _repository = locator<FinanceRepository>();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reductionController = TextEditingController(text: '0');
  final TextEditingController _referenceController = TextEditingController();

  String _paymentMode = 'Espèces';
  String _monthConcerned = 'Général';
  bool _isSaving = false;
  bool _canCollectFinance = false;

  late double _expected;
  late double _paid;
  late double _reduction;
  late double _balance;
  late int _feeId;
  late int _schoolId;

  final List<String> _paymentModes = [
    'Espèces',
    'MyNita (Nita Transfert)',
    'AmanaTa Transfert',
    'Al-Izza Transfert',
    'Airtel Money',
    'Moov Money (Flooz)',
    'Zamani Cash',
    'Mobile Money',
    'Virement',
    'Chèque',
    'Carte Bancaire',
  ];

  final List<String> _months = [
    'Général',
    'Frais d\'inscription',
    'Frais COGES & Carte ID',
    'Frais Transport & Internat',
    '1er Trimestre',
    '2ème Trimestre',
    '3ème Trimestre',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
  ];

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

  @override
  void initState() {
    super.initState();
    _feeId = _safeInt(widget.feeData['id']);
    _schoolId = _safeInt(widget.feeData['school_id']);
    _expected = _safeDouble(widget.feeData['total_expected']);
    _paid = _safeDouble(widget.feeData['total_paid']);
    _reduction = _safeDouble(widget.feeData['total_reduction']);
    final rawBalance = _safeDouble(widget.feeData['balance']);
    // Safety check: If _paid > 0 and rawBalance == _expected, compute the true remaining balance
    if (_paid > 0 && (_expected - rawBalance).abs() < 0.01) {
      _balance = (_expected - _paid - _reduction).clamp(0.0, double.infinity);
    } else {
      _balance = rawBalance;
    }
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final canCollect = await locator<PermissionService>()
        .hasPermission(AppPermissions.financeCollect);
    if (!mounted) return;
    setState(() {
      _canCollectFinance = canCollect;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reductionController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  double get _currentAmountInput => double.tryParse(_amountController.text) ?? 0.0;
  double get _currentReductionInput => double.tryParse(_reductionController.text) ?? 0.0;
  double get _newBalance => _balance - _currentAmountInput - _currentReductionInput;

  bool get _isSessionFrozen {
    if (widget.feeData['is_session_frozen'] == true) {
      return true;
    }
    final sessionId = _safeInt(widget.feeData['session_id'] ?? widget.feeData['sessionId']);
    final schoolId = _safeInt(widget.feeData['school_id'] ?? widget.feeData['schoolId']);
    if (sessionId > 0) {
      return _repository.isSessionFrozen(sessionId: sessionId, schoolId: schoolId > 0 ? schoolId : null);
    }
    return false;
  }

  Future<void> _handleSave() async {
    if (_isSessionFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible d'enregistrer : cette année scolaire est clôturée ou verrouillée. Les opérations financières y sont gelées."),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final double amount = _currentAmountInput;
    final double reduction = _currentReductionInput;

    if (amount + reduction > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Le montant total (Versement + Réduction) dépasse le solde restant."),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final session = locator<SessionManager>();
      final email = await session.getEmail() ?? 'Admin';
      final recordedBy = email.split('@').first.toUpperCase();

      final student = widget.feeData['students'] as Map<String, dynamic>? ?? {};
      final admissionNum = student['num_admission'] ?? student['matricule'] ?? student['id'] ?? '';
      final admissionClean = admissionNum.toString().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final defaultRef = 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}${admissionClean.isNotEmpty ? "-$admissionClean" : ""}';
      final referenceToSend = _referenceController.text.trim().isNotEmpty
          ? _referenceController.text.trim()
          : defaultRef;

      int? studentIdVal = _safeInt(student['id']);
      if (studentIdVal == 0) {
        studentIdVal = _safeInt(widget.feeData['student_id']);
      }
      if (studentIdVal == 0) {
        studentIdVal = _safeInt(widget.feeData['studentId']);
      }
      final effectiveStudentId = studentIdVal > 0 ? studentIdVal : null;

      final res = await _repository.recordPayment(
        feeId: _feeId,
        studentId: effectiveStudentId,
        schoolId: _schoolId,
        amount: amount,
        reduction: reduction,
        paymentMode: _paymentMode,
        reference: referenceToSend,
        monthConcerned: _monthConcerned,
        recordedBy: recordedBy,
        currentPaid: _paid,
        currentReduction: _reduction,
        totalExpected: _expected,
        studentName: student['nom_etudiant'] ?? student['nomPrenom'] ?? student['name'] ?? 'Élève',
        numAdmission: admissionNum.toString(),
        classe: student['classe']?.toString(),
        educationalLevel: student['educational_level']?.toString() ?? student['educationalLevel']?.toString() ?? student['niveau']?.toString(),
        section: student['section']?.toString(),
        filiere: student['filiere']?.toString(),
        sessionId: _safeInt(widget.feeData['session_id']) > 0
            ? _safeInt(widget.feeData['session_id'])
            : (_safeInt(widget.feeData['sessionId']) > 0 ? _safeInt(widget.feeData['sessionId']) : null),
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        if (res['success'] == true) {
          final isOffline = res['isOffline'] == true || res['queued'] == true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? "Versement enregistré hors-ligne avec succès ! Réf: ${res['reference'] ?? referenceToSend}"
                    : "Versement enregistré avec succès ! Préparation du reçu...",
              ),
              backgroundColor: AppColors.success,
            ),
          );

          Map<String, dynamic>? headerConfig;
          try {
            final headerRes = await _repository.getDocumentHeader(_schoolId);
            if (headerRes['success'] == true) {
              headerConfig = headerRes['data'] as Map<String, dynamic>?;
            }
          } catch (e) {
            debugPrint("Error fetching document header: $e");
          }

          final paymentData = res['payment'] as Map<String, dynamic>? ?? {};
          final resolvedRef = res['reference']?.toString().isNotEmpty == true
              ? res['reference'].toString()
              : (paymentData['reference']?.toString().isNotEmpty == true
                  ? paymentData['reference'].toString()
                  : referenceToSend);
          final resolvedId = res['paymentId'] ?? paymentData['id'] ?? DateTime.now().millisecondsSinceEpoch;

          final paymentRecord = {
            'id': resolvedId,
            'amount': amount,
            'reduction': reduction,
            'payment_mode': _paymentMode,
            'reference': resolvedRef,
            'month_concerned': _monthConcerned,
            'date_paid': paymentData['date_paid'] ?? DateTime.now().toIso8601String(),
            'recorded_by': recordedBy,
          };

          // Automatically pop up official receipt dialog (Print / Share / WhatsApp)
          try {
            await ReceiptGenerator.showFormatAndActionDialog(
              context: context,
              student: {
                ...student,
                'nom_etudiant': student['nom_etudiant'] ?? student['nomPrenom'] ?? 'Élève',
                'num_admission': student['num_admission'] ?? student['matricule'] ?? '-',
                'classe': student['classe'] ?? '-',
                'educational_level': student['educational_level'] ?? student['educationalLevel'] ?? student['niveau'],
              },
              payment: paymentRecord,
              totalExpected: _expected,
              remainingBalance: _newBalance,
              totalReduction: _reduction + reduction,
              scholarshipName: widget.feeData['scholarship_name'] ??
                  widget.feeData['scholarship']?['name'] ??
                  student['scholarship_name'],
              headerConfig: headerConfig,
            );
          } catch (e) {
            debugPrint("Error showing receipt dialog: $e");
          }

          if (mounted) {
            Navigator.pop(context, true); // Returns true to trigger refresh in caller screen
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['error'] ?? "Une erreur est survenue lors de la sauvegarde."),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur: $e"),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.feeData['students'] as Map<String, dynamic>? ?? {};
    final studentName = student['nom_etudiant'] ?? 'Sans Nom';
    final admissionNo = student['num_admission'] ?? 'N/A';
    final className = student['classe'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.slate50,
      appBar: AppBar(
        title: const Text("Enregistrer un Versement", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: !_canCollectFinance
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Vous n avez pas la permission d enregistrer un versement.',
                  textAlign: TextAlign.center,
                ),
              )
            : Form(
                key: _formKey,
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isSessionFrozen) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          "Exercice financier gelé (Année scolaire clôturée) : L'enregistrement de nouveaux versements est verrouillé.",
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Student Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEEF2F6), width: 1.5),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primaryLight,
                      child: const Icon(Icons.person, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(studentName, style: AppTextStyles.bodyBold.copyWith(fontSize: 14)),
                          Text(
                            "Matricule: $admissionNo • $className",
                            style: const TextStyle(color: AppColors.slate500, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Live Balance Display Box
              _buildLiveBalanceWidget(),
              const SizedBox(height: 24),

              // Input: Amount
              Text("Montant versé (FCFA)", style: AppTextStyles.bodyBold.copyWith(fontSize: 13, color: AppColors.slate700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: "Saisir le montant...",
                  prefixIcon: Icon(Icons.monetization_on, color: AppColors.primary),
                ),
                onChanged: (v) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Le montant est obligatoire.";
                  }
                  final val = double.tryParse(value);
                  if (val == null || val <= 0) {
                    return "Veuillez entrer un montant valide supérieur à 0.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Input: Reduction
              Text("Réduction accordée (FCFA)", style: AppTextStyles.bodyBold.copyWith(fontSize: 13, color: AppColors.slate700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _reductionController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: "Saisir la réduction (facultatif)...",
                  prefixIcon: Icon(Icons.card_giftcard, color: AppColors.primary),
                ),
                onChanged: (v) => setState(() {}),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final val = double.tryParse(value);
                    if (val == null || val < 0) {
                      return "Veuillez entrer une réduction valide positive.";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Dropdown: Payment Mode
              Text("Mode de Paiement", style: AppTextStyles.bodyBold.copyWith(fontSize: 13, color: AppColors.slate700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _paymentMode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.credit_card, color: AppColors.primary),
                ),
                items: _paymentModes.map((mode) {
                  return DropdownMenuItem<String>(
                    value: mode,
                    child: Text(mode, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _paymentMode = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              // Dropdown: Month concerned
              Text("Mois / Session concerné", style: AppTextStyles.bodyBold.copyWith(fontSize: 13, color: AppColors.slate700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _monthConcerned,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_month, color: AppColors.primary),
                ),
                items: _months.map((m) {
                  return DropdownMenuItem<String>(
                    value: m,
                    child: Text(
                      m,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _monthConcerned = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              // Input: Reference
              Text("Référence / N° de pièce", style: AppTextStyles.bodyBold.copyWith(fontSize: 13, color: AppColors.slate700)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  hintText: "N° chèque, virement ou transaction Mobile Money...",
                  prefixIcon: Icon(Icons.bookmark_border, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 30),

              // Save Button
              ElevatedButton(
                onPressed: _isSaving || !_canCollectFinance || _isSessionFrozen ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSessionFrozen ? AppColors.slate400 : AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSessionFrozen) ...[
                            const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _isSessionFrozen
                                ? "EXERCICE FINANCIER VERROUILLÉ"
                                : "VALIDER LE VERSEMENT",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBalanceWidget() {
    final double remaining = _newBalance;
    final bool isOverpaid = remaining < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOverpaid ? AppColors.danger.withAlpha(20) : AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOverpaid ? AppColors.danger.withAlpha(50) : AppColors.primary.withAlpha(50),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Solde initial:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.slate500)),
              Text("${_balance.toStringAsFixed(0)} F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.slate800)),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white70),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isOverpaid ? "Excédent (Non autorisé):" : "Nouveau Solde Reste à Payer:",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: isOverpaid ? AppColors.danger : AppColors.primary,
                ),
              ),
              Text(
                "${remaining.abs().toStringAsFixed(0)} F",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isOverpaid ? AppColors.danger : AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
