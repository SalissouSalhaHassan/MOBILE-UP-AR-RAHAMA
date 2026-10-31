import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/di/injection.dart';
import '../../../core/auth/session_manager.dart';
import '../data/finance_repository.dart';
import '../utils/smart_bourses_pdf_generator.dart';

class SmartBoursesEcheanciersScreen extends StatefulWidget {
  const SmartBoursesEcheanciersScreen({super.key});

  @override
  State<SmartBoursesEcheanciersScreen> createState() =>
      _SmartBoursesEcheanciersScreenState();
}

class _SmartBoursesEcheanciersScreenState
    extends State<SmartBoursesEcheanciersScreen>
    with SingleTickerProviderStateMixin {
  final FinanceRepository _financeRepo = locator<FinanceRepository>();
  final SessionManager _sessionManager = locator<SessionManager>();

  late TabController _tabController;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  Map<String, dynamic> _dashboardData = {};
  Map<String, dynamic>? _headerConfig;
  int _schoolId = 9;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sIdStr = await _sessionManager.getSchoolId();
      _schoolId = int.tryParse(sIdStr ?? '9') ?? 9;

      final results = await Future.wait([
        _financeRepo.getBoursesAndEcheanciersDashboard(schoolId: _schoolId),
        _financeRepo.getDocumentHeader(_schoolId).catchError((_) => {'success': false}),
      ]);

      final dashRes = results[0];
      final headerRes = results[1];

      if (mounted) {
        setState(() {
          if (dashRes['success'] == true && dashRes['data'] != null) {
            _dashboardData = Map<String, dynamic>.from(dashRes['data']);
          } else {
            _errorMessage = dashRes['error'] ?? "Impossible de charger les données.";
          }

          if (headerRes['success'] == true && headerRes['data'] != null) {
            _headerConfig = Map<String, dynamic>.from(headerRes['data']);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erreur de connexion : $e";
        });
      }
    }
  }

  Future<void> _handleBulkReminders() async {
    final schedules = List<Map<String, dynamic>>.from(_dashboardData['schedules'] ?? []);
    final overdue = schedules.where((s) => s['status'] == 'En retard' || ((s['balance'] as num? ?? 0) > 0)).toList();

    if (overdue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Aucune échéance en retard à relancer."),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Relance Intelligente Groupée", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("Souhaitez-vous déclencher la relance automatique pour les ${overdue.length} échéances en retard ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Relancer Tout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    final res = await _financeRepo.triggerBulkScheduleReminders();
    setState(() => _isProcessing = false);

    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Relance effectuée avec succès pour ${res['count'] ?? overdue.length} échéances !"),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? "Erreur lors de la relance groupée"),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
      }
    }
  }

  void _sendWhatsAppReminder(Map<String, dynamic> sched) async {
    final studentNom = sched['studentNom'] ?? 'Élève';
    final matricule = sched['studentMatricule'] ?? '-';
    final label = sched['label'] ?? 'Échéance';
    final bal = SmartBoursesPdfGenerator.formatCfa(num.tryParse(sched['balance']?.toString() ?? '0') ?? 0);
    final rawPhone = sched['studentWhatsapp'] ?? sched['studentMobile'] ?? '';
    final phone = rawPhone.toString().replaceAll(RegExp(r'[^0-9+]'), '');

    final text = "🔔 *Rappel d'Échéance de Paiement - UP/IAI*\n\n"
        "Bonjour, nous vous informons que le règlement de l'échéance *$label* d'un montant de *$bal* pour l'étudiant *$studentNom* ($matricule) est attendu.\n\n"
        "Merci de régulariser la situation auprès du service financier.";

    final uri = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(text)}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir WhatsApp.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Bourses & Échéanciers", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined, color: Color(0xFF4F46E5)),
            tooltip: "Imprimer Rapport des Échéanciers",
            onPressed: () {
              final scheds = List<Map<String, dynamic>>.from(_dashboardData['schedules'] ?? []);
              if (scheds.isNotEmpty) {
                SmartBoursesPdfGenerator.printScheduleReport(
                  schedules: scheds,
                  headerConfig: _headerConfig,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF059669)),
            tooltip: "Partager Rapport PDF",
            onPressed: () {
              final scheds = List<Map<String, dynamic>>.from(_dashboardData['schedules'] ?? []);
              if (scheds.isNotEmpty) {
                SmartBoursesPdfGenerator.shareScheduleReport(
                  schedules: scheds,
                  headerConfig: _headerConfig,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF4F46E5),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: "Boursiers Actifs"),
            Tab(text: "Échéanciers & Impayés"),
            Tab(text: "Programmes"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFE11D48)),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE11D48)), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                          child: const Text("Réessayer", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildKpiSummaryHeader(),
                    _buildSearchBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBoursiersTab(),
                          _buildEcheanciersTab(),
                          _buildProgrammesTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildKpiSummaryHeader() {
    final boursiersCount = _dashboardData['boursiersCount'] ?? 0;
    final totalAllocated = num.tryParse(_dashboardData['totalAllocatedBourses']?.toString() ?? '0') ?? 0;
    final totalOverdue = num.tryParse(_dashboardData['totalOverdueSchedules']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKpiCol("Boursiers Actifs", "$boursiersCount", const Color(0xFF38BDF8)),
              Container(width: 1, height: 35, color: Colors.white24),
              _buildKpiCol("Volume Alloué", SmartBoursesPdfGenerator.formatCfa(totalAllocated).replaceAll(' FCFA', ' F'), const Color(0xFF34D399)),
              Container(width: 1, height: 35, color: Colors.white24),
              _buildKpiCol("Impayés", SmartBoursesPdfGenerator.formatCfa(totalOverdue).replaceAll(' FCFA', ' F'), const Color(0xFFF87171)),
            ],
          ),
          if (totalOverdue > 0) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _isProcessing ? null : _handleBulkReminders,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48).withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE11D48).withAlpha(80)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.send_rounded, color: Color(0xFFF87171), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _isProcessing ? "Traitement de la relance..." : "Relance Automatique Tous les Impayés",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpiCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: "Rechercher un boursier, matricule, classe...",
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
    );
  }

  Widget _buildBoursiersTab() {
    final rawList = List<Map<String, dynamic>>.from(_dashboardData['allocations'] ?? []);
    final list = rawList.where((a) {
      if (_searchQuery.isEmpty) return true;
      final nom = (a['studentNom'] ?? '').toString().toLowerCase();
      final mat = (a['studentMatricule'] ?? '').toString().toLowerCase();
      final cls = (a['studentClasse'] ?? '').toString().toLowerCase();
      final bName = (a['scholarshipName'] ?? '').toString().toLowerCase();
      return nom.contains(_searchQuery) || mat.contains(_searchQuery) || cls.contains(_searchQuery) || bName.contains(_searchQuery);
    }).toList();

    if (list.isEmpty) {
      return const Center(
        child: Text("Aucun boursier actif trouvé.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final item = list[idx];
        final studentNom = item['studentNom'] ?? 'Élève';
        final matricule = item['studentMatricule'] ?? '-';
        final classe = item['studentClasse'] ?? '-';
        final schName = item['scholarshipName'] ?? 'Bourse';
        final discount = item['customDiscountPercentage'] ?? item['scholarshipDiscountValue'] ?? 50;
        final allocated = num.tryParse(item['allocatedAmount']?.toString() ?? '0') ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFFEF3C7),
                    child: const Icon(Icons.school_rounded, color: Color(0xFFD97706), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studentNom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                        Text("Matricule: $matricule • $classe", style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      "$discount% Bourse",
                      style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(schName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                        Text("Prise en charge: -${SmartBoursesPdfGenerator.formatCfa(allocated)}", style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5), size: 22),
                          tooltip: "Attestation Officielle PDF",
                          onPressed: () {
                            SmartBoursesPdfGenerator.printAttestationBourse(
                              student: item,
                              scholarship: item,
                              headerConfig: _headerConfig,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, color: Color(0xFF059669), size: 22),
                          tooltip: "Partager Attestation",
                          onPressed: () {
                            SmartBoursesPdfGenerator.shareAttestationBourse(
                              student: item,
                              scholarship: item,
                              headerConfig: _headerConfig,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEcheanciersTab() {
    final rawList = List<Map<String, dynamic>>.from(_dashboardData['schedules'] ?? []);
    final list = rawList.where((s) {
      if (_searchQuery.isEmpty) return true;
      final nom = (s['studentNom'] ?? '').toString().toLowerCase();
      final mat = (s['studentMatricule'] ?? '').toString().toLowerCase();
      final lbl = (s['label'] ?? '').toString().toLowerCase();
      return nom.contains(_searchQuery) || mat.contains(_searchQuery) || lbl.contains(_searchQuery);
    }).toList();

    if (list.isEmpty) {
      return const Center(
        child: Text("Aucune échéance enregistrée.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final sched = list[idx];
        final studentNom = sched['studentNom'] ?? 'Élève';
        final matricule = sched['studentMatricule'] ?? '-';
        final label = sched['label'] ?? 'Tranche';
        final dueDate = sched['dueDate'] != null
            ? DateFormat('dd/MM/yyyy').format(DateTime.parse(sched['dueDate'].toString()))
            : '-';
        final netAmount = num.tryParse(sched['netAmount']?.toString() ?? '0') ?? 0;
        final balance = num.tryParse(sched['balance']?.toString() ?? '0') ?? 0;
        final isOverdue = sched['status'] == 'En retard';
        final isPaid = sched['status'] == 'Payé' || balance == 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isOverdue ? const Color(0xFFFECDD3) : const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studentNom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                        Text("Matricule: $matricule • Date limite: $dueDate", style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPaid ? const Color(0xFFECFDF5) : (isOverdue ? const Color(0xFFFFF1F2) : const Color(0xFFEFF6FF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      sched['status'] ?? 'À échoir',
                      style: TextStyle(
                        color: isPaid ? const Color(0xFF059669) : (isOverdue ? const Color(0xFFE11D48) : const Color(0xFF2563EB)),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
                      Text("Net: ${SmartBoursesPdfGenerator.formatCfa(netAmount)}", style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Reste Dû", style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                      Text(
                        SmartBoursesPdfGenerator.formatCfa(balance),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: balance > 0 ? const Color(0xFFE11D48) : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (balance > 0) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF86EFAC)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text("WhatsApp", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => _sendWhatsAppReminder(sched),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgrammesTab() {
    final programs = List<Map<String, dynamic>>.from(_dashboardData['scholarships'] ?? []);
    if (programs.isEmpty) {
      return const Center(
        child: Text("Aucun programme de bourse configuré.", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: programs.length,
      itemBuilder: (ctx, idx) {
        final p = programs[idx];
        final name = p['name'] ?? 'Programme';
        final provider = p['provider'] ?? 'Établissement';
        final discount = p['discountValue'] ?? 50;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_membership_rounded, color: Color(0xFF4F46E5), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    const SizedBox(height: 2),
                    Text(provider, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$discount %",
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF059669), fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

