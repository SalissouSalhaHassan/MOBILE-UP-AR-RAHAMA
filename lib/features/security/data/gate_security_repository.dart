import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/api/mobile_api_client.dart';
import '../../../core/api/offline_store_manager.dart';
import '../../../core/di/injection.dart';

class GateSecurityRepository {
  final MobileApiClient _apiClient;

  GateSecurityRepository({MobileApiClient? apiClient})
      : _apiClient = apiClient ?? locator<MobileApiClient>();

  /// Scan a student QR code and retrieve instant security / gate status (Online + Offline fallback)
  Future<Map<String, dynamic>> scanGatePass({
    required String qrPayload,
    String? action, // 'scan', 'entry', 'exit'
    String? note,
  }) async {
    try {
      final res = await _apiClient.postJson(
        '/api/mobile/security/gate-scan',
        {
          'qrPayload': qrPayload.trim(),
          if (action != null) 'action': action,
          if (note != null) 'note': note,
        },
      );

      if (res['success'] == true || res['valid'] == true) {
        return res;
      }
      // Fall through to offline check if network returned error
      final offlineRes = _scanOffline(qrPayload.trim(), action);
      if (offlineRes != null) return offlineRes;
      return res;
    } catch (e) {
      debugPrint('Gate pass scan online error, trying offline cache: $e');
      final offlineRes = _scanOffline(qrPayload.trim(), action);
      if (offlineRes != null) return offlineRes;
      return {
        'success': false,
        'valid': false,
        'alertLevel': 'red',
        'message': 'Élève introuvable en mode hors-ligne. Synchronisez la liste des élèves.',
      };
    }
  }

  Map<String, dynamic>? _scanOffline(String raw, String? action) {
    try {
      if (!Hive.isBoxOpen(OfflineStoreManager.boxStudents)) return null;
      final box = Hive.box(OfflineStoreManager.boxStudents);

      String? targetId;
      String? targetMatricule = raw;

      if (raw.startsWith('EDUT-STU:')) {
        final parts = raw.split(':');
        if (parts.length >= 2) targetId = parts[1];
        if (parts.length >= 3) targetMatricule = parts[2];
      } else if (raw.startsWith('EDUT1.')) {
        try {
          final parts = raw.split('.');
          if (parts.length >= 2) {
            final normalized = base64Url.normalize(parts[1]);
            final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
            targetId = decoded['id']?.toString() ?? decoded['studentId']?.toString();
            targetMatricule = decoded['mat']?.toString() ?? decoded['numAdmission']?.toString();
          }
        } catch (_) {}
      }

      Map<String, dynamic>? matchedStudent;
      for (final val in box.values) {
        if (val is List) {
          for (final item in val) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final idStr = (map['id'] ?? '').toString();
              final matStr = (map['num_admission'] ?? map['numAdmission'] ?? map['matricule'] ?? '').toString();
              if ((targetId != null && idStr == targetId) ||
                  (targetMatricule != null && matStr.isNotEmpty && matStr.toLowerCase() == targetMatricule.toLowerCase())) {
                matchedStudent = map;
                break;
              }
            }
          }
        } else if (val is Map) {
          final map = Map<String, dynamic>.from(val);
          final idStr = (map['id'] ?? '').toString();
          final matStr = (map['num_admission'] ?? map['numAdmission'] ?? map['matricule'] ?? '').toString();
          if ((targetId != null && idStr == targetId) ||
              (targetMatricule != null && matStr.isNotEmpty && matStr.toLowerCase() == targetMatricule.toLowerCase())) {
            matchedStudent = map;
            break;
          }
        }
        if (matchedStudent != null) break;
      }

      if (matchedStudent == null) return null;

      final nom = (matchedStudent['nom_etudiant'] ?? matchedStudent['nomEtudiant'] ?? matchedStudent['nom'] ?? 'Élève').toString();
      final classe = (matchedStudent['classe'] ?? 'N/A').toString();
      final matricule = (matchedStudent['num_admission'] ?? matchedStudent['numAdmission'] ?? '').toString();
      final parentPhone = (matchedStudent['whatsapp'] ?? matchedStudent['mobile'] ?? '').toString();
      final solde = double.tryParse((matchedStudent['ancien_solde'] ?? matchedStudent['ancienSolde'] ?? '0').toString()) ?? 0;

      Map<String, dynamic>? whatsappAlert;
      if (parentPhone.isNotEmpty) {
        var cleanPhone = parentPhone.replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.length == 8) cleanPhone = '227$cleanPhone';
        final now = DateTime.now();
        final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final isExit = action == 'exit';
        final waText = '*U P AR-RAHAMA - MARADI • SÉCURITÉ CAMPUS* 🛡️\n\nBonjour Cher Parent,\nNous vous informons que votre enfant *$nom* ($classe) a été contrôlé au portail de l\'établissement (*${isExit ? "Sortie" : "Entrée"}*) à $timeStr.\n\n_Plateforme Numérique U P AR-RAHAMA_';
        whatsappAlert = {
          'phone': cleanPhone,
          'message': waText,
          'link': 'https://api.whatsapp.com/send?phone=$cleanPhone&text=${Uri.encodeComponent(waText)}',
        };
      }

      return {
        'success': true,
        'valid': true,
        'offline': true,
        'alertLevel': 'green',
        'decisionReason': 'Vérifié hors-ligne • Étudiant inscrit à U P AR-RAHAMA',
        'financialStatus': {
          'isUpToDate': solde <= 0,
          'balance': solde,
          'status': solde <= 0 ? 'En règle' : 'Impayé',
        },
        'whatsappAlert': whatsappAlert,
        'student': {
          'id': matchedStudent['id'],
          'nom': nom,
          'nomArabe': matchedStudent['nom_arabe'] ?? matchedStudent['nomArabe'],
          'matricule': matricule,
          'classe': classe,
          'photoUrl': matchedStudent['photo_path'] ?? matchedStudent['photoPath'],
          'groupeSanguin': matchedStudent['groupe_sanguin'] ?? matchedStudent['groupeSanguin'] ?? 'Non renseigné',
          'statut': matchedStudent['statut'] ?? 'Actif',
          'categorie': matchedStudent['categorie'] ?? 'Externe',
          'parentNom': matchedStudent['nom_pere'] ?? matchedStudent['nomPere'] ?? 'Parent',
          'parentPhone': parentPhone,
          'whatsapp': parentPhone,
        },
        'school': {
          'name': 'U P AR-RAHAMA',
        },
      };
    } catch (e) {
      debugPrint('Offline gate scan error: $e');
      return null;
    }
  }
}
