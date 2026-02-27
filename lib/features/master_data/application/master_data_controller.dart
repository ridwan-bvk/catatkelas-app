import 'package:flutter/material.dart';
import 'package:catat_kelas/features/master_data/data/master_firestore_repository.dart';
import 'package:catat_kelas/features/master_data/domain/models/category_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_sub_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_role_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_item.dart';

class MasterDataController extends ChangeNotifier {
  MasterDataController(
      {required bool firebaseEnabled, MasterFirestoreRepository? repository})
      : _firebaseEnabled = firebaseEnabled,
        _repository = repository;

  final bool _firebaseEnabled;
  final MasterFirestoreRepository? _repository;

  bool _loading = false;
  String? _lastError;
  bool _firebaseTemporarilyDisabled = false;

  final List<CategoryItem> _categories = [
    const CategoryItem(id: 'spp', name: 'SPP', color: Color(0xFF0A84FF)),
    const CategoryItem(id: 'donasi', name: 'Donasi', color: Color(0xFF34C759)),
    const CategoryItem(
        id: 'operasional', name: 'Operasional', color: Color(0xFFFF9F0A)),
    const CategoryItem(
        id: 'kegiatan', name: 'Kegiatan', color: Color(0xFFAF52DE)),
  ];

  final List<UserItem> _users = [
    const UserItem(id: 'u1', name: 'Admin Sekolah', role: 'Admin'),
    const UserItem(id: 'u2', name: 'Bendahara', role: 'Bendahara'),
  ];
  final List<UserRoleItem> _roles = [
    const UserRoleItem(id: 'role-admin', name: 'Admin'),
    const UserRoleItem(id: 'role-bendahara', name: 'Bendahara'),
  ];
  final List<StudentGroupItem> _studentGroups = [
    const StudentGroupItem(id: 'g1', name: 'Kelas 1'),
    const StudentGroupItem(id: 'g2', name: 'Kelas 2'),
  ];
  final List<StudentSubGroupItem> _studentSubGroups = [
    const StudentSubGroupItem(id: 'sg1a', groupId: 'g1', name: '1A'),
    const StudentSubGroupItem(id: 'sg1b', groupId: 'g1', name: '1B'),
    const StudentSubGroupItem(id: 'sg2a', groupId: 'g2', name: '2A'),
  ];
  final List<StudentItem> _students = [
    const StudentItem(
        id: 's1',
        groupId: 'g1',
        subGroupId: 'sg1a',
        name: 'Aisyah',
        nis: '1001'),
    const StudentItem(
        id: 's2', groupId: 'g1', subGroupId: 'sg1a', name: 'Bima', nis: '1002'),
    const StudentItem(
        id: 's3',
        groupId: 'g1',
        subGroupId: 'sg1b',
        name: 'Citra',
        nis: '1003'),
    const StudentItem(
        id: 's4',
        groupId: 'g2',
        subGroupId: 'sg2a',
        name: 'Damar',
        nis: '2001'),
    const StudentItem(
        id: 's5', groupId: 'g2', subGroupId: 'sg2a', name: 'Eka', nis: '2002'),
  ];

  List<CategoryItem> get categories => List.unmodifiable(_categories);
  List<UserItem> get users => List.unmodifiable(_users);
  List<UserRoleItem> get roles => List.unmodifiable(_roles);
  List<StudentGroupItem> get studentGroups => List.unmodifiable(_studentGroups);
  List<StudentSubGroupItem> get studentSubGroups =>
      List.unmodifiable(_studentSubGroups);
  List<StudentItem> get students => List.unmodifiable(_students);
  bool get loading => _loading;
  String? get lastError => _lastError;
  bool get firebaseEnabled => _firebaseEnabled && !_firebaseTemporarilyDisabled;

  void _setError(String value) {
    _lastError = value;
    notifyListeners();
  }

  void _clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  bool _isFirestoreDisabledError(String message) {
    final m = message.toLowerCase();
    return m.contains('firestore api has not been used') ||
        m.contains('permission denied') ||
        m.contains('firestore.googleapis.com');
  }

  void _handleFirebaseError(String context, Object error) {
    final message = error.toString();
    if (_isFirestoreDisabledError(message)) {
      _firebaseTemporarilyDisabled = true;
      _setError(
          'Firebase Firestore belum aktif/izin ditolak. Aktifkan Firestore API di Google Cloud Console untuk project ini, lalu jalankan ulang aplikasi.');
      return;
    }
    _setError('$context: $error');
  }

