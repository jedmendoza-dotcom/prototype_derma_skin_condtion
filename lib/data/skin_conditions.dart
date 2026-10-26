import 'package:flutter/material.dart';

class SkinCondition {
  final String name;
  final String category;
  final String summary;
  final List<String> signs;
  final IconData icon;
  final Color tint;

  /// Put a photo at this path (see SETUP.md). If it is missing, a gradient
  /// placeholder is shown instead.
  final String imageAsset;

  const SkinCondition({
    required this.name,
    required this.category,
    required this.summary,
    required this.signs,
    required this.icon,
    required this.tint,
    required this.imageAsset,
  });
}

const List<SkinCondition> kSkinConditions = [
  SkinCondition(
    name: 'Acne Vulgaris',
    category: 'Inflammatory',
    summary:
        'Clogged pores and inflammation that cause pimples, blackheads and '
        'cysts on the face, chest and back. Very common in teenagers and '
        'young adults, and often worsened by heat, sweat and oily skin.',
    signs: ['Pimples', 'Blackheads', 'Oily skin', 'Scarring'],
    icon: Icons.face_retouching_natural,
    tint: Color(0xFF3B82F6),
    imageAsset: 'assets/images/conditions/acne.jpg',
  ),
  SkinCondition(
    name: 'Atopic Dermatitis (Eczema)',
    category: 'Inflammatory',
    summary:
        'A long-term condition that leaves the skin dry, itchy and inflamed. '
        'Flare-ups are often triggered by heat, sweat, dust and harsh soaps.',
    signs: ['Intense itching', 'Dry patches', 'Redness', 'Thickened skin'],
    icon: Icons.water_drop_outlined,
    tint: Color(0xFF06B6D4),
    imageAsset: 'assets/images/conditions/eczema.jpg',
  ),
  SkinCondition(
    name: 'Tinea (Ringworm)',
    category: 'Fungal',
    summary:
        'Fungal infections thrive in warm, humid climates like the '
        'Philippines. They cause scaly, itchy patches on the body, feet '
        '(athlete\'s foot), groin or scalp.',
    signs: ['Ring-shaped rash', 'Scaling', 'Itching', 'Clearer centre'],
    icon: Icons.spa_outlined,
    tint: Color(0xFF10B981),
    imageAsset: 'assets/images/conditions/tinea.jpg',
  ),
  SkinCondition(
    name: 'Scabies',
    category: 'Parasitic',
    summary:
        'Caused by tiny mites that burrow into the skin. It spreads through '
        'prolonged skin contact and shared bedding, so it is seen more often '
        'in crowded living conditions.',
    signs: ['Night-time itching', 'Burrow lines', 'Small bumps', 'Between fingers'],
    icon: Icons.pest_control_outlined,
    tint: Color(0xFFF59E0B),
    imageAsset: 'assets/images/conditions/scabies.jpg',
  ),
  SkinCondition(
    name: 'Impetigo',
    category: 'Bacterial',
    summary:
        'A contagious bacterial skin infection, most common in children. It '
        'spreads easily through touch and shared items, and often starts '
        'from scratched insect bites or small wounds.',
    signs: ['Red sores', 'Honey-coloured crusts', 'Blisters', 'Itching'],
    icon: Icons.healing_outlined,
    tint: Color(0xFFEF6C6C),
    imageAsset: 'assets/images/conditions/impetigo.jpg',
  ),
  SkinCondition(
    name: 'Melasma',
    category: 'Pigmentation',
    summary:
        'Brown or grey-brown patches, usually on the cheeks, forehead and '
        'upper lip. Sun exposure and hormones play a role, which is why it '
        'is common in sunny countries.',
    signs: ['Symmetrical patches', 'Darkens in the sun', 'Painless', 'Face area'],
    icon: Icons.wb_sunny_outlined,
    tint: Color(0xFF8B5CF6),
    imageAsset: 'assets/images/conditions/melasma.jpg',
  ),
];
