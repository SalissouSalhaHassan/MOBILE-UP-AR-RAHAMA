import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/api/supabase_client.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/di/injection.dart';
import '../../../core/api/mobile_api_client.dart';
import '../../../core/api/offline_store_manager.dart';
import '../../../core/api/offline_queue_manager.dart';
import '../../../core/api/sync_engine.dart';
import '../../../core/utils/type_converters.dart';

class StudentsRepository {
  final MobileApiClient _apiClient;
  final SupabaseClient _client;

  StudentsRepository({MobileApiClient? apiClient, SupabaseClient? client})
      : _apiClient = apiClient ?? MobileApiClient(),
        _client = client ?? SupabaseClientManager().client;

  static const String _studentsCacheKey = "students_list";

  Future<List<Map<String, dynamic>>> getStudentsList() async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final sessionManager = locator<SessionManager>();
    final schoolId = await sessionManager.getSchoolId();

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("📶 Offline Mode: Fetching students list from local cache.");
      return cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
    }

    try {
      final queryParam = schoolId != null && schoolId.isNotEmpty ? '?schoolId=$schoolId' : '';
      final response = await _apiClient.getJson('/api/mobile/students$queryParam');
      final list = List<Map<String, dynamic>>.from(response['data'] ?? []);
      
      // The server is the source of truth: always refresh the local cache,
      // even when the server list is empty (students deleted on the web must
      // disappear from the mobile app). Only students created offline and not
      // yet synchronised (temporary ids) are preserved.
      final serverAdmissions = list
          .map((s) => (s['num_admission'] ?? '').toString().trim().toLowerCase())
          .toSet();
      final previousCache = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
      final pendingLocal = previousCache.where((s) {
        final id = s['id']?.toString() ?? '';
        final adm = (s['num_admission'] ?? '').toString().trim().toLowerCase();
        return id.startsWith('temp_std_') && !serverAdmissions.contains(adm);
      }).toList();

      final merged = <Map<String, dynamic>>[...pendingLocal, ...list];

      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
        data: merged,
      );

      return merged;
    } catch (e) {
      debugPrint('Error fetching students list from API: $e. Attempting direct Supabase query fallback with chunked streaming...');
      try {
        var baseQuery = _client.from('students').select();
        if (schoolId != null && schoolId.isNotEmpty && schoolId != 'null') {
          final sIdInt = int.tryParse(schoolId);
          if (sIdInt != null) {
            baseQuery = baseQuery.eq('school_id', sIdInt);
          }
        }
        
        // Paged fetch: 100 items per batch
        const int pageSize = 100;
        int page = 0;
        bool hasMore = true;
        final List<Map<String, dynamic>> allFetched = [];

        while (hasMore) {
          final from = page * pageSize;
          final to = from + pageSize - 1;
          final pageRes = await baseQuery
              .order('nom_etudiant', ascending: true)
              .range(from, to);
          final pageList = List<Map<String, dynamic>>.from(pageRes as List);
          allFetched.addAll(pageList);

          if (pageList.length < pageSize) {
            hasMore = false;
          } else {
            page++;
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        if (allFetched.isNotEmpty) {
          await cacheManager.saveDataList(
            boxName: OfflineStoreManager.boxStudents,
            key: _studentsCacheKey,
            data: allFetched,
          );
          return allFetched;
        }
      } catch (directErr) {
        debugPrint('Direct Supabase query fallback failed: $directErr');
      }

      return cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
    }
  }

  Future<Map<String, dynamic>?> getStudentDetails(int studentId) async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    final cacheKey = "student_detail_$studentId";

    if (!syncEngine.isOnlineNotifier.value) {
      debugPrint("📶 Offline Mode: Fetching student details from local cache.");
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: cacheKey,
      );
      if (cached.isNotEmpty) {
        return cached.first;
      }
      
      // Fallback search in cached students list
      final allStudents = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
      try {
        final match = allStudents.firstWhere((s) => TypeConverters.safeInt(s['id']) == studentId);
        return match;
      } catch (_) {}
      return null;
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/students/$studentId',
      );
      final details = Map<String, dynamic>.from(response['data'] ?? {});
      if (details.isNotEmpty) {
        await cacheManager.saveDataList(
          boxName: OfflineStoreManager.boxStudents,
          key: cacheKey,
          data: [details],
        );
      }
      return details;
    } catch (e) {
      debugPrint('Error fetching student details: $e');
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: cacheKey,
      );
      if (cached.isNotEmpty) return cached.first;
      return null;
    }
  }

  Future<Map<String, dynamic>> getStudentFormOptions() async {
    final syncEngine = locator<SyncEngine>();
    final cacheManager = locator<OfflineStoreManager>();
    const cacheKey = "student_form_options";

    if (!syncEngine.isOnlineNotifier.value) {
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: cacheKey,
      );
      if (cached.isNotEmpty && cached.first.containsKey('levels')) {
        final item = cached.first;
        return {
          'levels': List<String>.from(item['levels'] ?? []),
          'sections': List<String>.from(item['sections'] ?? []),
          'classes': List<String>.from(item['classes'] ?? []),
          'sessions': List<String>.from(item['sessions'] ?? ['2026-2027']),
          'classesDetails': List<Map<String, dynamic>>.from(
            (item['classesDetails'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)),
          ),
        };
      }
      return _buildFallbackFormOptions();
    }

    try {
      final response = await _apiClient.getJson(
        '/api/mobile/students/0/summary?action=getStudentFormOptions',
      );

      final levels = List<String>.from(response['levels'] ?? []);
      final sections = List<String>.from(response['sections'] ?? []);
      final classes = List<String>.from(response['classes'] ?? []);
      final sessions = List<String>.from(response['sessions'] ?? ['2026-2027']);
      final classesDetails = List<Map<String, dynamic>>.from(
        (response['classesDetails'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)),
      );

      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: cacheKey,
        data: [
          {
            'levels': levels,
            'sections': sections,
            'classes': classes,
            'sessions': sessions,
            'classesDetails': classesDetails,
          }
        ],
      );

      return {
        'levels': levels,
        'sections': sections,
        'classes': classes,
        'sessions': sessions,
        'classesDetails': classesDetails,
      };
    } catch (e) {
      debugPrint('Error fetching student form options: $e');
      final cached = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: cacheKey,
      );
      if (cached.isNotEmpty && cached.first.containsKey('levels')) {
        final item = cached.first;
        return {
          'levels': List<String>.from(item['levels'] ?? []),
          'sections': List<String>.from(item['sections'] ?? []),
          'classes': List<String>.from(item['classes'] ?? []),
          'sessions': List<String>.from(item['sessions'] ?? ['2026-2027']),
          'classesDetails': List<Map<String, dynamic>>.from(
            (item['classesDetails'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)),
          ),
        };
      }
      return _buildFallbackFormOptions();
    }
  }

  /// Derives real options from local Hive caches if direct form options cache is missing
  Map<String, dynamic> _buildFallbackFormOptions() {
    final cacheManager = locator<OfflineStoreManager>();
    final Set<String> levels = {};
    final Set<String> sections = {};
    final Set<String> classes = {};
    final Set<String> sessions = {};
    final List<Map<String, dynamic>> classesDetails = [];

    // 1. Try from cached classes & subjects (OfflineStoreManager.boxClassSubjects)
    try {
      if (Hive.isBoxOpen(OfflineStoreManager.boxClassSubjects)) {
        final box = Hive.box(OfflineStoreManager.boxClassSubjects);
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw is List) {
            for (final elem in raw) {
              if (elem is Map) {
                final item = Map<String, dynamic>.from(elem);
                final cName = item['class_name'] ?? item['className'] ?? item['name'];
                final sName = item['section_name'] ?? item['sectionName'];
                final lName = item['educational_level'] ?? item['educationalLevel'] ?? item['level'];
                if (cName != null && cName.toString().trim().isNotEmpty) {
                  final cStr = cName.toString().trim();
                  classes.add(cStr);
                  classesDetails.add({
                    'id': item['id'],
                    'className': cStr,
                    'sectionName': sName?.toString() ?? '',
                    'educationalLevel': lName?.toString() ?? '',
                    'scolariteMensuelle': item['scolarite_mensuelle'] ?? item['scolariteMensuelle'] ?? 0,
                    'droitsInscription': item['droits_inscription'] ?? item['droitsInscription'] ?? 0,
                    'cogesCarteId': item['coges_carte_id'] ?? item['cogesCarteId'] ?? 0,
                    'transportInternat': item['transport_internat'] ?? item['transportInternat'] ?? 0,
                    'ancienSolde': item['ancien_solde'] ?? item['ancienSolde'] ?? 0,
                    'statutInitial': item['statut_initial'] ?? item['statutInitial'] ?? 'Actif',
                  });
                }
                if (sName != null && sName.toString().trim().isNotEmpty) {
                  sections.add(sName.toString().trim());
                }
                if (lName != null && lName.toString().trim().isNotEmpty) {
                  levels.add(lName.toString().trim());
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Try from cached students list (OfflineStoreManager.boxStudents)
    try {
      final cachedStudents = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
      for (final s in cachedStudents) {
        final cName = s['classe']?.toString().trim();
        final sName = s['section']?.toString().trim();
        final lName = s['educational_level']?.toString().trim();
        final sess = s['session']?.toString().trim();
        if (cName != null && cName.isNotEmpty) classes.add(cName);
        if (sName != null && sName.isNotEmpty) sections.add(sName);
        if (lName != null && lName.isNotEmpty) levels.add(lName);
        if (sess != null && sess.isNotEmpty) sessions.add(sess);
      }
    } catch (_) {}

    // 3. Try from cached sessions (OfflineStoreManager.boxSchoolSessions)
    try {
      if (Hive.isBoxOpen(OfflineStoreManager.boxSchoolSessions)) {
        final box = Hive.box(OfflineStoreManager.boxSchoolSessions);
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw is List) {
            for (final elem in raw) {
              if (elem is Map) {
                final item = Map<String, dynamic>.from(elem);
                final sessName = item['session_name'] ?? item['name'] ?? item['session'];
                if (sessName != null && sessName.toString().trim().isNotEmpty) {
                  sessions.add(sessName.toString().trim());
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    final finalLevels = levels.isNotEmpty ? (levels.toList()..sort()) : ['Primaire', 'Collège', 'Lycée'];
    final finalSections = sections.isNotEmpty ? (sections.toList()..sort()) : ['Générale'];
    final finalClasses = classes.isNotEmpty ? (classes.toList()..sort()) : ['6ème A', '5ème A', '4ème A', '3ème A', '2nde A', '1ère A', 'Tle A'];
    final finalSessions = sessions.isNotEmpty ? sessions.toList() : ['2026-2027'];

    return {
      'levels': finalLevels,
      'sections': finalSections,
      'classes': finalClasses,
      'sessions': finalSessions,
      'classesDetails': classesDetails,
    };
  }

  String _sessionsCacheKey(int schoolId) => "finance_sessions_$schoolId";

  /// Checks whether an academic session is closed, archived, or locked
  bool isSessionFrozen({int? sessionId, String? sessionName, int? schoolId}) {
    try {
      final cacheManager = locator<OfflineStoreManager>();
      List<Map<String, dynamic>> sessionList = [];

      if (schoolId != null && schoolId > 0) {
        sessionList = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxSchoolSessions,
          key: _sessionsCacheKey(schoolId),
        );
        if (sessionList.isEmpty) {
          sessionList = cacheManager.getDataList(
            boxName: OfflineStoreManager.boxSchoolSessions,
            key: "sessions_$schoolId",
          );
        }
      }

      if (sessionList.isEmpty && Hive.isBoxOpen(OfflineStoreManager.boxSchoolSessions)) {
        final box = Hive.box(OfflineStoreManager.boxSchoolSessions);
        for (final k in box.keys) {
          final data = box.get(k);
          if (data is List && data.isNotEmpty) {
            sessionList = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            break;
          }
        }
      }

      for (final s in sessionList) {
        final sId = TypeConverters.safeInt(s['id']);
        final sName = s['session_name']?.toString() ?? s['name']?.toString() ?? '';
        final matchesId = sessionId != null && sessionId > 0 && sId == sessionId;
        final matchesName = sessionName != null && sessionName.trim().isNotEmpty &&
            sName.trim().toLowerCase() == sessionName.trim().toLowerCase();

        if (matchesId || matchesName) {
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
      }
    } catch (e) {
      debugPrint("Error checking isSessionFrozen in StudentsRepository: $e");
    }
    return false;
  }

  Future<Map<String, dynamic>> saveStudent({
    int? studentId,
    required Map<String, dynamic> payload,
  }) async {
    final syncEngine = locator<SyncEngine>();
    final isOnline = syncEngine.isOnlineNotifier.value;
    final queueManager = locator<OfflineQueueManager>();
    final cacheManager = locator<OfflineStoreManager>();

    final dataToSend = Map<String, dynamic>.from(payload);
    if (studentId != null) {
      dataToSend['id'] = studentId;
    }

    final schoolId = TypeConverters.safeInt(dataToSend['school_id']);
    final sessionId = TypeConverters.safeInt(dataToSend['session_id']);
    final sessionName = dataToSend['session']?.toString() ?? dataToSend['annee_scolaire']?.toString();

    if (isSessionFrozen(sessionId: sessionId > 0 ? sessionId : null, sessionName: sessionName, schoolId: schoolId > 0 ? schoolId : null)) {
      return {
        'success': false,
        'error': "Impossible d'enregistrer l'élève : l'année scolaire sélectionnée est clôturée ou verrouillée. Les inscriptions y sont gelées.",
      };
    }

    if (!isOnline) {
      final localTempId = "temp_std_${DateTime.now().millisecondsSinceEpoch}";
      dataToSend['localId'] = localTempId;
      dataToSend['id'] = localTempId;

      await queueManager.enqueue(
        table: 'students',
        action: 'create_student',
        data: dataToSend,
        priority: 1,
      );

      // Optimistic update in Hive students list
      final currentList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
      currentList.insert(0, dataToSend);
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
        data: currentList,
      );

      // Optimistically insert into Gestion Financière cache
      await _createOptimisticFeeForStudent(dataToSend, localTempId);

      return {
        'success': true,
        'isOffline': true,
        'localId': localTempId,
        'message': 'Élève enregistré localement en mode hors-ligne.',
      };
    }

    try {
      final response = await _apiClient.postJson(
        '/api/mobile/students',
        {
          'action': 'saveStudent',
          'payload': dataToSend,
        },
      );
      return response;
    } catch (e) {
      debugPrint('Error saving student online, falling back to offline queue: $e');
      final localTempId = "temp_std_${DateTime.now().millisecondsSinceEpoch}";
      dataToSend['localId'] = localTempId;
      dataToSend['id'] = localTempId;

      await queueManager.enqueue(
        table: 'students',
        action: 'create_student',
        data: dataToSend,
        priority: 1,
      );

      // Optimistic update in Hive students list
      final currentList = cacheManager.getDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
      );
      currentList.insert(0, dataToSend);
      await cacheManager.saveDataList(
        boxName: OfflineStoreManager.boxStudents,
        key: _studentsCacheKey,
        data: currentList,
      );

      // Optimistically insert into Gestion Financière cache
      await _createOptimisticFeeForStudent(dataToSend, localTempId);

      return {
        'success': true,
        'isOffline': true,
        'localId': localTempId,
        'message': 'Connexion instable. Élève mis en file d\'attente de synchronisation.',
      };
    }
  }

  Future<void> _createOptimisticFeeForStudent(Map<String, dynamic> studentData, dynamic studentId) async {
    try {
      if (!Hive.isBoxOpen(OfflineStoreManager.boxStudentFees)) {
        await Hive.openBox(OfflineStoreManager.boxStudentFees);
      }
      final box = Hive.box(OfflineStoreManager.boxStudentFees);

      final monthly = TypeConverters.safeDouble(studentData['frais_mensuels']);
      final registration = TypeConverters.safeDouble(studentData['frais_inscription']);
      final coges = TypeConverters.safeDouble(studentData['frais_coges_card'], 1500.0);
      final transport = TypeConverters.safeDouble(studentData['frais_transport_internat']);
      final prevBalance = TypeConverters.safeDouble(studentData['ancien_solde']);

      final isPrimary = (studentData['educational_level']?.toString().toLowerCase().contains('prim') ?? false) ||
          (studentData['educational_level']?.toString().toLowerCase().contains('mater') ?? false) ||
          (studentData['classe']?.toString().toUpperCase().contains('CE') ?? false) ||
          (studentData['classe']?.toString().toUpperCase().contains('CM') ?? false) ||
          (studentData['classe']?.toString().toUpperCase().contains('CI') ?? false) ||
          (studentData['classe']?.toString().toUpperCase().contains('CP') ?? false);

      double tuition;
      if (monthly >= 30000.0 || (isPrimary && monthly >= 20000.0)) {
        // The entered amount is already the full annual tuition, NOT monthly
        tuition = monthly;
      } else if (monthly > 0) {
        tuition = monthly * 9.0;
      } else {
        tuition = isPrimary ? 40000.0 : 0.0;
      }

      double totalExpected = tuition + registration + coges + transport + prevBalance;
      if (isPrimary && (totalExpected > 75000.0 || totalExpected <= 0.0)) {
        // Enforce realistic school fee ceiling for primary level
        totalExpected = 45000.0;
      }
      final feeId = DateTime.now().millisecondsSinceEpoch;

      final session = locator<SessionManager>();
      final sessionSchoolIdStr = await session.getSchoolId();
      final effectiveSchoolId = (sessionSchoolIdStr != null && int.tryParse(sessionSchoolIdStr) != null)
          ? int.parse(sessionSchoolIdStr)
          : (studentData['school_id'] as int? ?? 1);

      // Dynamically resolve active session ID
      int resolvedSessionId = 16;
      if (studentData['session_id'] != null && int.tryParse(studentData['session_id'].toString()) != null) {
        resolvedSessionId = int.parse(studentData['session_id'].toString());
      } else if (studentData['sessionId'] != null && int.tryParse(studentData['sessionId'].toString()) != null) {
        resolvedSessionId = int.parse(studentData['sessionId'].toString());
      } else {
        // Look in cached finance sessions or academic periods
        final cacheManager = locator<OfflineStoreManager>();
        final cachedSessions = cacheManager.getDataList(
          boxName: OfflineStoreManager.boxSchoolSessions,
          key: "finance_sessions_$effectiveSchoolId",
        );
        if (cachedSessions.isNotEmpty) {
          final active = cachedSessions.firstWhere(
            (s) => s['is_active'] == true || s['status']?.toString().toLowerCase() == 'actif',
            orElse: () => cachedSessions.first,
          );
          if (active['id'] != null && int.tryParse(active['id'].toString()) != null) {
            resolvedSessionId = int.parse(active['id'].toString());
          }
        }
      }

      final feeRecord = <String, dynamic>{
        'id': feeId,
        'student_id': studentId,
        'school_id': effectiveSchoolId,
        'session_id': resolvedSessionId,
        'total_expected': totalExpected > 0 ? totalExpected : 45000.0,
        'total_paid': 0.0,
        'total_reduction': 0.0,
        'balance': totalExpected > 0 ? totalExpected : 45000.0,
        'status': 'Impayé',
        'is_offline_draft': true,
        'students': {
          'id': studentId,
          'nom_etudiant': studentData['nom_etudiant'] ?? 'Nouvel Élève',
          'num_admission': studentData['num_admission'] ?? 'AM-2026-TEMP',
          'classe': studentData['classe'] ?? '',
          'educational_level': studentData['educational_level'] ?? '',
          'section': studentData['section'] ?? '',
          'mobile': studentData['mobile'] ?? '',
          'nom_pere': studentData['nom_pere'] ?? '',
        },
      };

      // Find all student_fees keys in boxStudentFees and prepend new student fee
      final feeKeys = box.keys.map((k) => k.toString()).where((k) => k.startsWith('student_fees_')).toSet();
      feeKeys.add('student_fees_${effectiveSchoolId}_$resolvedSessionId');
      feeKeys.add('student_fees_${effectiveSchoolId}_16');
      feeKeys.add('student_fees_1_16');
      feeKeys.add('student_fees_1_1');

      for (final key in feeKeys) {
        final existingRaw = box.get(key);
        final list = (existingRaw is List)
            ? existingRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        list.insert(0, feeRecord);
        await box.put(key, list);

        // Update corresponding stats key
        final statsKey = key.replaceFirst('student_fees_', 'finance_stats_');
        final currentStatsList = box.get(statsKey);
        if (currentStatsList is List && currentStatsList.isNotEmpty && currentStatsList.first is Map) {
          final statsMap = Map<String, dynamic>.from(currentStatsList.first as Map);
          final innerStats = statsMap['stats'] is Map ? Map<String, dynamic>.from(statsMap['stats'] as Map) : <String, dynamic>{};
          innerStats['totalExpected'] = TypeConverters.safeDouble(innerStats['totalExpected']) + TypeConverters.safeDouble(feeRecord['total_expected']);
          innerStats['totalDebts'] = TypeConverters.safeDouble(innerStats['totalDebts']) + TypeConverters.safeDouble(feeRecord['balance']);
          statsMap['stats'] = innerStats;
          await box.put(statsKey, [statsMap]);
        }
      }
      debugPrint("✅ Optimistic fee generated and cached for student $studentId across keys: $feeKeys");
    } catch (e) {
      debugPrint("⚠️ Warning generating optimistic student fee: $e");
    }
  }

  Future<Map<String, dynamic>> getPromotionOptions() async {
    try {
      final response = await _apiClient.getJson(
        '/api/mobile/students/0/summary?action=getPromotionOptions',
      );
      final classes = List<Map<String, dynamic>>.from(response['classes'] ?? []);
      final sessions = List<Map<String, dynamic>>.from(response['sessions'] ?? []);

      return {
        'classes': classes,
        'sessions': sessions,
      };
    } catch (e) {
      debugPrint('Error fetching promotion options: $e');
      return {
        'classes': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
      };
    }
  }

  Future<List<Map<String, dynamic>>> getPromotionHistory({
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.getJson(
        '/api/mobile/students/0/summary?action=getPromotionHistory&limit=$limit',
      );
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    } catch (e) {
      debugPrint('Error fetching promotion history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPromotionPreview({
    required List<Map<String, dynamic>> students,
    String? targetClass,
    String? targetSession,
  }) async {
    try {
      if (students.isEmpty) return [];

      final studentIds = students
          .map((row) => row['id'])
          .whereType<int>()
          .toList();

      final response = await _apiClient.getJson(
        '/api/mobile/students/0/summary?action=getPromotionPreview&studentIds=${studentIds.join(',')}',
      );

      final previewList = List<Map<String, dynamic>>.from(response['data'] ?? []);
      final statsMap = {
        for (var p in previewList)
          (p['id'] as num).toInt(): p
      };

      return students.map((student) {
        final studentId = TypeConverters.safeInt(student['id']);
        final stats = statsMap[studentId];
        final average = stats?['calculated_average'] != null ? TypeConverters.safeDouble(stats?['calculated_average']) : null;
        final recommendation = stats?['recommendation']?.toString() ?? 'A verifier';

        return {
          ...student,
          'target_class': targetClass,
          'target_session': targetSession,
          'calculated_average': average,
          'recommendation': recommendation,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching promotion preview: $e');
      return students
          .map(
            (student) => {
              ...student,
              'target_class': targetClass,
              'target_session': targetSession,
              'calculated_average': null,
              'recommendation': 'A verifier',
            },
          )
          .toList();
    }
  }

  Future<Map<String, dynamic>> promoteStudents({
    required List<int> studentIds,
    required String targetClass,
    required String targetSession,
    required bool transferBalance,
  }) async {
    try {
      if (studentIds.isEmpty) {
        return {'success': false, 'error': 'Aucun étudiant sélectionné.'};
      }

      if (isSessionFrozen(sessionName: targetSession)) {
        return {
          'success': false,
          'error': "Impossible d'effectuer la promotion : l'année scolaire de destination ($targetSession) est clôturée ou verrouillée.",
        };
      }

      final response = await _apiClient.postJson(
        '/api/mobile/students',
        {
          'action': 'promoteStudents',
          'payload': {
            'studentIds': studentIds,
            'targetClass': targetClass,
            'targetSession': targetSession,
            'transferBalance': transferBalance,
          },
        },
      );
      return response;
    } catch (e) {
      debugPrint('Error promoting students: $e');
      return {'success': false, 'error': '$e'};
    }
  }
}
