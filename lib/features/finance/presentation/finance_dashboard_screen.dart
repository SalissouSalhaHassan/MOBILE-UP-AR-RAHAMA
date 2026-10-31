import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/educational_level_helper.dart';
import '../data/finance_repository.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  final FinanceRepository _repository = locator<FinanceRepository>();

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _canCollectFinance = false;
  String? _errorMessage;
  String? _userEducationalLevel;

  int _schoolId = 1;
  int? _selectedSessionId;
  String _selectedSessionName = '';

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _fees = [];
  List<Map<String, dynamic>> _filteredFees = [];

  Map<String, dynamic> _stats = {
    'totalExpected': 0.0,
    'totalCollected': 0.0,
    'totalDebts': 0.0,
  };

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'Tous'; // 'Tous' | 'Impayé' | 'Partiel' | 'Soldé'

  bool get _isSessionFrozen {
    if (_selectedSessionId == null) return false;
    final current = _sessions.firstWhere(
      (s) => (s['id'] as num?)?.toInt() == _selectedSessionId,
      orElse: () => {},
    );
    if (current.isEmpty) return false;
    final status = current['status']?.toString().toLowerCase().trim() ?? '';
    final isActive = current['is_active'] == true;
    return !isActive ||
        status == 'clôturé' ||
        status == 'cloture' ||
        status == 'verrouillé' ||
        status == 'verrouille' ||
        status == 'archivé' ||
        status == 'archive';
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sessionManager = locator<SessionManager>();
      final schoolIdStr = await sessionManager.getSchoolId();
      _schoolId = int.tryParse(schoolIdStr ?? '') ?? 1;
      _canCollectFinance = await locator<PermissionService>()
          .hasPermission(AppPermissions.financeCollect);
      _userEducationalLevel = await sessionManager.getEducationalLevel();

      // Fetch school sessions
      _sessions = await _repository.getSessions(_schoolId);

      if (_sessions.isNotEmpty) {
        // Find active session or default to the first one
        final activeSession = _sessions.firstWhere(
          (s) => s['is_active'] == true || (s['status']?.toString().toLowerCase() == 'actif'),
          orElse: () => _sessions.first,
        );
        _selectedSessionId = (activeSession['id'] as num?)?.toInt() ?? 1;
        _selectedSessionName = activeSession['session_name']?.toString() ?? '';

        await _fetchFinanceData();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "Aucune session académique configurée.";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Erreur de chargement: $e";
      });
    }
  }

  Future<void> _fetchFinanceData() async {
    if (_selectedSessionId == null) return;

    try {
      // Parallel fetch for maximum speed
      final results = await Future.wait([
        _repository.getFinanceStats(
          schoolId: _schoolId,
          sessionId: _selectedSessionId!,
        ),
        _repository.getStudentFeesList(
          schoolId: _schoolId,
          sessionId: _selectedSessionId!,
        ),
      ]);

      final statsRes = results[0] as Map<String, dynamic>;
      final feesList = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          if (statsRes['success'] == true && statsRes['stats'] != null) {
            _stats = Map<String, dynamic>.from(statsRes['stats']);
          }
          _fees = feesList;

          if (_userEducationalLevel != null &&
              !EducationalLevelHelper.hasAllEducationalLevels(_userEducationalLevel)) {
            final scopedFees = _fees.where((fee) {
              final student = _extractStudentMap(fee['students']);
              return EducationalLevelHelper.isStudentInEducationalLevel(
                educationalLevel: student['educational_level']?.toString() ??
                    student['educationalLevel']?.toString() ??
                    fee['educational_level']?.toString(),
                className: student['classe']?.toString() ?? fee['classe']?.toString(),
                sectionName: student['section']?.toString() ?? fee['section']?.toString(),
                filiere: student['filiere']?.toString() ?? fee['filiere']?.toString(),
                activeLevel: _userEducationalLevel,
              );
            }).toList();

            double totalExpected = 0.0;
            double totalCollected = 0.0;
            double totalDebts = 0.0;
            for (final f in scopedFees) {
              totalExpected += (f['total_expected'] as num?)?.toDouble() ?? 0.0;
              totalCollected += (f['total_paid'] as num?)?.toDouble() ?? 0.0;
              totalDebts += (f['balance'] as num?)?.toDouble() ?? 0.0;
            }
            _stats = {
              'totalExpected': totalExpected,
              'totalCollected': totalCollected,
              'totalDebts': totalDebts,
            };
          }

          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erreur lors de la récupération des données: $e";
        });
      }
    }
  }

  Map<String, dynamic> _extractStudentMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first);
    }
    return {};
  }

  String _clean(dynamic val) {
    if (val == null) return '';
    return val
        .toString()
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  void _applyFilters() {
    final query = _clean(_searchController.text);

    setState(() {
      _filteredFees = _fees.where((fee) {
        final student = _extractStudentMap(fee['students']);

        // Scope check for educational level
        if (_userEducationalLevel != null &&
            !EducationalLevelHelper.hasAllEducationalLevels(_userEducationalLevel)) {
          final studentLevel = student['educational_level']?.toString() ??
              student['educationalLevel']?.toString() ??
              fee['educational_level']?.toString();
          final studentClass = student['classe']?.toString() ?? fee['classe']?.toString();
          final studentSection = student['section']?.toString() ?? fee['section']?.toString();
          final studentFiliere = student['filiere']?.toString() ?? fee['filiere']?.toString();

          if (!EducationalLevelHelper.isStudentInEducationalLevel(
            educationalLevel: studentLevel,
            className: studentClass,
            sectionName: studentSection,
            filiere: studentFiliere,
            activeLevel: _userEducationalLevel,
          )) {
            return false;
          }
        }

        final name = _clean(student['nom_etudiant'] ?? student['nomEtudiant'] ?? student['name'] ?? fee['nom_etudiant']);
        final code = _clean(student['num_admission'] ?? student['numAdmission'] ?? student['matricule'] ?? fee['num_admission']);
        final classe = _clean(student['classe'] ?? student['className'] ?? fee['classe']);
        final level = _clean(student['educational_level'] ?? student['educationalLevel'] ?? fee['educational_level']);

        final matchesSearch = query.isEmpty ||
            name.contains(query) ||
            code.contains(query) ||
            classe.contains(query) ||
            level.contains(query);

        final rawStatus = _clean(fee['status']);
        final targetStatus = _clean(_statusFilter);

        bool matchesStatus = _statusFilter == 'Tous' || targetStatus.isEmpty;
        if (!matchesStatus) {
          if (targetStatus.contains('solde') || targetStatus.contains('paye')) {
            matchesStatus = rawStatus.contains('solde') || rawStatus.contains('paye');
          } else if (targetStatus.contains('partiel')) {
            matchesStatus = rawStatus.contains('partiel');
          } else if (targetStatus.contains('impay') || targetStatus.contains('retard')) {
            matchesStatus = rawStatus.contains('impay') || rawStatus.contains('retard');
          } else {
            matchesStatus = rawStatus == targetStatus;
          }
        }

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _handleSync() async {
    if (_selectedSessionId == null) return;

    setState(() {
      _isSyncing = true;
    });

    final res = await _repository.syncStudentFees(
      schoolId: _schoolId,
      sessionId: _selectedSessionId!,
    );

    if (mounted) {
      setState(() {
        _isSyncing = false;
      });

      if (res['success'] == true) {
        final message = res['message']?.toString() ??
            "Dossiers synchronisés: ${res['inserted'] ?? 0} créés, ${res['updated'] ?? 0} mis à jour.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: res['offline'] == true ? const Color(0xFF1E88E5) : AppColors.success,
          ),
        );
        if (res['stats'] != null && res['stats'] is Map) {
          _stats = Map<String, dynamic>.from(res['stats']);
        }
        if (res['data'] != null && res['data'] is List) {
          _fees = List<Map<String, dynamic>>.from(res['data']);
          _applyFilters();
        }
        _fetchFinanceData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? "Une erreur est survenue lors de la synchronisation."),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _showSessionSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    "Sélectionner la Session",
                    style: AppTextStyles.heading3,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final item = _sessions[index];
                      final id = item['id'] as int;
                      final name = item['session_name'] as String;
                      final isActive = item['is_active'] == true;
                      final status = item['status']?.toString().toLowerCase().trim() ?? '';
                      final isClosed = !isActive ||
                          status == 'clôturé' ||
                          status == 'cloture' ||
                          status == 'verrouillé' ||
                          status == 'verrouille' ||
                          status == 'archivé' ||
                          status == 'archive';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isClosed
                              ? Colors.amber.shade100
                              : (isActive ? AppColors.success.withAlpha(25) : AppColors.slate100),
                          child: Icon(
                            isClosed ? Icons.lock_clock_rounded : Icons.calendar_today,
                            color: isClosed
                                ? Colors.amber.shade800
                                : (isActive ? AppColors.success : AppColors.slate500),
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: id == _selectedSessionId ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isClosed)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  border: Border.all(color: Colors.amber.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "Clôturée 🔒",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: id == _selectedSessionId ? const Icon(Icons.check, color: AppColors.primary) : null,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _selectedSessionId = id;
                            _selectedSessionName = name;
                            _isLoading = true;
                          });
                          _fetchFinanceData();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('sold') || s.contains('pay')) return AppColors.success;
    if (s.contains('partiel')) return AppColors.warning;
    return AppColors.danger;
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF4F46E5),
      const Color(0xFF0D9488),
      const Color(0xFF7C3AED),
      const Color(0xFF2563EB),
      const Color(0xFFEA580C),
      const Color(0xFFDB2777),
    ];
    if (name.isEmpty) return colors[0];
    final int hash = name.codeUnits.fold(0, (prev, element) => prev + element).abs();
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate50,
      appBar: AppBar(
        title: const Text("Gestion Financière", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate900,
        elevation: 0,
        actions: [
                    IconButton(
            icon: const Icon(Icons.school_rounded, color: Color(0xFFD97706)),
            onPressed: () => context.push('/finance/bourses-echeanciers'),
            tooltip: "Bourses, Exonérations & Échéanciers",
          ),
IconButton(
            icon: const Icon(Icons.balance_rounded, color: Color(0xFF4F46E5)),
            onPressed: () => context.push('/finance/unified-report'),
            tooltip: "Bilan Recettes vs Dépenses (Unifié)",
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981)),
            onPressed: () => context.push('/finance/journal'),
            tooltip: "Journal de caisse & Encaissements",
          ),
          IconButton(
            icon: const Icon(Icons.analytics_rounded, color: Color(0xFF6366F1)),
            onPressed: () => context.push('/finance/forecast'),
            tooltip: "Prévisions de Trésorerie & Cashflow",
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.primary),
            onPressed: _showSessionSelector,
            tooltip: "Changer de Session",
          ),
          if (!_isLoading && _canCollectFinance && !_isSessionFrozen)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.sync, color: AppColors.primary),
              onPressed: _isSyncing ? null : _handleSync,
              tooltip: "Synchroniser les dossiers",
            ),
        ],
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
                          onPressed: _loadInitialData,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text("Réessayer", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_isSessionFrozen)
                      _buildFreezeWarningBanner(),

                    // Overview Stats Card
                    _buildStatsCard(),

                    // Search & Filter Bar
                    _buildFilterSection(),

                    // Student list
                    Expanded(
                      child: _filteredFees.isEmpty
                          ? const Center(
                              child: Text(
                                "Aucun dossier financier trouvé.",
                                style: TextStyle(color: AppColors.slate400, fontWeight: FontWeight.bold),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filteredFees.length,
                              itemBuilder: (context, index) {
                                try {
                                  final fee = _filteredFees[index];
                                  final student = _extractStudentMap(fee['students']);
                                  final name = (student['nom_etudiant'] ??
                                          student['nomEtudiant'] ??
                                          student['name'] ??
                                          fee['nom_etudiant'] ??
                                          'Sans Nom')
                                      .toString()
                                      .trim();
                                  final admissionNo = (student['num_admission'] ??
                                          student['numAdmission'] ??
                                          student['matricule'] ??
                                          fee['num_admission'] ??
                                          'N/A')
                                      .toString()
                                      .trim();
                                  final className = (student['classe'] ??
                                          student['className'] ??
                                          fee['classe'] ??
                                          'Non spécifiée')
                                      .toString()
                                      .trim();

                                  final expected = (fee['total_expected'] as num?)?.toDouble() ??
                                      double.tryParse(fee['total_expected']?.toString() ?? '') ??
                                      0.0;
                                  final paid = (fee['total_paid'] as num?)?.toDouble() ??
                                      double.tryParse(fee['total_paid']?.toString() ?? '') ??
                                      0.0;
                                  final balance = (fee['balance'] as num?)?.toDouble() ??
                                      double.tryParse(fee['balance']?.toString() ?? '') ??
                                      (expected - paid);
                                  final status = fee['status']?.toString() ??
                                      (balance <= 0 ? 'Soldé' : (paid > 0 ? 'Partiel' : 'Impayé'));

                                  final words = name
                                      .split(RegExp(r'\s+'))
                                      .where((w) => w.isNotEmpty)
                                      .toList();
                                  String initials = '?';
                                  if (words.isNotEmpty) {
                                    if (words.length == 1) {
                                      initials = words[0].substring(0, words[0].length >= 2 ? 2 : 1).toUpperCase();
                                    } else {
                                      initials = '${words[0][0]}${words[1][0]}'.toUpperCase();
                                    }
                                  }

                                  final avatarColor = _getAvatarColor(name);
                                  final feeId = (fee['id'] as num?)?.toInt() ?? index;

                                  return _buildFeeCard(
                                    feeId: feeId,
                                    name: name,
                                    admissionNo: admissionNo,
                                    className: className,
                                    expected: expected,
                                    paid: paid,
                                    balance: balance,
                                    status: status,
                                    initials: initials,
                                    avatarColor: avatarColor,
                                    feeData: fee,
                                  );
                                } catch (err, stack) {
                                  debugPrint("Error rendering fee card at index $index: $err\n$stack");
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFreezeWarningBanner() {
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
              "Exercice financier gelé (Session clôturée ou verrouillée) : Mode consultation seule. Les encaissements et modifications sont désactivés.",
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

  Widget _buildStatsCard() {
    final double expected = (_stats['totalExpected'] as num?)?.toDouble() ?? 0.0;
    final double collected = (_stats['totalCollected'] as num?)?.toDouble() ?? 0.0;
    final double debts = (_stats['totalDebts'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "SESSION : $_selectedSessionName",
            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem("Attendu", expected, Colors.white),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildMetricItem("Recouvré", collected, AppColors.success),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildMetricItem("Solde/Dettes", debts, const Color(0xFFFCA5A5)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => context.push('/finance/journal'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(55)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_rounded, color: Color(0xFF34D399), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Ouvrir le Journal de Caisse & Rapports",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, double val, Color valueColor) {
    return Column(
      children: [
        Text(
          "${val.toStringAsFixed(0)} F",
          style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.w900),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          // Search box
          TextField(
            controller: _searchController,
            onChanged: (v) => _applyFilters(),
            decoration: InputDecoration(
              hintText: "Rechercher par élève ou matricule...",
              prefixIcon: const Icon(Icons.search, color: AppColors.slate400, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilters();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFEEF2F6), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal filter chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['Tous', 'Impayé', 'Partiel', 'Soldé'].map((filter) {
              final isSelected = _statusFilter == filter;
              return ChoiceChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _statusFilter = filter;
                    });
                    _applyFilters();
                  }
                },
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppColors.slate700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFEEF2F6), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildFeeCard({
    required int feeId,
    required String name,
    required String admissionNo,
    required String className,
    required double expected,
    required double paid,
    required double balance,
    required String status,
    required String initials,
    required Color avatarColor,
    required Map<String, dynamic> feeData,
  }) {
    final statusColor = _getStatusColor(status);
    final safeProgress = (expected > 0 && paid.isFinite && expected.isFinite)
        ? (paid / expected).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEEF2F6), width: 1.5),
      ),
      color: Colors.white,
      child: InkWell(
        onTap: () {
          final feeDataWithFreeze = Map<String, dynamic>.from(feeData);
          feeDataWithFreeze['is_session_frozen'] = _isSessionFrozen;
          feeDataWithFreeze['session_id'] = _selectedSessionId;
          context.push('/finance/fee-details', extra: feeDataWithFreeze).then((_) {
            // Refresh data when returning from details
            if (mounted) _fetchFinanceData();
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: avatarColor.withAlpha(30),
                    child: Text(
                      initials,
                      style: TextStyle(color: avatarColor, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.bodyBold.copyWith(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              "Matricule: $admissionNo • $className",
                              style: const TextStyle(color: AppColors.slate500, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            if ((feeData['total_reduction'] as num? ?? 0) > 0 || feeData['scholarship'] != null || feeData['scholarship_name'] != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Text(
                                  feeData['scholarship_percentage'] != null
                                      ? "🎓 ${feeData['scholarship_percentage']}% Bourse"
                                      : (feeData['scholarship']?['discount_percentage'] != null
                                          ? "🎓 ${feeData['scholarship']['discount_percentage']}% Bourse"
                                          : "🎓 Bourse"),
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${paid.toStringAsFixed(0)} F / ${expected.toStringAsFixed(0)} F", style: AppTextStyles.bodyBold.copyWith(fontSize: 13)),
                      const Text("Montant Payé / Expected", style: TextStyle(color: AppColors.slate400, fontSize: 9)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${balance.toStringAsFixed(0)} F", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: balance > 0 ? AppColors.danger : AppColors.slate700)),
                      const Text("Solde restant", style: TextStyle(color: AppColors.slate400, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: safeProgress,
                  backgroundColor: AppColors.slate100,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
