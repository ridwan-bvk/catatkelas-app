class UserItem {
  const UserItem({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  UserItem copyWith({String? name, String? role}) {
    return UserItem(id: id, name: name ?? this.name, role: role ?? this.role);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};

  factory UserItem.fromJson(Map<String, dynamic> json) {
    return UserItem(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
    );
  }
}
