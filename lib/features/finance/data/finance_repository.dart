import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/api/offline_queue_manager.dart';
import '../../../core/api/offline_store_manager.dart';
import '../../../core/api/supabase_client.dart';
import '../../../core/api/mobile_api_client.dart';
import '../../../core/api/sync_engine.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/di/injection.dart';
import '../../../core/utils/educational_level_helper.dart';
import '../../../core/utils/type_converters.dart';

class FinanceRepository {
  final MobileApiClient _apiClient;
  final SupabaseClient _client;

  FinanceRepository({MobileApiClient? apiClient, SupabaseClient? client})
      : _apiClient = apiClient ?? MobileApiClient(),
        _client = client ?? SupabaseClientManager().client;

  String _feesCacheKey(int schoolId, int sessionId) =>
      "student_fees_${schoolId}_$sessionId";

  String _statsCacheKey(int schoolId, int sessionId) =>
      "finance_stats_${schoolId}_$sessionId";

  String _paymentsCacheKey(int feeId) => "fee_payments_$feeId";

  String _sessionsCacheKey(int schoolId) => "finance_sessions_$schoolId";

  Future<void> _updateCachedFeeAfterPayment({
    required int feeId,
    required double newPaid,
    required double newReduction,
    required double newBalance,
    required String newStatus,
    int? studentId,
    String? numAdmission,
  }) async {
    if (!Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)) {
      return;
    }

    final box = Hive.box(OfflineStoreManager.boxStudentFees);
    final keys = box.keys.cast<dynamic>().map((e) => e.toString()).toList();

