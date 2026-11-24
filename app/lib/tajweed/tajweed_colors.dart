import 'package:flutter/material.dart';

/// Colours for Quran.com's tajweed classes, following common colour-coded
/// mushaf conventions. Labels show in the word sheet's legend.
class TajweedRule {
  const TajweedRule(this.label, this.color);
  final String label;
  final Color color;
}

const tajweedRules = <String, TajweedRule>{
  'ham_wasl': TajweedRule('Hamzat al-wasl', Color(0xFF9E9E9E)),
  'slnt': TajweedRule('Silent letter', Color(0xFF9E9E9E)),
  'laam_shamsiyah': TajweedRule('Lam shamsiyya', Color(0xFF9E9E9E)),
  'madda_normal': TajweedRule('Natural madd (2)', Color(0xFFC38A2C)),
  'madda_permissible': TajweedRule('Permissible madd (2/4/6)', Color(0xFFE08A1E)),
  'madda_obligatory': TajweedRule('Obligatory madd (4/5)', Color(0xFFD1491D)),
  'madda_necessary': TajweedRule('Necessary madd (6)', Color(0xFFA6151B)),
  'qalaqah': TajweedRule('Qalqala', Color(0xFF2E7DD7)),
  'ikhafa': TajweedRule('Ikhfa\'', Color(0xFF8E44AD)),
  'ikhafa_shafawi': TajweedRule('Ikhfa\' shafawi', Color(0xFFB04FC7)),
  'iqlab': TajweedRule('Iqlab', Color(0xFF1F9E89)),
  'idgham_ghunnah': TajweedRule('Idgham with ghunna', Color(0xFF169A3B)),
  'idgham_wo_ghunnah': TajweedRule('Idgham without ghunna', Color(0xFF6BA539)),
  'idgham_shafawi': TajweedRule('Idgham shafawi', Color(0xFF3FAE5B)),
  'idgham_mutajanisayn': TajweedRule('Idgham mutajanisayn', Color(0xFF7FA650)),
  'idgham_mutaqaribayn': TajweedRule('Idgham mutaqaribayn', Color(0xFF7FA650)),
  'ghunnah': TajweedRule('Ghunna (2)', Color(0xFFE7487C)),
};

Color? tajweedColor(String? rule) => rule == null ? null : tajweedRules[rule]?.color;
