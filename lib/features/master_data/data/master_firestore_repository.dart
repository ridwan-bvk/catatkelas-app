import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:catat_kelas/features/master_data/domain/models/category_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_sub_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_role_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_item.dart';

class MasterFirestoreRepository {
  MasterFirestoreRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _categoryCol =>
      _db.collection('master_categories');
  CollectionReference<Map<String, dynamic>> get _userCol =>
      _db.collection('master_users');
  CollectionReference<Map<String, dynamic>> get _roleCol =>
      _db.collection('master_user_roles');
  CollectionReference<Map<String, dynamic>> get _groupCol =>
      _db.collection('master_student_groups');
  CollectionReference<Map<String, dynamic>> get _subGroupCol =>
      _db.collection('master_student_sub_groups');
  CollectionReference<Map<String, dynamic>> get _studentCol =>
      _db.collection('master_students');

  Future<List<CategoryItem>> fetchCategories() async {
    final snap = await _categoryCol.orderBy('name').get();
    return snap.docs.map((doc) => CategoryItem.fromJson(doc.data())).toList();
  }

  Future<List<UserItem>> fetchUsers() async {
    final snap = await _userCol.orderBy('name').get();
    return snap.docs.map((doc) => UserItem.fromJson(doc.data())).toList();
  }

  Future<List<UserRoleItem>> fetchRoles() async {
    final snap = await _roleCol.orderBy('name').get();
    return snap.docs.map((doc) => UserRoleItem.fromJson(doc.data())).toList();
  }

  Future<List<StudentGroupItem>> fetchStudentGroups() async {
    final snap = await _groupCol.orderBy('name').get();
    return snap.docs
        .map((doc) => StudentGroupItem.fromJson(doc.data()))
        .toList();
  }

  Future<List<StudentSubGroupItem>> fetchStudentSubGroups() async {
    final snap = await _subGroupCol.orderBy('name').get();
    return snap.docs
        .map((doc) => StudentSubGroupItem.fromJson(doc.data()))
        .toList();
  }

  Future<List<StudentItem>> fetchStudents() async {
    final snap = await _studentCol.orderBy('name').get();
    return snap.docs.map((doc) => StudentItem.fromJson(doc.data())).toList();
  }

  Future<void> upsertCategory(CategoryItem item) async {
    await _categoryCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteCategory(String id) async {
    await _categoryCol.doc(id).delete();
  }

  Future<void> upsertUser(UserItem item) async {
    await _userCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteUser(String id) async {
    await _userCol.doc(id).delete();
  }

  Future<void> upsertRole(UserRoleItem item) async {
    await _roleCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteRole(String id) async {
    await _roleCol.doc(id).delete();
  }

  Future<void> upsertStudentGroup(StudentGroupItem item) async {
    await _groupCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteStudentGroup(String id) async {
    await _groupCol.doc(id).delete();
  }

  Future<void> upsertStudentSubGroup(StudentSubGroupItem item) async {
    await _subGroupCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteStudentSubGroup(String id) async {
    await _subGroupCol.doc(id).delete();
  }

  Future<void> upsertStudent(StudentItem item) async {
    await _studentCol.doc(item.id).set(item.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteStudent(String id) async {
    await _studentCol.doc(id).delete();
  }
}
