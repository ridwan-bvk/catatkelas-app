class StudentItem {
  const StudentItem({
    required this.id,
    required this.groupId,
    required this.subGroupId,
    required this.name,
    required this.nis,
  });

  final String id;
  final String groupId;
  final String subGroupId;
  final String name;
  final String nis;

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'subGroupId': subGroupId,
        'name': name,
        'nis': nis,
      };

  factory StudentItem.fromJson(Map<String, dynamic> json) {
    return StudentItem(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      subGroupId: json['subGroupId'] as String,
      name: json['name'] as String,
      nis: json['nis'] as String,
    );
  }
}
