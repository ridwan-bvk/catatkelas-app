enum AttendanceStatus { present, sick, excused, absent }

class AttendanceSessionItem {
  const AttendanceSessionItem({
    required this.id,
    required this.title,
    required this.date,
    required this.groupId,
    required this.subGroupId,
    required this.studentStatus,
  });

  final String id;
  final String title;
  final DateTime date;
  final String groupId;
  final String subGroupId;
  final Map<String, AttendanceStatus> studentStatus;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'groupId': groupId,
        'subGroupId': subGroupId,
        'studentStatus': studentStatus.map((k, v) => MapEntry(k, v.name)),
      };

  factory AttendanceSessionItem.fromJson(Map<String, dynamic> json) {
    final raw = json['studentStatus'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return AttendanceSessionItem(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
      groupId: json['groupId'] as String,
      subGroupId: json['subGroupId'] as String,
      studentStatus: raw.map((k, v) => MapEntry(
            k,
            AttendanceStatus.values.firstWhere(
              (x) => x.name == v,
              orElse: () => AttendanceStatus.absent,
            ),
          )),
    );
  }
}
