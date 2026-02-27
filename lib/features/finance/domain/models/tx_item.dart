enum TxType { income, expense }

class TxItem {
  const TxItem({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.date,
    double? unitAmount,
    this.selectedGroupId,
    this.selectedSubGroupId,
    this.checkedStudentIds = const [],
    this.checkedStudentAmounts = const {},
  }) : unitAmount = unitAmount ?? amount;

  final String id;
  final String title;
  final String categoryId;
  final TxType type;
  final double amount;
  final double unitAmount;
  final DateTime date;
  final String? selectedGroupId;
  final String? selectedSubGroupId;
  final List<String> checkedStudentIds;
  final Map<String, double> checkedStudentAmounts;

  TxItem copyWith({
    String? title,
    String? categoryId,
    TxType? type,
    double? amount,
    double? unitAmount,
    DateTime? date,
    String? selectedGroupId,
    String? selectedSubGroupId,
    List<String>? checkedStudentIds,
    Map<String, double>? checkedStudentAmounts,
  }) {
    return TxItem(
      id: id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      unitAmount: unitAmount ?? this.unitAmount,
      date: date ?? this.date,
      selectedGroupId: selectedGroupId ?? this.selectedGroupId,
      selectedSubGroupId: selectedSubGroupId ?? this.selectedSubGroupId,
      checkedStudentIds: checkedStudentIds ?? this.checkedStudentIds,
      checkedStudentAmounts:
          checkedStudentAmounts ?? this.checkedStudentAmounts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'categoryId': categoryId,
      'type': type.name,
      'amount': amount,
      'unitAmount': unitAmount,
      'date': date.toIso8601String(),
      'selectedGroupId': selectedGroupId,
      'selectedSubGroupId': selectedSubGroupId,
      'checkedStudentIds': checkedStudentIds,
      'checkedStudentAmounts': checkedStudentAmounts,
    };
  }

  factory TxItem.fromJson(Map<String, dynamic> json) {
    return TxItem(
      id: json['id'] as String,
      title: json['title'] as String,
      categoryId: json['categoryId'] as String,
      type:
          (json['type'] as String) == 'income' ? TxType.income : TxType.expense,
      amount: (json['amount'] as num).toDouble(),
      unitAmount: (json['unitAmount'] as num?)?.toDouble(),
      date: DateTime.parse(json['date'] as String),
      selectedGroupId: json['selectedGroupId'] as String?,
      selectedSubGroupId: json['selectedSubGroupId'] as String?,
      checkedStudentIds:
          (json['checkedStudentIds'] as List<dynamic>? ?? const [])
              .map((e) => e as String)
              .toList(),
      checkedStudentAmounts:
          (json['checkedStudentAmounts'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}
