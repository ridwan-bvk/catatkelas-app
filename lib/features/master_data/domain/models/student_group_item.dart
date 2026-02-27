class StudentGroupItem {
  const StudentGroupItem({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory StudentGroupItem.fromJson(Map<String, dynamic> json) {
    return StudentGroupItem(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
