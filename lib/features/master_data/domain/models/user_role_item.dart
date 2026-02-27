class UserRoleItem {
  const UserRoleItem({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  UserRoleItem copyWith({String? name}) {
    return UserRoleItem(id: id, name: name ?? this.name);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory UserRoleItem.fromJson(Map<String, dynamic> json) {
    return UserRoleItem(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
