/// One choice in a list: [code] is what is sent to the server and stored in the
/// database, [label] is what the user reads. The codes must match the CHECK
/// constraints in dermascreen_schema.sql.
class ChoiceOption {
  final String code;
  final String label;
  const ChoiceOption(this.code, this.label);
}

/// Age of the person who has the skin problem (can be a child the user is helping).
const List<ChoiceOption> kAgeGroups = [
  ChoiceOption('0-1', '0 to 1 year (baby)'),
  ChoiceOption('2-5', '2 to 5 years'),
  ChoiceOption('6-12', '6 to 12 years'),
  ChoiceOption('13-17', '13 to 17 years'),
  ChoiceOption('18-30', '18 to 30 years'),
  ChoiceOption('31-45', '31 to 45 years'),
  ChoiceOption('46-60', '46 to 60 years'),
  ChoiceOption('61+', '61 years and above'),
];

/// How long the skin problem has been there.
const List<ChoiceOption> kDurations = [
  ChoiceOption('lt_1d', 'Less than a day'),
  ChoiceOption('1_3d', '1 to 3 days'),
  ChoiceOption('4_7d', '4 to 7 days'),
  ChoiceOption('1_2w', '1 to 2 weeks'),
  ChoiceOption('3_4w', '3 to 4 weeks'),
  ChoiceOption('1_3m', '1 to 3 months'),
  ChoiceOption('gt_3m', 'More than 3 months'),
];

/// Short word for an itch rating, shown under the rating buttons.
String itchWord(int score) {
  if (score == 0) return 'No itching';
  if (score <= 3) return 'Mild itching';
  if (score <= 6) return 'Moderate itching';
  if (score <= 8) return 'Severe itching';
  return 'Unbearable itching';
}

/// Names of the form fields as the server reports them, in plain words.
const Map<String, String> kFieldLabels = {
  'age_group': 'Age',
  'duration_range': 'How long you have had it',
  'itch_score': 'Itch rating',
  'has_swelling': 'Swelling',
  'has_allergy': 'Allergies',
  'allergy_details': 'What you are allergic to',
  'description': 'Description',
  'contact_number': 'Contact number',
  'photo': 'Photo',
};