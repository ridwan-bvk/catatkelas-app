class StudentSubGroupItem {
  const StudentSubGroupItem({
    required this.id,
    required this.groupId,
    required this.name,
  });

  final String id;
  final String groupId;
  final String name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'name': name,
      };

  factory StudentSubGroupItem.fromJson(Map<String, dynamic> json) {
    return StudentSubGroupItem(
      id: json['id'] as String,
      groupId: json['groupId'] as String,
      name: json['name'] as String,
    );
  }
}
