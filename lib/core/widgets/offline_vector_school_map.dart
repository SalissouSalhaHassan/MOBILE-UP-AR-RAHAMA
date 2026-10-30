import 'package:flutter/material.dart';

class SchoolMapPoint {
  final String id;
  final String name;
  final String region;
  final double xRatio; // Relative position 0.0 to 1.0 on local map
  final double yRatio; // Relative position 0.0 to 1.0 on local map
  final int studentsCount;
  final String cycle;
  final bool isPriority;

  const SchoolMapPoint({
    required this.id,
    required this.name,
    required this.region,
    required this.xRatio,
    required this.yRatio,
    required this.studentsCount,
    required this.cycle,
    this.isPriority = false,
  });
}

/// Offline Interactive Vector School Map
/// Operates 100% offline without requiring Google Play Services or network access.
class OfflineVectorSchoolMap extends StatefulWidget {
  final List<SchoolMapPoint> schools;
  final void Function(SchoolMapPoint)? onSchoolSelected;

  const OfflineVectorSchoolMap({
    super.key,
    this.schools = const [],
    this.onSchoolSelected,
  });

  @override
  State<OfflineVectorSchoolMap> createState() => _OfflineVectorSchoolMapState();
}

class _OfflineVectorSchoolMapState extends State<OfflineVectorSchoolMap> {
  SchoolMapPoint? _selectedSchool;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Custom Painter rendering geographic region grid & administrative zones
            CustomPaint(
              size: Size.infinite,
              painter: _OfflineTerritoryPainter(),
            ),

            // Interactive School Markers
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;

                final schoolList = widget.schools.isNotEmpty
                    ? widget.schools
                    : _defaultSampleSchools;

                return Stack(
                  children: schoolList.map((school) {
                    final isSelected = _selectedSchool?.id == school.id;
                    final posX = school.xRatio * (w - 40) + 20;
                    final posY = school.yRatio * (h - 40) + 20;

                    return Positioned(
                      left: posX - 16,
                      top: posY - 16,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedSchool = school);
                          widget.onSchoolSelected?.call(school);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isSelected ? 38 : 28,
                          height: isSelected ? 38 : 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: school.isPriority
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF6366F1),
                            border: Border.all(
                              color: Colors.white,
                              width: isSelected ? 2.5 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (school.isPriority
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF6366F1))
                                    .withValues(alpha: isSelected ? 0.8 : 0.4),
                                blurRadius: isSelected ? 14 : 6,
                                spreadRadius: isSelected ? 3 : 1,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.school_rounded,
                              size: isSelected ? 18 : 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            // Top Status Badge (100% Offline Tag)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.public_off_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 6),
                    Text(
                      "CARTE SECTORIELLE HORS-LIGNE",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Selected School Bottom Details Overlay
            if (_selectedSchool != null)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF475569)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _selectedSchool!.isPriority
                              ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                              : const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.domain_rounded,
                          color: _selectedSchool!.isPriority
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedSchool!.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${_selectedSchool!.region} • ${_selectedSchool!.cycle} • ${_selectedSchool!.studentsCount} élèves",
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                        onPressed: () => setState(() => _selectedSchool = null),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<SchoolMapPoint> _defaultSampleSchools = [
    SchoolMapPoint(
      id: "1",
      name: "U P AR-RAHAMA - CAMPUS PRINCIPAL",
      region: "Niamey - District 1",
      xRatio: 0.28,
      yRatio: 0.65,
      studentsCount: 1240,
      cycle: "Collège & Lycée",
      isPriority: false,
    ),
    SchoolMapPoint(
      id: "2",
      name: "LYCÉE TECHNIQUE MARADI",
      region: "Maradi",
      xRatio: 0.62,
      yRatio: 0.70,
      studentsCount: 890,
      cycle: "Technique",
      isPriority: true,
    ),
    SchoolMapPoint(
      id: "3",
      name: "ÉCOLE NATIONALE ZINDER",
      region: "Zinder",
      xRatio: 0.78,
      yRatio: 0.68,
      studentsCount: 650,
      cycle: "Primaire",
      isPriority: false,
    ),
    SchoolMapPoint(
      id: "4",
      name: "INSPECTION TAHOUA SUD",
      region: "Tahoua",
      xRatio: 0.45,
      yRatio: 0.45,
      studentsCount: 520,
      cycle: "Collège",
      isPriority: true,
    ),
    SchoolMapPoint(
      id: "5",
      name: "GROUPE SCOLAIRE AGADEZ",
      region: "Agadez",
      xRatio: 0.60,
      yRatio: 0.25,
      studentsCount: 410,
      cycle: "Primaire",
      isPriority: false,
    ),
  ];
}

class _OfflineTerritoryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final contourPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final fillPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    // Simulated regional territorial boundary
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.75)
      ..lineTo(size.width * 0.35, size.height * 0.45)
      ..lineTo(size.width * 0.55, size.height * 0.20)
      ..lineTo(size.width * 0.85, size.height * 0.25)
      ..lineTo(size.width * 0.90, size.height * 0.65)
      ..lineTo(size.width * 0.65, size.height * 0.80)
      ..lineTo(size.width * 0.30, size.height * 0.85)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, contourPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
