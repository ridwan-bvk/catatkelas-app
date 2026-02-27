import 'package:catat_kelas/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:catat_kelas/app/school_finance_app.dart';
import 'package:catat_kelas/features/master_data/data/master_firestore_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');

  bool firebaseEnabled = false;
  MasterFirestoreRepository? repository;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    repository = MasterFirestoreRepository(FirebaseFirestore.instance);
    firebaseEnabled = true;
  } catch (_) {
    firebaseEnabled = false;
  }

  runApp(SchoolFinanceApp(
      firebaseEnabled: firebaseEnabled, repository: repository));
}