  Future<void> initialize() async {
    if (!_firebaseEnabled ||
        _firebaseTemporarilyDisabled ||
        _repository == null) {
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final categories = await _repository.fetchCategories();
      final users = await _repository.fetchUsers();
      final roles = await _repository.fetchRoles();
      final studentGroups = await _repository.fetchStudentGroups();
      final studentSubGroups = await _repository.fetchStudentSubGroups();
      final students = await _repository.fetchStudents();

      if (categories.isNotEmpty) {
        _categories
          ..clear()
          ..addAll(categories);
      }

      if (users.isNotEmpty) {
        _users
          ..clear()
          ..addAll(users);
      }
      if (roles.isNotEmpty) {
        _roles
          ..clear()
          ..addAll(roles);
      }
      if (studentGroups.isNotEmpty) {
        _studentGroups
          ..clear()
          ..addAll(studentGroups);
      }
      if (studentSubGroups.isNotEmpty) {
        _studentSubGroups
          ..clear()
          ..addAll(studentSubGroups);
      }
      if (students.isNotEmpty) {
        _students
          ..clear()
          ..addAll(students);
      }
    } catch (e) {
      _handleFirebaseError('Gagal membaca master data Firebase', e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addOrUpdateCategory(CategoryItem item) async {
    final idx = _categories.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _categories[idx] = item;
    } else {
      _categories.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertCategory(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron kategori ke Firebase', e);
      }
    }
  }

  Future<void> deleteCategory(String id) async {
    _categories.removeWhere((x) => x.id == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteCategory(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus kategori di Firebase', e);
      }
    }
  }

  Future<void> addOrUpdateUser(UserItem item) async {
    final idx = _users.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _users[idx] = item;
    } else {
      _users.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertUser(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron pengguna ke Firebase', e);
      }
    }
  }

  Future<void> deleteUser(String id) async {
    _users.removeWhere((x) => x.id == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteUser(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus pengguna di Firebase', e);
      }
    }
  }

  Future<void> addOrUpdateRole(UserRoleItem item) async {
    final idx = _roles.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _roles[idx] = item;
    } else {
      _roles.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertRole(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron role pengguna ke Firebase', e);
      }
    }
  }

  Future<void> deleteRole(String id) async {
    _roles.removeWhere((x) => x.id == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteRole(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus role pengguna di Firebase', e);
      }
    }
  }

  Future<void> addOrUpdateStudentGroup(StudentGroupItem item) async {
    final idx = _studentGroups.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _studentGroups[idx] = item;
    } else {
      _studentGroups.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertStudentGroup(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron group murid ke Firebase', e);
      }
    }
  }

  Future<void> deleteStudentGroup(String id) async {
    _studentGroups.removeWhere((x) => x.id == id);
    _studentSubGroups.removeWhere((x) => x.groupId == id);
    _students.removeWhere((x) => x.groupId == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteStudentGroup(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus group murid di Firebase', e);
      }
    }
  }

  Future<void> addOrUpdateStudentSubGroup(StudentSubGroupItem item) async {
    final idx = _studentSubGroups.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _studentSubGroups[idx] = item;
    } else {
      _studentSubGroups.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertStudentSubGroup(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron sub group murid ke Firebase', e);
      }
    }
  }

  Future<void> deleteStudentSubGroup(String id) async {
    _studentSubGroups.removeWhere((x) => x.id == id);
    _students.removeWhere((x) => x.subGroupId == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteStudentSubGroup(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus sub group murid di Firebase', e);
      }
    }
  }

  Future<void> addOrUpdateStudent(StudentItem item) async {
    final idx = _students.indexWhere((x) => x.id == item.id);
    if (idx >= 0) {
      _students[idx] = item;
    } else {
      _students.add(item);
    }
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.upsertStudent(item);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron murid ke Firebase', e);
      }
    }
  }

  Future<void> deleteStudent(String id) async {
    _students.removeWhere((x) => x.id == id);
    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        await _repository.deleteStudent(id);
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal hapus murid di Firebase', e);
      }
    }
  }

  Future<void> replaceFromBackup({
    required List<CategoryItem> categories,
    required List<UserItem> users,
    List<UserRoleItem>? roles,
    List<StudentGroupItem>? studentGroups,
    List<StudentSubGroupItem>? studentSubGroups,
    List<StudentItem>? students,
  }) async {
    _categories
      ..clear()
      ..addAll(categories);

    _users
      ..clear()
      ..addAll(users);
    if (roles != null) {
      _roles
        ..clear()
        ..addAll(roles);
    }
    if (studentGroups != null) {
      _studentGroups
        ..clear()
        ..addAll(studentGroups);
    }
    if (studentSubGroups != null) {
      _studentSubGroups
        ..clear()
        ..addAll(studentSubGroups);
    }
    if (students != null) {
      _students
        ..clear()
        ..addAll(students);
    }

    notifyListeners();

    if (firebaseEnabled && _repository != null) {
      try {
        for (final category in _categories) {
          await _repository.upsertCategory(category);
        }
        for (final user in _users) {
          await _repository.upsertUser(user);
        }
        for (final role in _roles) {
          await _repository.upsertRole(role);
        }
        for (final group in _studentGroups) {
          await _repository.upsertStudentGroup(group);
        }
        for (final subGroup in _studentSubGroups) {
          await _repository.upsertStudentSubGroup(subGroup);
        }
        for (final student in _students) {
          await _repository.upsertStudent(student);
        }
        _clearError();
      } catch (e) {
        _handleFirebaseError('Gagal sinkron data backup ke Firebase', e);
      }
    }
  }
}