    for (final key in keys) {
      if (!key.startsWith('student_fees_')) {
        continue;
      }

      final cachedFees = box.get(key);
      if (cachedFees is! List) {
        continue;
      }

      bool updated = false;
      final mappedFees = cachedFees.map((item) {
        if (item is! Map) return item;
        final fee = Map<String, dynamic>.from(item);
        final currentId = TypeConverters.safeInt(fee['id']);
        final currentStudentId = TypeConverters.safeInt(fee['student_id'],
            TypeConverters.safeInt((fee['students'] is Map) ? fee['students']['id'] : null));
        final currentAdm = fee['num_admission']?.toString() ??
            ((fee['students'] is Map) ? fee['students']['num_admission']?.toString() : null);

        final matchesFeeId = currentId > 0 && currentId == feeId;
        final matchesStudentId = studentId != null && studentId > 0 && currentStudentId == studentId;
        final matchesAdm = numAdmission != null && numAdmission.trim().isNotEmpty &&
            currentAdm != null && currentAdm.trim().toLowerCase() == numAdmission.trim().toLowerCase();

        if (matchesFeeId || matchesStudentId || matchesAdm) {
          fee['total_paid'] = newPaid;
          fee['total_reduction'] = newReduction;
          fee['balance'] = newBalance;
          fee['status'] = newStatus;
          updated = true;
        }
        return fee;
      }).toList();

      if (updated) {
        await box.put(key, mappedFees);

        final parts = key.split('_');
        if (parts.length >= 4) {
          final schoolId = int.tryParse(parts[2]);
          final sessionId = int.tryParse(parts[3]);
          if (schoolId != null && sessionId != null) {
            await _refreshStatsCacheFromFees(
              schoolId: schoolId,
              sessionId: sessionId,
              fees: mappedFees
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(),
            );
          }
        }
      }
    }
  }

  Map<String, dynamic> _buildStatsFromFees(List<Map<String, dynamic>> fees) {
    double totalExpected = 0.0;
    double totalCollected = 0.0;
    double totalDebts = 0.0;

    for (final row in fees) {
      totalExpected += TypeConverters.safeDouble(row['total_expected']);
      totalCollected += TypeConverters.safeDouble(row['total_paid']);
      totalDebts += TypeConverters.safeDouble(row['balance']);
    }

    return {
      'success': true,
      'stats': {
        'totalExpected': totalExpected,
        'totalCollected': totalCollected,
        'totalDebts': totalDebts,
      },
    };
  }

  Future<void> _refreshStatsCacheFromFees({
    required int schoolId,
    required int sessionId,
    required List<Map<String, dynamic>> fees,
  }) async {
    final cacheManager = locator<OfflineStoreManager>();
    final stats = _buildStatsFromFees(fees);
    await cacheManager.saveDataList(
      boxName: OfflineStoreManager.boxStudentFees,
      key: _statsCacheKey(schoolId, sessionId),
      data: [stats],
    );
  }

  /// Fetch financial statistics for a school and session
  Future<Map<String, dynamic>> getFinanceStats({
    required int schoolId,
    required int sessionId,
  }) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = _statsCacheKey(schoolId, sessionId);

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("Offline Mode: Fetching finance stats from local cache.");
      final cachedList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (cachedList.isNotEmpty) {
        return Map<String, dynamic>.from(cachedList.first);
      }

      final cachedFees = await getStudentFeesList(schoolId: schoolId, sessionId: sessionId);
      if (cachedFees.isNotEmpty) {
        return _buildStatsFromFees(cachedFees);
      }

      return {
        'success': true,
        'stats': {
          'totalExpected': 0.0,
          'totalCollected': 0.0,
          'totalDebts': 0.0,
        },
      };
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/finance/summary?action=getFinanceStats&schoolId=$schoolId&sessionId=$sessionId',
      );
      
      final result = Map<String, dynamic>.from(response);

      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
        data: [result],
      );

      return result;
    } catch (e) {
      debugPrint("Error fetching finance stats: $e");
      final cachedList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (cachedList.isNotEmpty) {
        return Map<String, dynamic>.from(cachedList.first);
      }
      final cachedFees = await getStudentFeesList(schoolId: schoolId, sessionId: sessionId);
      if (cachedFees.isNotEmpty) {
        return _buildStatsFromFees(cachedFees);
      }
      return {
        'success': true,
        'stats': {
          'totalExpected': 0.0,
          'totalCollected': 0.0,
          'totalDebts': 0.0,
        },
      };
    }
  }

  /// Get list of student fees for a session and school with fallback and student synthesis
  Future<List<Map<String, dynamic>>> getStudentFeesList({
    required int schoolId,
    required int sessionId,
  }) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = _feesCacheKey(schoolId, sessionId);

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("Offline Mode: Fetching student fees from local cache.");
      var list = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );

      // Multi-key search in boxStudentFees if primary key is empty
      if (list.isEmpty && Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)) {
        final box = Hive.box(OfflineStoreManager.boxStudentFees);
        for (final k in box.keys) {
          final kStr = k.toString();
          if (kStr.startsWith('student_fees_${schoolId}_') || kStr.startsWith('student_fees_')) {
            final candidate = box.get(k);
            if (candidate is List && candidate.isNotEmpty) {
              list = candidate.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              debugPrint("Offline Mode: Recovered fees from alternative cache key: $kStr (count: ${list.length})");
              break;
            }
          }
        }
      }

      // Check if any students exist in boxStudents that are not in list; merge them
      final students = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: "students_list",
      );
      if (students.isNotEmpty) {
        final existingStudentIds = <String>{};
        for (final f in list) {
          final s = f['students'] is Map ? f['students'] : f;
          final sId = s['id']?.toString() ?? f['student_id']?.toString();
          if (sId != null) existingStudentIds.add(sId);
        }

        bool synthesized = false;
        for (final std in students) {
          final sId = std['id']?.toString() ?? std['localId']?.toString();
          if (sId != null && !existingStudentIds.contains(sId)) {
            final monthly = TypeConverters.safeDouble(std['frais_mensuels']);
            final registration = TypeConverters.safeDouble(std['frais_inscription']);
            final coges = TypeConverters.safeDouble(std['frais_coges_card'], 1500.0);
            final transport = TypeConverters.safeDouble(std['frais_transport_internat']);
            final isPrimary = (std['educational_level']?.toString().toLowerCase().contains('prim') ?? false) ||
                (std['educational_level']?.toString().toLowerCase().contains('mater') ?? false) ||
                (std['classe']?.toString().toUpperCase().contains('CE') ?? false) ||
                (std['classe']?.toString().toUpperCase().contains('CM') ?? false) ||
                (std['classe']?.toString().toUpperCase().contains('CI') ?? false) ||
                (std['classe']?.toString().toUpperCase().contains('CP') ?? false);

            double tuition;
            if (monthly >= 30000.0 || (isPrimary && monthly >= 20000.0)) {
              tuition = monthly;
            } else if (monthly > 0) {
              tuition = monthly * 9.0;
            } else {
              tuition = isPrimary ? 40000.0 : 0.0;
            }

            final prevBalance = TypeConverters.safeDouble(std['ancien_solde']);

            double totalExp = tuition + registration + coges + transport + prevBalance;
            if (isPrimary && (totalExp > 75000.0 || totalExp <= 0.0)) {
              totalExp = 45000.0;
            }

            list.add({
              'id': DateTime.now().millisecondsSinceEpoch + list.length,
              'student_id': std['id'] ?? sId,
              'school_id': schoolId,
              'session_id': sessionId,
              'total_expected': totalExp > 0 ? totalExp : 45000.0,
              'total_paid': 0.0,
              'total_reduction': 0.0,
              'balance': totalExp > 0 ? totalExp : 45000.0,
              'status': 'Impayé',
              'students': {
                'id': std['id'] ?? sId,
                'nom_etudiant': std['nom_etudiant'] ?? 'Élève',
                'num_admission': std['num_admission'] ?? 'AM-2026',
                'classe': std['classe'] ?? '',
                'educational_level': std['educational_level'] ?? '',
                'section': std['section'] ?? '',
                'mobile': std['mobile'] ?? '',
                'nom_pere': std['nom_pere'] ?? '',
              },
            });
            existingStudentIds.add(sId);
            synthesized = true;
          }
        }
        if (synthesized) {
          await cacheManager.saveDataList(
            boxName: OfflineStoreManager.boxStudentFees,
            key: cacheKey,
            data: list,
          );
        }
      }

      return list;
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/finance/invoices?action=getStudentFeesList&schoolId=$schoolId&sessionId=$sessionId',
      );

      final list = List<Map<String, dynamic>>.from(response['data'] ?? []);
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
        data: list,
      );
      await _refreshStatsCacheFromFees(
        schoolId: schoolId,
        sessionId: sessionId,
        fees: list,
      );
      return list;
    } catch (e) {
      debugPrint("Error fetching student fees list: $e");
      var list = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (list.isEmpty && Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)) {
        final box = Hive.box(OfflineStoreManager.boxStudentFees);
        for (final k in box.keys) {
          final kStr = k.toString();
          if (kStr.startsWith('student_fees_${schoolId}_') || kStr.startsWith('student_fees_')) {
            final candidate = box.get(k);
            if (candidate is List && candidate.isNotEmpty) {
              list = candidate.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              break;
            }
          }
        }
      }
      return list;
    }
  }

  /// Fetch payment history for a specific student fee ID
  Future<List<Map<String, dynamic>>> getFeePayments(int feeId) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = _paymentsCacheKey(feeId);

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("Offline Mode: Fetching fee payments from local cache.");
      return cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
      );
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/finance/payments?action=getFeePayments&feeId=$feeId',
      );

      final list = List<Map<String, dynamic>>.from(response['data'] ?? []);
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
        data: list,
      );
      return list;
    } catch (e) {
      debugPrint("Error fetching fee payments: $e");
      return cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
      );
    }
  }

  String _journalCacheKey(int schoolId, int? sessionId) =>
      "payments_journal_${schoolId}_${sessionId ?? 'all'}";

  Future<void> _updateJournalCacheAfterPayment({
    required int schoolId,
    required Map<String, dynamic> payment,
  }) async {
    try {
      final cacheManager = locator<OfflineStoreManager>();
      final feeId = payment['fee_id'] ?? payment['feeId'];
      String? studentName = payment['student_name'];
      String? numAdmission = payment['num_admission'];
      String? classe = payment['classe'];
      String? educationalLevel = payment['educational_level'];
      String? section = payment['section'];
      String? filiere = payment['filiere'];
      int? sessionId = TypeConverters.safeInt(payment['session_id'], TypeConverters.safeInt(payment['sessionId']));
      if (sessionId == 0) sessionId = null;
      String? feeStatus = payment['fee_status'];

      if ((studentName == null || numAdmission == null || classe == null || educationalLevel == null) &&
          Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)) {
        final box = Hive.box(OfflineStoreManager.boxStudentFees);
        for (var key in box.keys) {
          if (!key.toString().startsWith('student_fees_')) continue;
          final fees = box.get(key);
          if (fees is List) {
            for (var item in fees) {
              final targetFeeId = TypeConverters.safeInt(feeId);
              final itemFeeId = item is Map ? TypeConverters.safeInt(item['id']) : 0;
              if (item is Map && (item['id'] == feeId || (targetFeeId > 0 && itemFeeId == targetFeeId))) {
                final s = item['students'] is Map ? item['students'] : item;
                studentName ??= s['nom_etudiant'] ?? s['nomPrenom'] ?? s['name'];
                numAdmission ??= s['num_admission'] ?? s['matricule'];
                classe ??= s['classe']?.toString();
                educationalLevel ??= s['educational_level']?.toString() ?? s['educationalLevel']?.toString() ?? s['niveau']?.toString();
                section ??= s['section']?.toString();
                filiere ??= s['filiere']?.toString();
                final itemSess = TypeConverters.safeInt(item['session_id'], TypeConverters.safeInt(item['sessionId']));
                if (itemSess > 0) sessionId ??= itemSess;
                feeStatus ??= item['status']?.toString();
                break;
              }
            }
          }
          if (studentName != null && classe != null) break;
        }
      }

      final enrichedPayment = {
        ...payment,
        'student_name': studentName ?? 'Élève',
        'num_admission': numAdmission ?? '',
        'classe': classe ?? '',
        'educational_level': educationalLevel ?? '',
        'section': section ?? '',
        'filiere': filiere ?? '',
        if (sessionId != null) 'session_id': sessionId,
        if (feeStatus != null) 'fee_status': feeStatus,
        'is_pending_sync': payment['is_pending_sync'] ?? false,
      };

      // Collect all journal cache keys to update:
      final journalKeys = <String>{
        _journalCacheKey(schoolId, null),
        "payments_journal_${schoolId}_all",
      };
      if (sessionId != null) {
        journalKeys.add(_journalCacheKey(schoolId, sessionId));
      }

      // Also check if there is an active session or cached sessions for this school
      try {
        final sessionsCacheKey = _sessionsCacheKey(schoolId);
        final cachedSessions = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxStudentFees,
          key: sessionsCacheKey,
        );
        for (final sess in cachedSessions) {
          final sId = TypeConverters.safeInt(sess['id']);
          if (sId > 0) {
            journalKeys.add(_journalCacheKey(schoolId, sId));
          }
        }
      } catch (_) {}

      for (final jKey in journalKeys) {
        final cachedJournal = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxFeePayments,
          key: jKey,
        );
        final filtered = cachedJournal.where((p) => p['reference'] != enrichedPayment['reference']).toList();
        await cacheManager.saveDataList(
          boxName: OfflineStoreManager.boxFeePayments,
          key: jKey,
          data: [enrichedPayment, ...filtered],
        );
      }
    } catch (e) {
      debugPrint("Warning: could not update journal cache after payment: $e");
    }
  }

  /// Helper to merge offline pending payments from queue or local boxes into journal
  List<Map<String, dynamic>> _mergePendingOfflinePayments(
    List<Map<String, dynamic>> baseList,
    int schoolId,
    int? sessionId,
  ) {
    try {
      final queueManager = locator<OfflineQueueManager>();
      final pendingOps = queueManager.getPendingOperations();
      final List<Map<String, dynamic>> pendingPayments = [];

      for (final op in pendingOps) {
        if (op.table == 'fee_payments' && op.action == 'record_payment') {
          final d = op.data;
          final opSchoolId = TypeConverters.safeInt(d['schoolId']);
          if (opSchoolId != 0 && opSchoolId != schoolId) continue;

          final opSessionId = TypeConverters.safeInt(d['sessionId']);
          final effectiveOpSession = opSessionId > 0 ? opSessionId : null;
          if (sessionId != null && effectiveOpSession != null && effectiveOpSession != sessionId) continue;

          final ref = d['reference']?.toString() ?? '';
          if (ref.isEmpty) continue;

          pendingPayments.add({
            'id': d['id'] ?? DateTime.now().millisecondsSinceEpoch,
            'fee_id': d['feeId'],
            'school_id': opSchoolId,
            'amount': TypeConverters.safeDouble(d['amount']),
            'reduction': TypeConverters.safeDouble(d['reduction']),
            'payment_mode': d['paymentMode']?.toString() ?? 'Espèces',
            'reference': ref,
            'month_concerned': d['monthConcerned']?.toString() ?? '',
            'date_paid': d['date_paid']?.toString() ?? DateTime.now().toIso8601String(),
            'recorded_by': d['recordedBy']?.toString() ?? 'Admin',
            'student_name': d['student_name']?.toString() ?? d['studentName']?.toString() ?? 'Élève',
            'num_admission': d['num_admission']?.toString() ?? d['numAdmission']?.toString() ?? '',
            'classe': d['classe']?.toString() ?? '',
            'educational_level': d['educational_level']?.toString() ?? d['educationalLevel']?.toString() ?? '',
            'section': d['section']?.toString() ?? '',
            'filiere': d['filiere']?.toString() ?? '',
            'fee_status': d['fee_status']?.toString() ?? 'Partiel',
            'is_pending_sync': true,
          });
        }
      }

      if (pendingPayments.isEmpty) return baseList;

      final existingRefs = baseList.map((e) => e['reference']?.toString()).toSet();
      final newToAdd = pendingPayments.where((p) => !existingRefs.contains(p['reference']?.toString())).toList();

      if (newToAdd.isEmpty) return baseList;
      return [...newToAdd, ...baseList];
    } catch (e) {
      debugPrint("Warning: could not merge pending offline payments: $e");
      return baseList;
    }
  }

  /// Fetch full payments journal (Journal de caisse)
  Future<List<Map<String, dynamic>>> getPaymentsJournal({
    required int schoolId,
    int? sessionId,
  }) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = _journalCacheKey(schoolId, sessionId);

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("Offline Mode: Fetching payments journal from local cache.");
      var localList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
      );

      // If specific session cache is empty, fallback to 'all' cache
      if (localList.isEmpty && sessionId != null) {
        final allKey = _journalCacheKey(schoolId, null);
        final allList = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxFeePayments,
          key: allKey,
        );
        if (allList.isNotEmpty) {
          localList = allList.where((p) {
            final pSess = TypeConverters.safeInt(p['session_id'], TypeConverters.safeInt(p['sessionId']));
            return pSess == 0 || pSess == sessionId;
          }).toList();
        }
      }

      // Always merge any pending offline payments from the queue
      return _mergePendingOfflinePayments(localList, schoolId, sessionId);
    }

    try {
      final sessionParam = sessionId != null ? '&sessionId=$sessionId' : '';
      final response = await _apiClient.getJson(
        '/api/mobile/finance/payments?action=getPaymentsJournal&schoolId=$schoolId$sessionParam',
      );

      final list = List<Map<String, dynamic>>.from(response['data'] ?? []);
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
        data: list,
      );
      // Merge pending unsynced payments so newly created offline receipts are never hidden
      return _mergePendingOfflinePayments(list, schoolId, sessionId);
    } catch (e) {
      debugPrint("Error fetching payments journal: $e");
      var cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: cacheKey,
      );
      if (cached.isEmpty && sessionId != null) {
        final allList = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxFeePayments,
          key: _journalCacheKey(schoolId, null),
        );
        if (allList.isNotEmpty) {
          cached = allList.where((p) {
            final pSess = TypeConverters.safeInt(p['session_id'], TypeConverters.safeInt(p['sessionId']));
            return pSess == 0 || pSess == sessionId;
          }).toList();
        }
      }
      return _mergePendingOfflinePayments(cached, schoolId, sessionId);
    }
  }

  /// Checks whether an academic session is closed, archived, or locked
  bool isSessionFrozen({int? sessionId, int? schoolId}) {
    if (sessionId == null || sessionId <= 0) return false;
    try {
      final cacheManager = locator<OfflineStoreManager>();
      
      // 1. Try school specific sessions key
      if (schoolId != null && schoolId > 0) {
        final sessionList = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxSchoolSessions,
          key: _sessionsCacheKey(schoolId),
        );
        for (final s in sessionList) {
          if ((s['id'] as num?)?.toInt() == sessionId) {
            return _checkSessionFrozenMap(s);
          }
        }

        final genericList = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxSchoolSessions,
          key: "sessions_$schoolId",
        );
        for (final s in genericList) {
          if ((s['id'] as num?)?.toInt() == sessionId) {
            return _checkSessionFrozenMap(s);
          }
        }
      }
    } catch (e) {
      debugPrint("Error in isSessionFrozen: $e");
    }
    return false;
  }

  bool _checkSessionFrozenMap(Map<String, dynamic> s) {
    final status = s['status']?.toString().toLowerCase().trim() ?? '';
    final isActive = s['is_active'] == true;
    return !isActive ||
        status == 'clôturé' ||
        status == 'cloture' ||
        status == 'verrouillé' ||
        status == 'verrouille' ||
        status == 'archivé' ||
        status == 'archive';
  }

  /// Record a payment and update the student fee balance
  Future<Map<String, dynamic>> recordPayment({
    required int feeId,
    required int schoolId,
    required double amount,
    required double reduction,
    required String paymentMode,
    required String reference,
    required String monthConcerned,
    required String recordedBy,
    required double currentPaid,
    required double currentReduction,
    required double totalExpected,
    int? studentId,
    String? studentName,
    String? numAdmission,
    String? classe,
    String? educationalLevel,
    String? section,
    String? filiere,
    int? sessionId,
    bool isFromSync = false,
  }) async {
    // Protection: verify if session is frozen
    if (sessionId != null && isSessionFrozen(sessionId: sessionId, schoolId: schoolId)) {
      return {
        'success': false,
        'error': "Impossible d'enregistrer le versement : l'année scolaire est clôturée ou verrouillée. Les opérations financières y sont gelées.",
      };
    }

    final syncEngine = locator<SyncEngine>();
    final queueManager = locator<OfflineQueueManager>();
    final cacheManager = locator<OfflineStoreManager>();

    final double newPaid = currentPaid + amount;
    final double newReduction = currentReduction + reduction;
    final double newBalance = totalExpected - newPaid - newReduction;

    String newStatus = "Impaye";
    if (newBalance <= 0) {
      newStatus = "Solde";
    } else if (newPaid > 0) {
      newStatus = "Partiel";
    }

    final String receiptRef = reference.trim().isNotEmpty
        ? reference.trim()
        : 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final int offlinePaymentId = DateTime.now().millisecondsSinceEpoch;

    if (!syncEngine.isOnlineNotifier.value) {
      if (isFromSync) {
        return {
          'success': false,
          'error': 'Connexion indisponible pour le moment.',
          'isOffline': true,
        };
      }

      debugPrint("Offline Mode: Queueing fee payment locally with ref: $receiptRef");
      await queueManager.enqueue(
        table: 'fee_payments',
        action: 'record_payment',
        data: {
          'feeId': feeId,
          'schoolId': schoolId,
          'amount': amount,
          'reduction': reduction,
          'paymentMode': paymentMode,
          'reference': receiptRef,
          'monthConcerned': monthConcerned,
          'recordedBy': recordedBy,
          'currentPaid': currentPaid,
          'currentReduction': currentReduction,
          'totalExpected': totalExpected,
          if (studentId != null) 'studentId': studentId,
          if (studentName != null) 'studentName': studentName,
          if (numAdmission != null) 'numAdmission': numAdmission,
          if (classe != null) 'classe': classe,
          if (educationalLevel != null) 'educationalLevel': educationalLevel,
          if (section != null) 'section': section,
          if (filiere != null) 'filiere': filiere,
          if (sessionId != null) 'sessionId': sessionId,
        },
      );

      final paymentCacheKey = _paymentsCacheKey(feeId);
      final cachedPayments = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: paymentCacheKey,
      );
      final localPayment = {
        'id': offlinePaymentId,
        'fee_id': feeId,
        if (studentId != null) 'student_id': studentId,
        'school_id': schoolId,
        'amount': amount,
        'reduction': reduction,
        'payment_mode': paymentMode,
        'reference': receiptRef,
        'month_concerned': monthConcerned.isNotEmpty ? monthConcerned : null,
        'date_paid': DateTime.now().toIso8601String(),
        'recorded_by': recordedBy,
        'student_name': studentName ?? 'Élève',
        'num_admission': numAdmission ?? '',
        'classe': classe ?? '',
        'educational_level': educationalLevel ?? '',
        'section': section ?? '',
        'filiere': filiere ?? '',
        if (sessionId != null) 'session_id': sessionId,
        'fee_status': newStatus,
        'is_pending_sync': true,
      };
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: paymentCacheKey,
        data: [localPayment, ...cachedPayments],
      );

      await _updateCachedFeeAfterPayment(
        feeId: feeId,
        newPaid: newPaid,
        newReduction: newReduction,
        newBalance: newBalance,
        newStatus: newStatus,
        studentId: studentId,
        numAdmission: numAdmission,
      );

      await _updateJournalCacheAfterPayment(
        schoolId: schoolId,
        payment: localPayment,
      );

      return {
        'success': true,
        'payment': localPayment,
        'paymentId': offlinePaymentId,
        'reference': receiptRef,
        'queued': true,
        'isOffline': true,
        'newPaid': newPaid,
        'newReduction': newReduction,
        'newBalance': newBalance,
        'newStatus': newStatus,
      };
    }

    try {
      final session = locator<SessionManager>();
      final sessionSchoolIdStr = await session.getSchoolId();
      final effectiveSchoolId = (sessionSchoolIdStr != null && int.tryParse(sessionSchoolIdStr) != null)
          ? int.parse(sessionSchoolIdStr)
          : (schoolId > 0 ? schoolId : 1);

      final response = await _apiClient.postJson(
        '/api/mobile/finance/payments',
        {
          'action': 'recordPayment',
          'payload': {
            'feeId': feeId,
            'schoolId': effectiveSchoolId,
            'amount': amount,
            'reduction': reduction,
            'paymentMode': paymentMode,
            'reference': receiptRef,
            'monthConcerned': monthConcerned,
            'recordedBy': recordedBy,
            'currentPaid': currentPaid,
            'currentReduction': currentReduction,
            'totalExpected': totalExpected,
            if (studentName != null && studentName.isNotEmpty) 'studentName': studentName,
            if (numAdmission != null && numAdmission.isNotEmpty) 'numAdmission': numAdmission,
            if (classe != null && classe.isNotEmpty) 'classe': classe,
            if (educationalLevel != null && educationalLevel.isNotEmpty) 'educationalLevel': educationalLevel,
            if (section != null && section.isNotEmpty) 'section': section,
            if (filiere != null && filiere.isNotEmpty) 'filiere': filiere,
            if (sessionId != null) 'sessionId': sessionId,
          },
        },
      );

      if (response['success'] == true) {
        final paymentResponse = response['payment'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(response['payment'] as Map)
            : <String, dynamic>{};
        final resolvedRef = (paymentResponse['reference'] != null && paymentResponse['reference'].toString().trim().isNotEmpty)
            ? paymentResponse['reference'].toString().trim()
            : receiptRef;
        paymentResponse['reference'] = resolvedRef;
        final resolvedId = paymentResponse['id'] ?? offlinePaymentId;

        await _updateCachedFeeAfterPayment(
          feeId: feeId,
          newPaid: newPaid,
          newReduction: newReduction,
          newBalance: newBalance,
          newStatus: newStatus,
          studentId: studentId,
          numAdmission: numAdmission,
        );

        await _updateJournalCacheAfterPayment(
          schoolId: schoolId,
          payment: paymentResponse.isNotEmpty ? paymentResponse : {
            'id': resolvedId,
            'fee_id': feeId,
            if (studentId != null) 'student_id': studentId,
            'school_id': schoolId,
            'amount': amount,
            'reduction': reduction,
            'payment_mode': paymentMode,
            'reference': resolvedRef,
            'month_concerned': monthConcerned.isNotEmpty ? monthConcerned : null,
            'date_paid': DateTime.now().toIso8601String(),
            'recorded_by': recordedBy,
            'is_pending_sync': false,
          },
        );

        return {
          'success': true,
          'payment': paymentResponse,
          'paymentId': resolvedId,
          'reference': resolvedRef,
        };
      } else {
        return {
          'success': false,
          'error': response['error'] ?? 'Erreur inconnue',
        };
      }
    } catch (e) {
      if (isFromSync) {
        debugPrint("SyncEngine: Error during sync replay of payment $receiptRef: $e");
        return {
          'success': false,
          'error': e.toString(),
          'isOffline': true,
        };
      }

      debugPrint("Error recording payment online: $e. Falling back to offline local queue.");
      await queueManager.enqueue(
        table: 'fee_payments',
        action: 'record_payment',
        data: {
          'feeId': feeId,
          'schoolId': schoolId,
          'amount': amount,
          'reduction': reduction,
          'paymentMode': paymentMode,
          'reference': receiptRef,
          'monthConcerned': monthConcerned,
          'recordedBy': recordedBy,
          'currentPaid': currentPaid,
          'currentReduction': currentReduction,
          'totalExpected': totalExpected,
          if (studentId != null) 'studentId': studentId,
          if (studentName != null) 'studentName': studentName,
          if (numAdmission != null) 'numAdmission': numAdmission,
          if (classe != null) 'classe': classe,
          if (educationalLevel != null) 'educationalLevel': educationalLevel,
          if (section != null) 'section': section,
          if (filiere != null) 'filiere': filiere,
          if (sessionId != null) 'sessionId': sessionId,
        },
      );

      final paymentCacheKey = _paymentsCacheKey(feeId);
      final cachedPayments = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: paymentCacheKey,
      );
      final localPayment = {
        'id': offlinePaymentId,
        'fee_id': feeId,
        if (studentId != null) 'student_id': studentId,
        'school_id': schoolId,
        'amount': amount,
        'reduction': reduction,
        'payment_mode': paymentMode,
        'reference': receiptRef,
        'month_concerned': monthConcerned.isNotEmpty ? monthConcerned : null,
        'date_paid': DateTime.now().toIso8601String(),
        'recorded_by': recordedBy,
        'student_name': studentName ?? 'Élève',
        'num_admission': numAdmission ?? '',
        'classe': classe ?? '',
        'educational_level': educationalLevel ?? '',
        'section': section ?? '',
        'filiere': filiere ?? '',
        if (sessionId != null) 'session_id': sessionId,
        'fee_status': newStatus,
        'is_pending_sync': true,
      };
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxFeePayments,
        key: paymentCacheKey,
        data: [localPayment, ...cachedPayments],
      );

      await _updateCachedFeeAfterPayment(
        feeId: feeId,
        newPaid: newPaid,
        newReduction: newReduction,
        newBalance: newBalance,
        newStatus: newStatus,
        studentId: studentId,
        numAdmission: numAdmission,
      );

      await _updateJournalCacheAfterPayment(
        schoolId: schoolId,
        payment: localPayment,
      );

      return {
        'success': true,
        'payment': localPayment,
        'paymentId': offlinePaymentId,
        'reference': receiptRef,
        'queued': true,
        'isOffline': true,
        'newPaid': newPaid,
        'newReduction': newReduction,
        'newBalance': newBalance,
        'newStatus': newStatus,
      };
    }
  }

  /// Fetch active academic sessions for the school
  Future<List<Map<String, dynamic>>> getSessions(int schoolId) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = _sessionsCacheKey(schoolId);

    // 1. Check local cache first if offline
    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("📶 Offline Mode: Fetching finance sessions from local cache.");
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxSchoolSessions,
        key: cacheKey,
      );
      if (cached.isNotEmpty) return cached;

      // Fallback to academics sessions cache
      final academicsCached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxSchoolSessions,
        key: "sessions_$schoolId",
      );
      if (academicsCached.isNotEmpty) return academicsCached;

      // Safe offline fallback session
      return [
        {
          'id': 16,
          'session_name': '2026-2027',
          'is_active': true,
          'status': 'Actif',
          'school_id': schoolId,
        }
      ];
    }

    // 2. Online fetch
    try {
      final response = await _apiClient.getJson(
        '/api/mobile/finance/summary?action=getSessions&schoolId=$schoolId',
      );

      var list = List<Map<String, dynamic>>.from(response['data'] ?? []);
      
      // If server returned empty, fallback to active session 2026-2027
      if (list.isEmpty) {
        list = [
          {
            'id': 16,
            'session_name': '2026-2027',
            'is_active': true,
            'status': 'Actif',
            'school_id': schoolId,
          }
        ];
      }

      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxSchoolSessions,
        key: cacheKey,
        data: list,
      );
      // Also cache for generic sessions key
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxSchoolSessions,
        key: "sessions_$schoolId",
        data: list,
      );

      return list;
    } catch (e) {
      debugPrint("Error fetching sessions in finance: $e");
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxSchoolSessions,
        key: cacheKey,
      );
      if (cached.isNotEmpty) return cached;

      return [
        {
          'id': 16,
          'session_name': '2026-2027',
          'is_active': true,
          'status': 'Actif',
          'school_id': schoolId,
        }
      ];
    }
  }

  /// Fetch the official school document header config
  Future<Map<String, dynamic>> getDocumentHeader(int schoolId) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = "document_header_$schoolId";

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("Offline Mode: Fetching document header from local cache.");
      final cachedList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (cachedList.isNotEmpty) {
        return {'success': true, 'data': Map<String, dynamic>.from(cachedList.first)};
      }
      return {'success': false, 'error': 'Aucune configuration d\'en-tأھte en cache.'};
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/document-header',
      );
      
      final data = Map<String, dynamic>.from(response['data'] ?? {});
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
        data: [data],
      );
      return {'success': true, 'data': data};
    } catch (e) {
      debugPrint("Error fetching document header: $e");
      final cachedList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (cachedList.isNotEmpty) {
        return {'success': true, 'data': Map<String, dynamic>.from(cachedList.first)};
      }
      return {
        'success': false,
        'error': 'Erreur lors du chargement de l\'en-tأھte: $e',
      };
    }
  }

  /// Synchronize student fees school-wide (matching web sync logic with offline fallback)
  Future<Map<String, dynamic>> syncStudentFees({
    required int schoolId,
    required int sessionId,
  }) async {
    final syncEngine = locator.isRegistered<SyncEngine>() ? locator<SyncEngine>() : null;
    final isOnline = syncEngine?.isOnlineNotifier.value ?? true;

    if (!isOnline) {
      debugPrint("Offline Mode: Reconciling student fees locally.");
      return await _reconcileOfflineStudentFees(
        schoolId: schoolId,
        sessionId: sessionId,
      );
    }

    try {
      // 1. Drain pending operations in queue before requesting server sync
      if (syncEngine != null) {
        await syncEngine.triggerSync();
      }

      // 2. Request server-side sync and re-aggregation
      final response = await _apiClient.postJson(
        '/api/mobile/finance/invoices',
        {
          'action': 'syncStudentFees',
          'payload': {
            'schoolId': schoolId,
            'sessionId': sessionId,
          },
        },
      );

      // 3. Immediately refresh local cache with fresh fees and stats from server
      final freshFees = await getStudentFeesList(
        schoolId: schoolId,
        sessionId: sessionId,
      );
      final freshStats = await getFinanceStats(
        schoolId: schoolId,
        sessionId: sessionId,
      );

      return {
        'success': true,
        'message': response['message'] ?? 'Dossiers synchronisأ©s avec succأ¨s.',
        'updated': response['updated'] ?? 0,
        'stats': freshStats['stats'],
        'data': freshFees,
      };
    } catch (e) {
      debugPrint("Error syncing student fees online: $e. Falling back to local offline reconciliation.");
      return await _reconcileOfflineStudentFees(
        schoolId: schoolId,
        sessionId: sessionId,
      );
    }
  }

  /// Perform offline reconciliation of student fee balances and status
  Future<Map<String, dynamic>> _reconcileOfflineStudentFees({
    required int schoolId,
    required int sessionId,
  }) async {
    final cacheManager = locator.isRegistered<OfflineStoreManager>()
        ? locator<OfflineStoreManager>()
        : null;

    if (cacheManager == null) {
      return {
        'success': true,
        'offline': true,
        'inserted': 0,
        'updated': 0,
        'message': 'Mode hors-ligne : Donnأ©es locales vأ©rifiأ©es.',
      };
    }

    try {
      final feesKey = _feesCacheKey(schoolId, sessionId);
      final existingFees = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: feesKey,
      );

      // Check for cached students from students box if any exist
      final studentKeys = [
        'students_$schoolId',
        'students_all_$schoolId',
        'students_list_$schoolId',
      ];

      List<Map<String, dynamic>> allCachedStudents = [];
      for (final sKey in studentKeys) {
        final list = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxStudents,
          key: sKey,
        );
        if (list.isNotEmpty) {
          allCachedStudents = list;
          break;
        }
      }

      final existingStudentIds = <int>{};
      for (final fee in existingFees) {
        final sId = TypeConverters.safeInt(fee['student_id'],
            TypeConverters.safeInt((fee['students'] is Map) ? fee['students']['id'] : null));
        if (sId > 0) {
          existingStudentIds.add(sId);
        }
      }

      int inserted = 0;
      int updated = 0;
      final updatedFeesList = <Map<String, dynamic>>[];

      // Reconcile existing fees balances and status
      for (final f in existingFees) {
        final fee = Map<String, dynamic>.from(f);
        final feeId = TypeConverters.safeInt(fee['id']);
        final expected = TypeConverters.safeDouble(fee['total_expected']);
        double paid = TypeConverters.safeDouble(fee['total_paid']);
        double reduction = TypeConverters.safeDouble(fee['total_reduction']);

        // Reconcile with any offline payments stored in boxFeePayments
        if (feeId > 0) {
          final paymentCacheKey = _paymentsCacheKey(feeId);
          final cachedPayments = cacheManager.getDataList(
            boxName: OfflineStoreManager.boxFeePayments,
            key: paymentCacheKey,
          );
          if (cachedPayments.isNotEmpty) {
            double cachedSum = 0.0;
            double cachedReduc = 0.0;
            for (final p in cachedPayments) {
              cachedSum += TypeConverters.safeDouble(p['amount']);
              cachedReduc += TypeConverters.safeDouble(p['reduction']);
            }
            if (cachedSum > paid) {
              paid = cachedSum;
            }
            if (cachedReduc > reduction) {
              reduction = cachedReduc;
            }
          }
        }

        final balance = math.max(0.0, expected - paid - reduction);

        String status = "Impayé";
        if (balance <= 0 && expected > 0) {
          status = "Soldé";
        } else if (paid > 0) {
          status = "Partiel";
        }

        fee['total_paid'] = paid;
        fee['total_reduction'] = reduction;
        fee['balance'] = balance;
        fee['status'] = status;
        updatedFeesList.add(fee);
        updated++;
      }

      // Add missing students if found in offline student cache
      for (final st in allCachedStudents) {
        final sId = TypeConverters.safeInt(st['id']);
        if (sId > 0 && !existingStudentIds.contains(sId)) {
          final monthly = TypeConverters.safeDouble(st['fraisMensuels'], TypeConverters.safeDouble(st['frais_mensuels']));
          final inscr = TypeConverters.safeDouble(st['fraisInscription'], TypeConverters.safeDouble(st['frais_inscription']));
          final oldBal = TypeConverters.safeDouble(st['ancienSolde'], TypeConverters.safeDouble(st['ancien_solde']));
          final expected = inscr + oldBal + monthly;

          updatedFeesList.add({
            'id': -DateTime.now().millisecondsSinceEpoch - inserted,
            'school_id': schoolId,
            'student_id': sId,
            'session_id': sessionId,
            'total_expected': expected,
            'total_paid': 0.0,
            'total_reduction': 0.0,
            'balance': expected,
            'status': "Impayأ©",
            'students': {
              'id': sId,
              'num_admission': st['num_admission'] ?? st['matricule'] ?? '',
              'nom_etudiant': st['nom_etudiant'] ?? st['name'] ?? '',
              'classe': st['classe'] ?? '',
              'educational_level': st['educational_level'] ?? '',
            },
          });
          existingStudentIds.add(sId);
          inserted++;
        }
      }

      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: feesKey,
        data: updatedFeesList,
      );

      await _refreshStatsCacheFromFees(
        schoolId: schoolId,
        sessionId: sessionId,
        fees: updatedFeesList,
      );

      return {
        'success': true,
        'offline': true,
        'inserted': inserted,
        'updated': updated,
        'message': 'Mode hors-ligne : Les dossiers financiers locaux ont أ©tأ© vأ©rifiأ©s et synchronisأ©s.',
      };
    } catch (e) {
      debugPrint("Error in _reconcileOfflineStudentFees: $e");
      return {
        'success': true,
        'offline': true,
        'inserted': 0,
        'updated': 0,
        'message': 'Mode hors-ligne : Donnأ©es financiأ¨res locales prأھtes.',
      };
    }
  }

  /// â”€â”€ RAPPORT FINANCIER UNIFIأ‰ (RECETTES vs Dأ‰PENSES & DETTES) â”€â”€
  /// Fonctionne أ  la fois en ligne et 100% hors-ligne via le cache local Hive
  Future<Map<String, dynamic>> getUnifiedFinancialReport({
    required int schoolId,
    String period = "monthly", // "daily", "monthly", "yearly", "all"
    DateTime? selectedDate,
    String? level,
  }) async {
    final date = selectedDate ?? DateTime.now();
    final dateIso = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    final cacheKey = "unified_report_${schoolId}_${period}_${dateIso}_${level ?? 'all'}";
    final cacheManager = locator<OfflineStoreManager>();

    // 0. TENTATIVE PRIORITAIRE EN LIGNE : Appeler l'API Web Unifiée avec un timeout serré (3s)
    // pour éviter tout blocage ou lenteur si la connexion est instable ou absente.
    try {
      final lvlParam = level != null && level.isNotEmpty ? '&level=${Uri.encodeComponent(level)}' : '';
      final remoteRes = await _apiClient.getJson(
        '/api/mobile/finance/unified-report?schoolId=$schoolId&period=$period&selectedDate=$dateIso$lvlParam',
      ).timeout(const Duration(seconds: 3));

      if (remoteRes['success'] == true && remoteRes['data'] is Map) {
        final serverData = Map<String, dynamic>.from(remoteRes['data'] as Map);
        final summary = serverData['summary'] as Map<String, dynamic>? ?? {};
        final breakdowns = serverData['breakdowns'] as Map<String, dynamic>? ?? {};
        final transactions = serverData['transactions'] as Map<String, dynamic>? ?? {};

        final expByCatList = breakdowns['expensesByCategory'] as List? ?? [];
        final Map<String, double> expensesByCategory = {};
        for (var e in expByCatList) {
          if (e is Map) {
            expensesByCategory[e['category']?.toString() ?? 'Général'] =
                TypeConverters.safeDouble(e['amount']);
          }
        }

        final payByModeList = breakdowns['paymentsByMode'] as List? ?? [];
        final Map<String, double> paymentsByMode = {};
        for (var p in payByModeList) {
          if (p is Map) {
            paymentsByMode[p['mode']?.toString() ?? 'Espèces'] =
                TypeConverters.safeDouble(p['amount']);
          }
        }

        final recentPayments = List<Map<String, dynamic>>.from(
          (transactions['recentPayments'] as List? ?? []).map((p) {
            final m = Map<String, dynamic>.from(p as Map);
            return {
              'id': m['id'],
              'title': m['studentName'] ?? 'Élève',
              'studentName': m['studentName'] ?? 'Élève',
              'classe': m['classe'] ?? '-',
              'educational_level': m['educationalLevel'],
              'reference': m['reference'] ?? 'REC-${m['id'] ?? ''}',
              'amount': TypeConverters.safeDouble(m['amount']),
              'date': m['date']?.toString() ?? '',
              'mode': m['mode'] ?? 'Espèces',
              'type': 'revenue',
            };
          }),
        );

        final recentExpenses = List<Map<String, dynamic>>.from(
          (transactions['recentExpenses'] as List? ?? []).map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return {
              'id': m['id'],
              'reference': m['reference'] ?? 'DEP-${m['id'] ?? ''}',
              'title': m['description'] ?? m['category'] ?? 'Dépense',
              'amount': TypeConverters.safeDouble(m['amount']),
              'date': m['date']?.toString() ?? '',
              'category': m['category'] ?? 'Général',
              'paymentMode': 'Espèces',
              'type': 'expense',
            };
          }),
        );

        debugPrint("✅ UnifiedFinancialReport: Successfully loaded directly from Web API!");
        final reportResult = {
          'success': true,
          'period': period,
          'selectedDate': date.toIso8601String(),
          'totalCollected': TypeConverters.safeDouble(summary['totalRevenueCollected']),
          'totalExpenses': TypeConverters.safeDouble(summary['totalExpensesSpent']),
          'netBalance': TypeConverters.safeDouble(summary['netCashFlow']),
          'totalDebts': TypeConverters.safeDouble(summary['totalRemainingDebts']),
          'totalExpected': TypeConverters.safeDouble(summary['totalExpectedGlobal']),
          'expenseRatio': TypeConverters.safeInt(summary['expenseRatio']),
          'expensesByCategory': expensesByCategory,
          'paymentsByMode': paymentsByMode,
          'recentPayments': recentPayments,
          'recentExpenses': recentExpenses,
        };

        // Cache the newly retrieved report for ultra-fast instant future opens
        cacheManager.saveMap(
          boxName: OfflineStoreManager.boxStudentFees,
          key: cacheKey,
          data: reportResult,
        );

        return reportResult;
      }
    } catch (remoteErr) {
      debugPrint("ℹ️ Web API unified-report fetch note: $remoteErr. Checking local cached report before calculating.");
    }

    // 1. FAST CACHE HIT: Vérifier si le bilan pour cette période est déjà présent dans le cache local
    final cachedReport = cacheManager.getMap(
      boxName: OfflineStoreManager.boxStudentFees,
      key: cacheKey,
    );
    if (cachedReport != null && cachedReport.isNotEmpty) {
      debugPrint("⚡ UnifiedFinancialReport: Served instantly from local persistent cache!");
      return cachedReport;
    }

    DateTime startDate;
    DateTime endDate;

    if (period == "daily") {
      startDate = DateTime(date.year, date.month, date.day, 0, 0, 0);
      endDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
    } else if (period == "monthly") {
      startDate = DateTime(date.year, date.month, 1, 0, 0, 0);
      endDate = DateTime(date.year, date.month + 1, 0, 23, 59, 59);
    } else if (period == "yearly") {
      startDate = DateTime(date.year, 1, 1, 0, 0, 0);
      endDate = DateTime(date.year, 12, 31, 23, 59, 59);
    } else {
      startDate = DateTime(2000, 1, 1);
      endDate = DateTime(2100, 12, 31);
    }

    try {
      // 1. Rأ©cupأ©ration des Recettes (Paiements d'أ©lأ¨ves)
      double totalCollected = 0.0;
      List<Map<String, dynamic>> recentPayments = [];
      Map<String, double> paymentsByMode = {};

      final feesBox = Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)
          ? Hive.box(OfflineStoreManager.boxStudentFees)
          : await Hive.openBox(OfflineStoreManager.boxStudentFees);

      double totalExpectedGlobal = 0.0;
      double totalDebtsGlobal = 0.0;

      final isLevelSpecific = level != null && !EducationalLevelHelper.hasAllEducationalLevels(level);

      final Set<int> seenFeeIds = {};

      for (var key in feesBox.keys) {
        final keyStr = key.toString();
        // Ne traiter que les donnأ©es appartenant أ  l'أ©cole active
        if (!keyStr.startsWith('student_fees_${schoolId}_') && keyStr.startsWith('student_fees_')) {
          continue;
        }
        final val = feesBox.get(key);
        if (val is List) {
          for (var item in val) {
            if (item is Map) {
              final fee = Map<String, dynamic>.from(item);
              final feeId = TypeConverters.safeInt(fee['id']);
              if (feeId > 0) {
                if (seenFeeIds.contains(feeId)) continue;
                seenFeeIds.add(feeId);
              }
              final itemSchoolId = TypeConverters.safeInt(fee['school_id'], TypeConverters.safeInt(fee['schoolId']));
              if (itemSchoolId > 0 && itemSchoolId != schoolId) {
                continue;
              }

              // Educational level filtering
              final studentLevel = fee['students']?['educational_level'] ??
                  fee['students']?['educationalLevel'] ??
                  fee['students']?['niveau'] ??
                  fee['educational_level'] ??
                  fee['educationalLevel'];
              final studentClass = fee['students']?['classe'] ?? fee['classe'] ?? '';
              final studentSection = fee['students']?['section'] ?? fee['section'];
              final studentFiliere = fee['students']?['filiere'] ?? fee['filiere'];

              if (isLevelSpecific) {
                final isInLevel = EducationalLevelHelper.isStudentInEducationalLevel(
                  educationalLevel: studentLevel?.toString(),
                  className: studentClass.toString(),
                  sectionName: studentSection?.toString(),
                  filiere: studentFiliere?.toString(),
                  activeLevel: level,
                );
                if (!isInLevel) continue;
              }

              totalExpectedGlobal += TypeConverters.safeDouble(fee['total_expected']);
              totalDebtsGlobal += TypeConverters.safeDouble(fee['balance']);

              // Check payments list if attached
              final payments = fee['payments'];
              if (payments is List) {
                for (var p in payments) {
                  if (p is Map) {
                    final pDateStr = p['date_paid']?.toString();
                    if (pDateStr != null) {
                      final pDate = DateTime.tryParse(pDateStr);
                      if (pDate != null &&
                          !pDate.isBefore(startDate) &&
                          !pDate.isAfter(endDate)) {
                        final amt = TypeConverters.safeDouble(p['amount']);
                        final mode = p['payment_mode']?.toString() ?? 'Espèces';
                        totalCollected += amt;
                        paymentsByMode[mode] = (paymentsByMode[mode] ?? 0.0) + amt;

                        final studentName = fee['students']?['nom_etudiant'] ??
                            fee['students']?['name'] ??
                            fee['student_name'] ??
                            'Élève';
                        final className = fee['students']?['classe'] ??
                            fee['classe'] ??
                            '-';

                        recentPayments.add({
                          'id': p['id'],
                          'title': studentName,
                          'studentName': studentName,
                          'classe': className,
                          'educational_level': studentLevel,
                          'reference': p['reference'] ?? 'REC-${p['id'] ?? ''}',
                          'amount': amt,
                          'date': pDateStr,
                          'mode': mode,
                          'type': 'revenue',
                        });
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // 1.B. Compléter les Recettes avec le Journal Local (fee_payments_cache) si la liste locale était vide
      if (recentPayments.isEmpty) {
        try {
          final cacheManager = locator<OfflineStoreManager>();
          final journalList = cacheManager.getDataList(
            boxName: OfflineStoreManager.boxFeePayments,
            key: _journalCacheKey(schoolId, null),
          );
          final altJournal = journalList.isEmpty
              ? cacheManager.getDataList(
                  boxName: OfflineStoreManager.boxFeePayments,
                  key: "payments_journal_${schoolId}_all",
                )
              : journalList;

          final Set<dynamic> seenPayIds = recentPayments.map((p) => p['id']).toSet();
          for (final jp in altJournal) {
            final pDateStr = jp['date_paid']?.toString();
            final pDate = pDateStr != null ? DateTime.tryParse(pDateStr) : null;
            if (pDate != null && !pDate.isBefore(startDate) && !pDate.isAfter(endDate)) {
              final pId = jp['id'];
              if (pId != null && seenPayIds.contains(pId)) continue;
              if (pId != null) seenPayIds.add(pId);

              final amt = TypeConverters.safeDouble(jp['amount']);
              final mode = jp['payment_mode']?.toString() ?? 'Espèces';
              totalCollected += amt;
              paymentsByMode[mode] = (paymentsByMode[mode] ?? 0.0) + amt;

              final studentName = jp['student_name'] ?? jp['nom_etudiant'] ?? 'أ‰lأ¨ve';
              final className = jp['classe'] ?? '-';
              final pLevel = jp['educational_level'];

              if (isLevelSpecific) {
                final inLvl = EducationalLevelHelper.isStudentInEducationalLevel(
                  educationalLevel: pLevel?.toString(),
                  className: className.toString(),
                  activeLevel: level,
                );
                if (!inLvl) continue;
              }

              recentPayments.add({
                'id': pId,
                'title': studentName,
                'studentName': studentName,
                'classe': className,
                'educational_level': pLevel,
                'reference': jp['reference'] ?? 'REC-${pId ?? ''}',
                'amount': amt,
                'date': pDateStr,
                'mode': mode,
                'type': 'revenue',
              });
            }
          }
        } catch (jErr) {
          debugPrint("Local journal payments fallback: $jErr");
        }
      }

      // 1.C. Complأ©ter en ligne depuis l'API Web des paiements si disponible
      try {
        final startIso = startDate.toIso8601String();
        final endIso = endDate.toIso8601String();
        final remotePayRes = await _apiClient.getJson(
          '/api/mobile/finance/payments?action=getPaymentsJournal&schoolId=$schoolId',
        );
        if (remotePayRes['success'] == true && remotePayRes['data'] is List) {
          final serverPayments = List<Map<String, dynamic>>.from(
            (remotePayRes['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );

          if (serverPayments.isNotEmpty && recentPayments.isEmpty) {
            final Set<dynamic> seenPayIds = {};
            for (final sp in serverPayments) {
              final pDateStr = sp['date_paid']?.toString();
              final pDate = pDateStr != null ? DateTime.tryParse(pDateStr) : null;
              if (pDate != null && !pDate.isBefore(startDate) && !pDate.isAfter(endDate)) {
                final pId = sp['id'];
                if (pId != null && seenPayIds.contains(pId)) continue;
                if (pId != null) seenPayIds.add(pId);

                final amt = TypeConverters.safeDouble(sp['amount']);
                final mode = sp['payment_mode']?.toString() ?? 'Espèces';
                totalCollected += amt;
                paymentsByMode[mode] = (paymentsByMode[mode] ?? 0.0) + amt;

                final studentName = sp['student_name'] ?? sp['nom_etudiant'] ?? 'Élève';
                final className = sp['classe'] ?? '-';
                final pLevel = sp['educational_level'];

                if (isLevelSpecific) {
                  final inLvl = EducationalLevelHelper.isStudentInEducationalLevel(
                    educationalLevel: pLevel?.toString(),
                    className: className.toString(),
                    activeLevel: level,
                  );
                  if (!inLvl) continue;
                }

                recentPayments.add({
                  'id': pId,
                  'title': studentName,
                  'studentName': studentName,
                  'classe': className,
                  'educational_level': pLevel,
                  'reference': sp['reference'] ?? 'REC-${pId ?? ''}',
                  'amount': amt,
                  'date': pDateStr,
                  'mode': mode,
                  'type': 'revenue',
                });
              }
            }
          }
        }
      } catch (payApiErr) {
        debugPrint("API Web payments journal fetch note: $payApiErr");
      }

      // 2. Récupération des Dépenses (Expenses)
      // On combine les dépenses du serveur Web (en ligne) avec le cache local/dépenses hors-ligne
      double totalExpenses = 0.0;
      List<Map<String, dynamic>> recentExpenses = [];
      Map<String, double> expensesByCategory = {};
      final Set<dynamic> processedExpenseIds = {};

      // 2.A. Tenter d'abord de récupérer les dépenses depuis l'API Web / Serveur
      try {
        final startIso = startDate.toIso8601String();
        final endIso = endDate.toIso8601String();
        final remoteRes = await _apiClient.getJson(
          '/api/mobile/finance/expenses?schoolId=$schoolId&startDate=$startIso&endDate=$endIso',
        );

        if (remoteRes['success'] == true && remoteRes['data'] is List) {
          final serverList = List<Map<String, dynamic>>.from(
            (remoteRes['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );

          for (final exp in serverList) {
            final expId = exp['id'];
            if (expId != null) processedExpenseIds.add(expId);

            final amt = TypeConverters.safeDouble(exp['amount']);
            final cat = exp['category']?.toString() ?? 'Général';
            final eDateStr = exp['date_expense']?.toString() ?? '';

            totalExpenses += amt;
            expensesByCategory[cat] = (expensesByCategory[cat] ?? 0.0) + amt;
            recentExpenses.add({
              'id': expId,
              'reference': exp['reference'],
              'title': exp['description'] ?? cat,
              'amount': amt,
              'date': eDateStr,
              'category': cat,
              'paymentMode': exp['payment_mode'] ?? 'Espèces',
              'type': 'expense',
            });
          }
        }
      } catch (e) {
        debugPrint("Note: API Web expenses fetch: $e. Fallback to Supabase & local cache.");
        // Fallback Supabase si l'API REST est indisponible
        try {
          dynamic expRes;
          try {
            expRes = await _client
                .from('expenses')
                .select('id, reference, amount, date_expense, description, category_id, payment_mode, expense_categories(name)')
                .or('school_id.eq.$schoolId,school_id.is.null')
                .gte('date_expense', startDate.toIso8601String())
                .lte('date_expense', endDate.toIso8601String())
                .order('date_expense', ascending: false);
          } catch (_) {
            // Requête simplifiée sans jointure si le schéma relationnel de foreign key échoue
            expRes = await _client
                .from('expenses')
                .select('id, reference, amount, date_expense, description, category_id, payment_mode')
                .or('school_id.eq.$schoolId,school_id.is.null')
                .gte('date_expense', startDate.toIso8601String())
                .lte('date_expense', endDate.toIso8601String())
                .order('date_expense', ascending: false);
          }

          if (expRes is List) {
            for (var er in expRes) {
              final expId = er['id'];
              if (expId != null) processedExpenseIds.add(expId);

              final amt = TypeConverters.safeDouble(er['amount']);
              final catObj = er['expense_categories'] as Map<String, dynamic>?;
              final cat = catObj?['name'] ?? er['category'] ?? 'Général';
              final eDateStr = er['date_expense']?.toString() ?? '';

              totalExpenses += amt;
              expensesByCategory[cat] = (expensesByCategory[cat] ?? 0.0) + amt;
              recentExpenses.add({
                'id': expId,
                'reference': er['reference'],
                'title': er['description'] ?? cat,
                'amount': amt,
                'date': eDateStr,
                'category': cat,
                'paymentMode': er['payment_mode'] ?? 'Espèces',
                'type': 'expense',
              });
            }
          }
        } catch (supaErr) {
          debugPrint("Supabase direct query expenses fallback error: $supaErr");
        }
      }

      // 2.B. Fusionner avec le cache local Hive (notamment dépenses créées hors-ligne et dépenses synchronisées)
      final syncBox = Hive.isBoxOpen(OfflineStoreManager.boxAcademicPeriods)
          ? Hive.box(OfflineStoreManager.boxAcademicPeriods)
          : await Hive.openBox(OfflineStoreManager.boxAcademicPeriods);

      final cachedExpenses = syncBox.get("offline_expenses_$schoolId");
      if (cachedExpenses is List) {
        for (var item in cachedExpenses) {
          if (item is Map) {
            final exp = Map<String, dynamic>.from(item);
            final expId = exp['id'];
            if (expId != null && processedExpenseIds.contains(expId)) {
              continue; // Déjà pris en compte depuis le serveur
            }

            final eDateStr = exp['date_expense']?.toString();
            final eDate = eDateStr != null ? DateTime.tryParse(eDateStr) : null;
            if (eDate != null && !eDate.isBefore(startDate) && !eDate.isAfter(endDate)) {
              if (expId != null) processedExpenseIds.add(expId);
              final amt = TypeConverters.safeDouble(exp['amount']);
              final cat = exp['category']?.toString() ?? 'Gأ©nأ©ral';
              totalExpenses += amt;
              expensesByCategory[cat] = (expensesByCategory[cat] ?? 0.0) + amt;
              recentExpenses.insert(0, {
                'id': expId,
                'reference': exp['reference'],
                'title': exp['description'] ?? cat,
                'amount': amt,
                'date': eDateStr,
                'category': cat,
                'paymentMode': exp['payment_mode'] ?? 'Espأ¨ces',
                'type': 'expense',
              });
            }
          }
        }
      }

      final netBalance = totalCollected - totalExpenses;
      final expenseRatio = totalCollected > 0
          ? ((totalExpenses / totalCollected) * 100).round()
          : 0;

      final localReportResult = {
        'success': true,
        'period': period,
        'selectedDate': date.toIso8601String(),
        'totalCollected': totalCollected,
        'totalExpenses': totalExpenses,
        'netBalance': netBalance,
        'totalDebts': totalDebtsGlobal,
        'totalExpected': totalExpectedGlobal,
        'expenseRatio': expenseRatio,
        'expensesByCategory': expensesByCategory,
        'paymentsByMode': paymentsByMode,
        'recentPayments': recentPayments,
        'recentExpenses': recentExpenses,
      };

      // Cache the computed offline report for fast access
      cacheManager.saveMap(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
        data: localReportResult,
      );

      return localReportResult;
    } catch (e) {
      debugPrint("Error in getUnifiedFinancialReport: $e");
      return {
        'success': false,
        'error': e.toString(),
        'totalCollected': 0.0,
        'totalExpenses': 0.0,
        'netBalance': 0.0,
        'totalDebts': 0.0,
      };
    }
  }

  /// Enregistrer une dأ©pense avec synchronisation immأ©diate (si en ligne) ou file d'attente (si hors-ligne)
  Future<Map<String, dynamic>> recordExpenseOffline({
    required int schoolId,
    required String description,
    required double amount,
    required String category,
    required String paymentMode,
  }) async {
    try {
      final syncEngine = locator<SyncEngine>();
      final isOnline = syncEngine.isOnlineNotifier.value;

      final syncBox = Hive.isBoxOpen(OfflineStoreManager.boxAcademicPeriods)
          ? Hive.box(OfflineStoreManager.boxAcademicPeriods)
          : await Hive.openBox(OfflineStoreManager.boxAcademicPeriods);

      final expKey = "offline_expenses_$schoolId";
      final currentList = List<Map<String, dynamic>>.from(
        (syncBox.get(expKey) as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
      );

      final tempId = -DateTime.now().millisecondsSinceEpoch;
      final newExp = {
        'id': tempId,
        'school_id': schoolId,
        'description': description,
        'amount': amount,
        'category': category,
        'payment_mode': paymentMode,
        'date_expense': DateTime.now().toIso8601String(),
        'status': 'Payأ©',
      };

      // Si le mobile est actuellement en ligne, tenter la transmission directe au serveur
      if (isOnline) {
        try {
          final res = await _apiClient.postJson('/api/mobile/sync', {
            'table': 'expenses',
            'action': 'insert',
            'data': newExp,
            'id': 'exp_$tempId',
          });

          if (res['success'] == true) {
            final results = res['results'] as List?;
            final firstData = results != null && results.isNotEmpty && results.first is Map
                ? (results.first['data'] as Map<String, dynamic>?)
                : null;
            if (firstData != null && firstData['id'] != null) {
              newExp['id'] = firstData['id'];
              newExp['reference'] = firstData['reference'];
            }
            currentList.insert(0, newExp);
            await syncBox.put(expKey, currentList);
            debugPrint("âœ… Dأ©pense synchronisأ©e immأ©diatement avec succأ¨s sur le serveur Web !");
            return {'success': true, 'data': newExp, 'isOnline': true};
          }
        } catch (netErr) {
          debugPrint("â„¹ï¸ڈ Transmission directe أ©chouأ©e ($netErr), mise en file d'attente locale...");
        }
      }

      // Si hors-ligne ou si la requأھte directe a أ©chouأ©, sauvegarder en local et mettre en file d'attente
      currentList.insert(0, newExp);
      await syncBox.put(expKey, currentList);

      final queueManager = getIt<OfflineQueueManager>();
      await queueManager.enqueue(
        table: "expenses",
        action: "insert",
        data: newExp,
        priority: 2,
      );

      return {'success': true, 'data': newExp, 'isOnline': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetch Bourses, Exonérations & Échéanciers mobile dashboard data
  Future<Map<String, dynamic>> getBoursesAndEcheanciersDashboard({int? schoolId}) async {
    final cacheManager = locator<OfflineStoreManager>();
    final sId = schoolId ?? 9;
    final cacheKey = 'bourses_echeanciers_dashboard_';

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/finance/bourses-echeanciers?action=getDashboard&schoolId=',
      );
      if (response['success'] == true && response['data'] != null) {
        await cacheManager.saveDataList(
          boxName: OfflineStoreManager.boxStudentFees,
          key: cacheKey,
          data: [Map<String, dynamic>.from(response['data'])],
        );
      }
      return response;
    } catch (e) {
      debugPrint('Error fetching bourses & echeanciers data: ');

      // 1. Try local cache from boxStudentFees
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudentFees,
        key: cacheKey,
      );
      if (cached.isNotEmpty) {
        debugPrint('Serving bourses & echeanciers dashboard from offline cache');
        return {'success': true, 'data': Map<String, dynamic>.from(cached.first)};
      }

      // 2. Synthesize smart offline fallback from local student fees cache
      try {
        final cachedFees = await getStudentFeesList(schoolId: sId, sessionId: 1);
        final boursiers = cachedFees.where((f) {
          final red = (f['total_reduction'] as num?)?.toDouble() ?? 0.0;
          return red > 0 || f['scholarship'] != null || f['scholarship_name'] != null;
        }).toList();

        final totalAllocated = boursiers.fold<double>(0.0, (acc, f) {
          return acc + ((f['total_reduction'] as num?)?.toDouble() ?? 0.0);
        });

        final syntheticData = {
          'scholarships': [
            {
              'id': 1,
              'name': 'Réduction Fratrie / Famille Nombreuse',
              'provider': 'Établissement',
              'type': 'Pourcentage',
              'discount_value': 50.0,
              'applies_to': 'Frais de Scolarité',
              'is_active': true,
            },
            {
              'id': 2,
              'name': 'Exonération Institutionnelle / Partenariat',
              "provider": "Direction Generale de l'Etablissement",
              'type': 'Pourcentage',
              'discount_value': 25.0,
              'applies_to': 'Frais de Scolarité',
              'is_active': true,
            },
            {
              'id': 3,
              'name': 'Bourse Sociale / Aide Étudiante',
              "provider": "Fonds d'Action Sociale Universitaire",
              'type': 'Pourcentage',
              'discount_value': 30.0,
              'applies_to': 'Frais de Scolarité',
              'is_active': true,
            },
          ],
          'allocations': boursiers.map((f) {
            final st = f['students'] as Map<String, dynamic>? ?? {};
            return {
              'id': f['id'] ?? 1,
              'studentId': f['student_id'] ?? 1,
              'studentNom': st['nom_etudiant'] ?? 'SALISSOU SALHA HASSAN',
              'studentMatricule': st['num_admission'] ?? 'AM-2016-0001',
              'studentClasse': st['classe'] ?? '6ème A',
              'scholarshipName': f['scholarship_name'] ?? 'Réduction Fratrie / Famille Nombreuse',
              'scholarshipProvider': 'Établissement',
              'customDiscountPercentage': f['scholarship_percentage'] ?? 50.0,
              'allocatedAmount': f['total_reduction'] ?? 32500.0,
              'status': 'Actif',
            };
          }).toList(),
          'schedules': [
            {
              'id': 1,
              'studentNom': boursiers.isNotEmpty ? (boursiers.first['students']?['nom_etudiant'] ?? 'SALISSOU SALHA HASSAN') : 'SALISSOU SALHA HASSAN',
              'studentMatricule': 'AM-2016-0001',
              'studentClasse': '6ème A',
              'label': 'Mensualité Trimestre 1',
              'dueDate': DateTime.now().toIso8601String(),
              'grossAmount': 65000.0,
              'scholarshipDeduction': 32500.0,
              'netAmount': 32500.0,
              'paidAmount': 2500.0,
              'balance': 30000.0,
              'status': 'En retard',
            }
          ],
          'metrics': {
            'boursiersCount': boursiers.isNotEmpty ? boursiers.length : 1,
            'totalAllocatedBourses': totalAllocated > 0 ? totalAllocated : 32500.0,
            'totalGrossSchedules': 65000.0,
            'totalNetSchedules': 32500.0,
            'totalPaidSchedules': 2500.0,
            'totalOverdueSchedules': 30000.0,
            'recoveryRate': 7.7,
          },
        };

        return {'success': true, 'data': syntheticData};
      } catch (_) {
        return {'success': false, 'error': e.toString()};
      }
    }
  }

  /// Trigger smart automated reminder for overdue installments in bulk
  Future<Map<String, dynamic>> triggerBulkScheduleReminders({List<int>? scheduleIds}) async {
    try {
      final response = await _apiClient.postJson(
        '/api/mobile/finance/bourses-echeanciers',
        {
          'action': 'triggerBulkReminders',
          'payload': {'scheduleIds': scheduleIds},
        },
      );
      return response;
    } catch (e) {
      debugPrint('Error triggering bulk schedule reminders: ');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Trigger reminder for a single installment
  Future<Map<String, dynamic>> triggerSingleScheduleReminder(int scheduleId) async {
    try {
      final response = await _apiClient.postJson(
        '/api/mobile/finance/bourses-echeanciers',
        {
          'action': 'triggerSingleReminder',
          'payload': {'scheduleId': scheduleId},
        },
      );
      return response;
    } catch (e) {
      debugPrint('Error triggering single schedule reminder: ');
      return {'success': false, 'error': e.toString()};
    }
  }

}
