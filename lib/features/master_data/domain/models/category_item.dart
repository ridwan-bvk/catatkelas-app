import 'package:flutter/material.dart';

class CategoryItem {
  const CategoryItem(
      {required this.id,
      required this.name,
      required this.color,
      this.useGroup = false,
      this.useSubGroup = false,
      this.useStudent = false,
      this.allowEmptyAmountOnCreate = false,
      this.useStudentVariableAmount = false});

  final String id;
  final String name;
  final Color color;
  final bool useGroup;
  final bool useSubGroup;
  final bool useStudent;
  final bool allowEmptyAmountOnCreate;
  final bool useStudentVariableAmount;

  CategoryItem copyWith({
    String? name,
    Color? color,
    bool? useGroup,
    bool? useSubGroup,
    bool? useStudent,
    bool? allowEmptyAmountOnCreate,
    bool? useStudentVariableAmount,
  }) {
    return CategoryItem(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      useGroup: useGroup ?? this.useGroup,
      useSubGroup: useSubGroup ?? this.useSubGroup,
      useStudent: useStudent ?? this.useStudent,
      allowEmptyAmountOnCreate:
          allowEmptyAmountOnCreate ?? this.allowEmptyAmountOnCreate,
      useStudentVariableAmount:
          useStudentVariableAmount ?? this.useStudentVariableAmount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.value,
        'useGroup': useGroup,
        'useSubGroup': useSubGroup,
        'useStudent': useStudent,
        'allowEmptyAmountOnCreate': allowEmptyAmountOnCreate,
        'useStudentVariableAmount': useStudentVariableAmount,
      };

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    return CategoryItem(
      id: json['id'] as String,
      name: json['name'] as String,
      color: Color((json['color'] as num).toInt()),
      useGroup: json['useGroup'] as bool? ?? false,
      useSubGroup: json['useSubGroup'] as bool? ?? false,
      useStudent: json['useStudent'] as bool? ?? false,
      allowEmptyAmountOnCreate:
          json['allowEmptyAmountOnCreate'] as bool? ?? false,
      useStudentVariableAmount:
          json['useStudentVariableAmount'] as bool? ?? false,
    );
  }
}
