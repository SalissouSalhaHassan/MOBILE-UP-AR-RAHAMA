import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/di/injection.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/students_repository.dart';

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({
    super.key,
    this.initialData,
  });

  final Map<String, dynamic>? initialData;

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final StudentsRepository _repository = locator<StudentsRepository>();
  final _formKey = GlobalKey<FormState>();

  int _currentStep = 0; // 0: Profil & Identité, 1: Dossier Famille, 2: Plan Financier

  // Step 1: Identité & Profil
  late final TextEditingController _admissionController;
  late final TextEditingController _nameController;
  late final TextEditingController _arabicNameController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _birthPlaceController;
  late final TextEditingController _religionController;
  late final TextEditingController _cnicController;
  late final TextEditingController _pinController;
  String _selectedSexe = 'Garcon';
  String? _selectedBloodGroup;
  String? _fingerprintHash;
  String? _photoPath;

  // Step 2: Dossier Famille & Contacts
  late final TextEditingController _fatherController;
  late final TextEditingController _fatherCnicController;
  late final TextEditingController _mobileController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _fatherQualificationController;
  late final TextEditingController _phoneFixeController;

  // Académique
  String? _selectedSession;
  String? _selectedLevel;
  String? _selectedClass;
  String? _selectedSection;
  String _selectedCategory = 'Général';
  String _selectedStatus = 'Actif';
  late final TextEditingController _behaviorController;

  // Step 3: Plan Financier & Scolarité
  late final TextEditingController _monthlyController;
  late final TextEditingController _registrationController;
  late final TextEditingController _balanceController;
  late final TextEditingController _cogesCardController;
  late final TextEditingController _transportInternatController;

  final ImagePicker _imagePicker = ImagePicker();

  bool _isSaving = false;
  bool _isLoadingOptions = true;
  bool _hasFormPermission = false;

  List<String> _sessions = ['2026-2027'];
  List<String> _levels = [];
  List<String> _sections = [];
  List<String> _classes = [];
  List<Map<String, dynamic>> _classesDetails = [];

  bool get _isEdit => widget.initialData?['id'] != null;

  bool get _isSessionFrozen => _repository.isSessionFrozen(sessionName: _selectedSession);

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};

    // 1. Identité
    _admissionController = TextEditingController(text: data['num_admission']?.toString() ?? '');
    _nameController = TextEditingController(text: data['nom_etudiant']?.toString() ?? '');
    _arabicNameController = TextEditingController(text: data['nom_arabe']?.toString() ?? '');
    _birthDateController = TextEditingController(text: data['date_naissance']?.toString() ?? '');
    _birthPlaceController = TextEditingController(text: data['lieu_naissance']?.toString() ?? '');
    _religionController = TextEditingController(text: data['religion']?.toString() ?? '');
    _cnicController = TextEditingController(text: data['cnic']?.toString() ?? '');
    _pinController = TextEditingController(text: data['activation_pin']?.toString() ?? '');
    _selectedSexe = _normalizeSexe(data['sexe']?.toString());
    _selectedBloodGroup = data['groupe_sanguin']?.toString();
    _fingerprintHash = data['fingerprint_hash']?.toString();
    _photoPath = data['photo_path']?.toString();

    // 2. Famille
    _fatherController = TextEditingController(text: data['nom_pere']?.toString() ?? '');
    _fatherCnicController = TextEditingController(text: data['cnic_pere']?.toString() ?? '');
    _mobileController = TextEditingController(text: data['mobile']?.toString() ?? '');
    _whatsappController = TextEditingController(text: data['whatsapp']?.toString() ?? '');
    _fatherQualificationController = TextEditingController(text: data['father_qualification']?.toString() ?? '');
    _phoneFixeController = TextEditingController(text: data['phone_fixe']?.toString() ?? '');

    // Académique
    _selectedSession = data['session']?.toString() ?? '2026-2027';
    _selectedLevel = data['educational_level']?.toString();
    _selectedSection = data['section']?.toString();
    _selectedClass = data['classe']?.toString();
    _selectedCategory = data['categorie']?.toString() ?? 'Général';
    _selectedStatus = data['statut']?.toString() ?? 'Actif';
    _behaviorController = TextEditingController(text: data['behavior_score']?.toString() ?? '18');

    // 3. Finances
    _monthlyController = TextEditingController(text: data['frais_mensuels']?.toString() ?? '0');
    _registrationController = TextEditingController(text: data['frais_inscription']?.toString() ?? '0');
    _balanceController = TextEditingController(text: data['ancien_solde']?.toString() ?? '0');
    _cogesCardController = TextEditingController(text: data['frais_coges_card']?.toString() ?? '1500');
    _transportInternatController = TextEditingController(text: data['frais_transport_internat']?.toString() ?? '0');

    _loadOptions();
  }

  @override
  void dispose() {
    _admissionController.dispose();
    _nameController.dispose();
    _arabicNameController.dispose();
    _birthDateController.dispose();
    _birthPlaceController.dispose();
    _religionController.dispose();
    _cnicController.dispose();
    _pinController.dispose();

    _fatherController.dispose();
    _fatherCnicController.dispose();
    _mobileController.dispose();
    _whatsappController.dispose();
    _fatherQualificationController.dispose();
    _phoneFixeController.dispose();

    _behaviorController.dispose();
    _monthlyController.dispose();
    _registrationController.dispose();
    _balanceController.dispose();
    _cogesCardController.dispose();
    _transportInternatController.dispose();
    super.dispose();
  }

  String _normalizeSexe(String? value) {
    final raw = (value ?? '').toLowerCase();
    if (raw.contains('f')) return 'Fille';
    return 'Garcon';
  }

  void _generateRandomPin() {
    final pin = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    setState(() {
      _pinController.text = pin;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _photoPath = base64Image;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photographie enregistrée !'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking photo: $e');
    }
  }

  void _applyClassFees(String? className) {
    if (className == null || className.isEmpty) return;
    final cls = _classesDetails.firstWhere(
      (c) => c['className']?.toString() == className,
      orElse: () => <String, dynamic>{},
    );

    if (cls.isNotEmpty) {
      final monthly = cls['scolariteMensuelle'];
      final registration = cls['droitsInscription'];
      final coges = cls['cogesCarteId'];
      final transport = cls['transportInternat'];
      final balance = cls['ancienSolde'];
      final initialStatus = cls['statutInitial'];

      final infLevel = cls['educationalLevel']?.toString();
      final infSection = cls['sectionName']?.toString();

      setState(() {
        if (infLevel != null && infLevel.isNotEmpty && _levels.contains(infLevel)) {
          _selectedLevel = infLevel;
        }
        if (infSection != null && infSection.isNotEmpty && _sections.contains(infSection)) {
          _selectedSection = infSection;
        }
        if (initialStatus != null && initialStatus.toString().isNotEmpty) {
          _selectedStatus = initialStatus.toString();
        }

        if (!_isEdit || _monthlyController.text.isEmpty || _monthlyController.text == '0') {
          _monthlyController.text = (monthly ?? 0).toString();
        }
        if (!_isEdit || _registrationController.text.isEmpty || _registrationController.text == '0') {
          _registrationController.text = (registration ?? 0).toString();
        }
        if (!_isEdit || _cogesCardController.text.isEmpty || _cogesCardController.text == '0') {
          _cogesCardController.text = (coges ?? 1500).toString();
        }
        if (!_isEdit || _transportInternatController.text.isEmpty) {
          _transportInternatController.text = (transport ?? 0).toString();
        }
        if (!_isEdit || _balanceController.text.isEmpty) {
          _balanceController.text = (balance ?? 0).toString();
        }
      });
    }
  }

  Future<void> _loadOptions() async {
    try {
      try {
        await locator<PermissionService>().getCurrentProfile();
      } catch (_) {}
      final options = await _repository.getStudentFormOptions();
      if (!mounted) return;
      setState(() {
        _hasFormPermission = true;
        _sessions = (options['sessions'] != null && (options['sessions'] as List).isNotEmpty)
            ? List<String>.from(options['sessions'])
            : ['2026-2027'];
        _levels = (options['levels'] != null && (options['levels'] as List).isNotEmpty)
            ? List<String>.from(options['levels'])
            : ['Primaire', 'Collège', 'Lycée'];
        _sections = (options['sections'] != null && (options['sections'] as List).isNotEmpty)
            ? List<String>.from(options['sections'])
            : ['Primaire Général', 'Section A'];
        _classes = (options['classes'] != null && (options['classes'] as List).isNotEmpty)
            ? List<String>.from(options['classes'])
            : ['CE1 A', '6ème A'];
        _classesDetails = (options['classesDetails'] != null)
            ? List<Map<String, dynamic>>.from(options['classesDetails'])
            : [];

        _selectedSession ??= _sessions.first;
        _selectedLevel ??= _levels.first;
        _selectedSection ??= _sections.first;
        _selectedClass ??= _classes.first;

        // Auto-fill financial fees if creating a new student
        if (!_isEdit && _selectedClass != null) {
          _applyClassFees(_selectedClass);
        }
      });
    } catch (e) {
      debugPrint('Error loading form options: $e');
      if (!mounted) return;
      setState(() {
        _hasFormPermission = true;
        _sessions = ['2026-2027'];
        _levels = ['Primaire', 'Collège', 'Lycée'];
        _sections = ['Primaire Général', 'Section A'];
        _classes = ['CE1 A', '6ème A'];
        _classesDetails = [];
        _selectedSession ??= _sessions.first;
        _selectedLevel ??= _levels.first;
        _selectedSection ??= _sections.first;
        _selectedClass ??= _classes.first;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOptions = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_isSessionFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("L'année scolaire sélectionnée est clôturée ou verrouillée. Les inscriptions y sont gelées."),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final payload = {
      'num_admission': _admissionController.text.trim(),
      'nom_etudiant': _nameController.text.trim(),
      'nom_arabe': _arabicNameController.text.trim(),
      'sexe': _selectedSexe,
      'date_naissance': _birthDateController.text.trim(),
      'lieu_naissance': _birthPlaceController.text.trim(),
      'religion': _religionController.text.trim(),
      'cnic': _cnicController.text.trim(),
      'groupe_sanguin': _selectedBloodGroup ?? '',
      'activation_pin': _pinController.text.trim(),
      'fingerprint_hash': _fingerprintHash ?? '',
      'photo_path': _photoPath ?? '',

      'session': _selectedSession,
      'educational_level': _selectedLevel,
      'classe': _selectedClass,
      'section': _selectedSection,
      'categorie': _selectedCategory,
      'statut': _selectedStatus,
      'behavior_score': double.tryParse(_behaviorController.text.trim().replaceAll(',', '.')) ?? 18,

      'nom_pere': _fatherController.text.trim(),
      'cnic_pere': _fatherCnicController.text.trim(),
      'mobile': _mobileController.text.trim(),
      'whatsapp': _whatsappController.text.trim(),
      'father_qualification': _fatherQualificationController.text.trim(),
      'phone_fixe': _phoneFixeController.text.trim(),

      'frais_mensuels': double.tryParse(_monthlyController.text.trim().replaceAll(',', '.')) ?? 0,
      'frais_inscription': double.tryParse(_registrationController.text.trim().replaceAll(',', '.')) ?? 0,
      'ancien_solde': double.tryParse(_balanceController.text.trim().replaceAll(',', '.')) ?? 0,
      'frais_coges_card': double.tryParse(_cogesCardController.text.trim().replaceAll(',', '.')) ?? 1500,
      'frais_transport_internat': double.tryParse(_transportInternatController.text.trim().replaceAll(',', '.')) ?? 0,
    };

    final result = await _repository.saveStudent(
      studentId: widget.initialData?['id'] as int?,
      payload: payload,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Élève modifié avec succès !' : 'Nouvelle inscription enregistrée avec succès !'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']?.toString() ?? 'Échec enregistrement')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Dark sophisticated Web-matching theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ADMINISTRATION SCOLAIRE',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF818CF8)),
            ),
            Text(
              _isEdit ? 'Modifier Élève' : 'Nouvelle Inscription',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              '${_currentStep + 1}/3',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF38BDF8)),
            ),
          ),
        ],
      ),
      body: _isLoadingOptions
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : !_hasFormPermission
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Vous n\'avez pas la permission d\'accéder à ce formulaire.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Step Progress Tabs
                    Container(
                      color: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          _stepTab(0, '1. Profil', Icons.person_rounded),
                          const SizedBox(width: 6),
                          _stepTab(1, '2. Famille', Icons.family_restroom_rounded),
                          const SizedBox(width: 6),
                          _stepTab(2, '3. Finances', Icons.account_balance_wallet_rounded),
                        ],
                      ),
                    ),

                    // Main Form Body
                    Expanded(
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_isSessionFrozen)
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
                                          "Année scolaire clôturée ou verrouillée : Mode consultation seule. L'enregistrement et la modification d'élèves sont désactivés.",
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
                              IndexedStack(
                                index: _currentStep,
                                children: [
                                  _buildStep1Profil(),
                                  _buildStep2Famille(),
                                  _buildStep3Finances(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom Navigation Bar
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _stepTab(int stepIndex, String title, IconData icon) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentStep = stepIndex),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4F46E5)
                : (isDone ? const Color(0xFF1E293B) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF6366F1)
                  : (isDone ? const Color(0xFF10B981) : const Color(0xFF334155)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : icon,
                size: 13,
                color: isActive ? Colors.white : (isDone ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                    color: isActive ? Colors.white : (isDone ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8)),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 1: Profil Élève & Identité
  // -------------------------------------------------------------
  Widget _buildStep1Profil() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _darkCard(
          title: 'INFORMATIONS D\'IDENTITÉ',
          children: [
            _darkTextField(_admissionController, 'N° ADMISSION / MATRICULE *', hint: 'Ex: AD-2024-001', required: true),
            const SizedBox(height: 12),
            _darkTextField(_nameController, 'NOM COMPLET DE L\'ÉLÈVE *', hint: 'Jean Dupont', required: true),
            const SizedBox(height: 12),
            _darkTextField(_arabicNameController, 'الاسم الكامل بالعربية', hint: 'اسم الطالب هنا', required: false, isRtl: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _darkDropdown(
                    label: 'SEXE DE L\'ENFANT *',
                    value: _selectedSexe,
                    items: const ['Garcon', 'Fille'],
                    onChanged: (v) => setState(() => _selectedSexe = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _darkDropdown(
                    label: 'GROUPE SANGUIN',
                    value: _selectedBloodGroup,
                    items: const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
                    onChanged: (v) => setState(() => _selectedBloodGroup = v),
                    placeholder: '-- Choisir --',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _darkTextField(_birthDateController, 'DATE NAISSANCE', hint: 'YYYY-MM-DD', keyboardType: TextInputType.datetime, required: false)),
                const SizedBox(width: 12),
                Expanded(child: _darkTextField(_birthPlaceController, 'LIEU NAISSANCE', hint: 'Ville, Pays', required: false)),
              ],
            ),
            const SizedBox(height: 12),
            _darkTextField(_cnicController, 'CNIC / NUMÉRO NATIONAL', hint: 'Numéro d\'identification', required: false),
            const SizedBox(height: 12),
            _darkTextField(_religionController, 'RELIGION', hint: 'Islam / Christianisme...', required: false),
          ],
        ),

        const SizedBox(height: 16),

        // Photo Dossier Card (Parity with Web UI)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Photo Avatar / Camera Preview
                  GestureDetector(
                    onTap: () => _pickPhoto(ImageSource.gallery),
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155), width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _photoPath != null && _photoPath!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: _photoPath!.startsWith('data:image')
                                  ? Image.memory(base64Decode(_photoPath!.split(',').last), fit: BoxFit.cover)
                                  : Image.network(_photoPath!, fit: BoxFit.cover),
                            )
                          : const Center(
                              child: Icon(Icons.person_rounded, size: 42, color: Color(0xFF475569)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photographie du dossier',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'REQUIS POUR LA CARTE SCOLAIRE',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Actions Row: UPLOAD & CAMÉRA matching Web design
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.file_upload_outlined, size: 15, color: Color(0xFF818CF8)),
                                label: const Text('UPLOAD', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  side: const BorderSide(color: Color(0xFF334155)),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickPhoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined, size: 15, color: Color(0xFF818CF8)),
                                label: const Text('CAMÉRA', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  side: const BorderSide(color: Color(0xFF334155)),
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // SMART AI SCAN Button (Matching Web UI)
              ElevatedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFFBBF24)),
                label: const Text(
                  'SMART AI SCAN',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF818CF8)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  side: const BorderSide(color: Color(0xFF3730A3)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Biométrie & Code PIN
        _darkCard(
          title: 'SÉCURITÉ & BIOMÉTRIE',
          children: [
            _darkTextField(
              _pinController,
              'CODE PIN ACCÈS (4 CHIFFRES)',
              hint: 'Ex: 1234',
              required: false,
              keyboardType: TextInputType.number,
              suffix: TextButton.icon(
                onPressed: _generateRandomPin,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 14, color: Color(0xFF818CF8)),
                label: const Text('Auto PIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF818CF8))),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                      ? const Color(0xFF10B981)
                      : const Color(0xFF334155),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                              ? const Color(0xFF065F46)
                              : const Color(0xFF312E81),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 26,
                          color: _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                              ? const Color(0xFF34D399)
                              : const Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                                  ? 'Empreinte Digitale Enregistrée'
                                  : 'Empreinte Digitale Biométrique',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                                  ? _fingerprintHash!
                                  : 'Pour pointage automatique sur bornes et mobile',
                              style: TextStyle(
                                fontSize: 11,
                                color: _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF94A3B8),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _fingerprintHash = 'FP-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
                        });
                      },
                      icon: const Icon(Icons.fingerprint, size: 16, color: Colors.white),
                      label: Text(
                        _fingerprintHash != null && _fingerprintHash!.isNotEmpty ? 'Re-capturer l\'empreinte' : 'Capturer l\'empreinte',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _fingerprintHash != null && _fingerprintHash!.isNotEmpty
                            ? const Color(0xFF059669)
                            : const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 2: Dossier Famille & Académique
  // -------------------------------------------------------------
  Widget _buildStep2Famille() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _darkCard(
          title: 'DOSSIER FAMILLE & PARENTS',
          children: [
            _darkTextField(_fatherController, 'NOM DU TUTEUR / PÈRE *', hint: 'Nom du responsable', required: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _darkTextField(_mobileController, 'MOBILE *', hint: '+227 00 00 00 00', keyboardType: TextInputType.phone, required: true)),
                const SizedBox(width: 12),
                Expanded(child: _darkTextField(_whatsappController, 'WHATSAPP', hint: '+227 00 00 00 00', keyboardType: TextInputType.phone, required: false)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _darkTextField(_fatherCnicController, 'CNIC TUTEUR', hint: 'Numéro d\'identité', required: false)),
                const SizedBox(width: 12),
                Expanded(child: _darkTextField(_phoneFixeController, 'TÉLÉPHONE FIXE', hint: 'Fixe ou bureau', keyboardType: TextInputType.phone, required: false)),
              ],
            ),
            const SizedBox(height: 12),
            _darkTextField(_fatherQualificationController, 'PROFESSION DU TUTEUR', hint: 'Ex: Enseignant, Commerçant...', required: false),
          ],
        ),

        const SizedBox(height: 16),

        _darkCard(
          title: 'AFFECTATION ACADÉMIQUE',
          children: [
            Row(
              children: [
                Expanded(
                  child: _darkDropdown(
                    label: 'SESSION *',
                    value: _selectedSession,
                    items: _sessions,
                    onChanged: (v) => setState(() => _selectedSession = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _darkDropdown(
                    label: 'NIVEAU *',
                    value: _selectedLevel,
                    items: _levels,
                    onChanged: (v) => setState(() => _selectedLevel = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _darkDropdown(
                    label: 'CLASSE *',
                    value: _selectedClass,
                    items: _classes,
                    onChanged: (v) {
                      setState(() => _selectedClass = v);
                      _applyClassFees(v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _darkDropdown(
                    label: 'SECTION *',
                    value: _selectedSection,
                    items: _sections,
                    onChanged: (v) => setState(() => _selectedSection = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _darkDropdown(
                    label: 'CATÉGORIE',
                    value: _selectedCategory,
                    items: const ['Général', 'Boursier', 'Fils employé'],
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _darkDropdown(
                    label: 'STATUT',
                    value: _selectedStatus,
                    items: const ['Actif', 'En attente', 'Inactif', 'Diplômé', 'Exclu'],
                    onChanged: (v) => setState(() => _selectedStatus = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _darkTextField(_behaviorController, 'NOTE DE CONDUITE INITIALE (/20)', hint: '18', keyboardType: TextInputType.number, required: false),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 3: Plan Financier & Frais
  // -------------------------------------------------------------
  Widget _buildStep3Finances() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _darkCard(
          title: 'PLAN FINANCIER & SCOLARITÉ',
          children: [
            Row(
              children: [
                Expanded(child: _darkTextField(_monthlyController, 'MENSUALITÉ (FCFA) *', hint: '5000', keyboardType: TextInputType.number, required: true)),
                const SizedBox(width: 12),
                Expanded(child: _darkTextField(_registrationController, 'INSCRIPTION (FCFA) *', hint: '5000', keyboardType: TextInputType.number, required: true)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _darkTextField(_cogesCardController, 'CARTE COGES (FCFA)', hint: '1500', keyboardType: TextInputType.number, required: false)),
                const SizedBox(width: 12),
                Expanded(child: _darkTextField(_balanceController, 'ANCIEN SOLDE (FCFA)', hint: '0', keyboardType: TextInputType.number, required: false)),
              ],
            ),
            const SizedBox(height: 12),
            _darkTextField(_transportInternatController, 'TRANSPORT / INTERNAT (FCFA)', hint: '0', keyboardType: TextInputType.number, required: false),
          ],
        ),

        const SizedBox(height: 16),

        // Financial Recap summary banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B4B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF4338CA)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF312E81),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calculate_rounded, color: Color(0xFF818CF8), size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Validation des engagements financiers',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Les échéances et reçus officiels seront générés automatiquement selon la session configurée.',
                      style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Bottom Action Bar (Suivant / Précédent / Enregistrer)
  // -------------------------------------------------------------
  Widget _buildBottomBar() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _currentStep--),
                icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF94A3B8)),
                label: const Text('PRÉCÉDENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF94A3B8))),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF334155)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF334155)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('QUITTER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF94A3B8))),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSaving || (_currentStep >= 2 && _isSessionFrozen)
                  ? null
                  : () {
                      if (_currentStep < 2) {
                        setState(() => _currentStep++);
                      } else {
                        _save();
                      }
                    },
              icon: Icon(
                _currentStep < 2
                    ? Icons.bolt_rounded
                    : (_isSessionFrozen ? Icons.lock_rounded : Icons.check_circle_rounded),
                size: 16,
                color: Colors.white,
              ),
              label: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _currentStep < 2
                          ? 'SUIVANT'
                          : (_isSessionFrozen ? 'VERROUILLÉ' : 'ENREGISTRER'),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentStep >= 2 && _isSessionFrozen
                    ? const Color(0xFF475569)
                    : const Color(0xFF4F46E5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------
  Widget _darkCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF818CF8)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _darkTextField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = true,
    bool isRtl = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1E293B)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _darkDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? placeholder,
  }) {
    final safeValue = items.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          dropdownColor: const Color(0xFF0F172A),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          items: [
            if (placeholder != null)
              DropdownMenuItem<String>(
                value: null,
                child: Text(placeholder, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ),
            ...items.map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1E293B)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
