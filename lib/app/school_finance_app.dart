import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:catat_kelas/core/theme/app_theme.dart';
import 'package:catat_kelas/features/attendance/domain/models/attendance_session_item.dart';
import 'package:catat_kelas/features/finance/domain/models/tx_item.dart';
import 'package:catat_kelas/features/master_data/application/master_data_controller.dart';
import 'package:catat_kelas/features/master_data/data/master_firestore_repository.dart';
import 'package:catat_kelas/features/master_data/domain/models/category_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/student_sub_group_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_role_item.dart';
import 'package:catat_kelas/features/master_data/domain/models/user_item.dart';

// Safe format helpers usable anywhere in this file. They try the intl
// DateFormat/NumberFormat APIs and fall back to simple formatting if intl
// initialization isn't available (prevents LocaleDataException crashes).
String safeFormatDate(String pattern, DateTime date, [String? locale]) {
  try {
    return DateFormat(pattern, locale).format(date);
  } catch (_) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }
}

String safeFormatCurrency(double amount) {
  try {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return f.format(amount);
  } catch (_) {
    return 'Rp ${amount.toStringAsFixed(0)}';
  }
}

String attendanceCode(AttendanceStatus status) {
  switch (status) {
    case AttendanceStatus.present:
      return 'H';
    case AttendanceStatus.sick:
      return 'S';
    case AttendanceStatus.excused:
      return 'I';
    case AttendanceStatus.absent:
      return 'A';
  }
}

class SchoolFinanceApp extends StatefulWidget {
  const SchoolFinanceApp({
    super.key,
    required this.firebaseEnabled,
    required this.repository,
  });

  final bool firebaseEnabled;
  final MasterFirestoreRepository? repository;

  @override
  State<SchoolFinanceApp> createState() => _SchoolFinanceAppState();
}

class _SchoolFinanceAppState extends State<SchoolFinanceApp> {
  int tab = 0;
  bool dark = false;
  int seed = 10;
  String filterCat = '';
  DateTime? filterStart;
  DateTime? filterEnd;
  int financeTabIndex = 0;
  bool fabExpanded = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final MasterDataController masterController;

  late final List<TxItem> txs = [];
  UserProfileData userProfile = const UserProfileData();
  String selectedGroupId = '';
  String selectedSubGroupId = '';
  final List<AttendanceSessionItem> attendanceSessions = [];
  bool _intlReady = false;

  String id() => 'id-${++seed}';

  Future<void> _ensureIntlReady() async {
    if (_intlReady) return;
    await initializeDateFormatting('id_ID');
    _intlReady = true;
  }

  String _colorToHexRgb(Color color) {
    final rgb = color.value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _colorFromHexRgb(String input) {
    final hex = input.trim().toUpperCase().replaceFirst('#', '');
    if (hex.length != 6) return null;
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(hex)) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  List<CategoryItem> get categories => masterController.categories;
  List<UserItem> get users => masterController.users;
  List<UserRoleItem> get roles => masterController.roles;
  List<StudentGroupItem> get studentGroups => masterController.studentGroups;
  List<StudentSubGroupItem> get studentSubGroups =>
      masterController.studentSubGroups;
  List<StudentItem> get students => masterController.students;
  bool get hasActiveTxFilter =>
      filterCat.isNotEmpty || filterStart != null || filterEnd != null;

  @override
  void initState() {
    super.initState();
    masterController = MasterDataController(
      firebaseEnabled: widget.firebaseEnabled,
      repository: widget.repository,
    )..addListener(_onMasterChanged);
    masterController.initialize();
    _ensureSelectionValid();
  }

  void _onMasterChanged() {
    setState(() => _ensureSelectionValid());
  }

  @override
  void dispose() {
    masterController.removeListener(_onMasterChanged);
    masterController.dispose();
    super.dispose();
  }

  List<TxItem> get filtered => txs.where((t) {
        if (filterCat.isNotEmpty && t.categoryId != filterCat) return false;
        if (filterStart != null && t.date.isBefore(filterStart!)) return false;
        if (filterEnd != null && t.date.isAfter(filterEnd!)) return false;
        return true;
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double get income => txs
      .where((t) => t.type == TxType.income)
      .fold(0.0, (s, t) => s + t.amount);

  double get expense => txs
      .where((t) => t.type == TxType.expense)
      .fold(0.0, (s, t) => s + t.amount);

  void showInfo(String message) {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  bool isCategoryUsed(String categoryId) {
    return txs.any((t) => t.categoryId == categoryId);
  }

  bool isCategoryNameUsed(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return categories.any(
        (c) => c.id != exceptId && c.name.trim().toLowerCase() == normalized);
  }

  bool isGroupNameUsed(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return studentGroups.any(
        (g) => g.id != exceptId && g.name.trim().toLowerCase() == normalized);
  }

  bool isSubGroupNameUsed(String groupId, String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return studentSubGroups.any((g) =>
        g.id != exceptId &&
        g.groupId == groupId &&
        g.name.trim().toLowerCase() == normalized);
  }

  bool isStudentNameUsed(String subGroupId, String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return students.any((s) =>
        s.id != exceptId &&
        s.subGroupId == subGroupId &&
        s.name.trim().toLowerCase() == normalized);
  }

  CategoryItem? findCategoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool isRoleNameUsed(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return roles.any(
        (r) => r.id != exceptId && r.name.trim().toLowerCase() == normalized);
  }

  bool isRoleUsed(String roleName) {
    return users.any(
        (u) => u.role.trim().toLowerCase() == roleName.trim().toLowerCase());
  }

  void _ensureSelectionValid() {
    if (studentGroups.isEmpty) {
      selectedGroupId = '';
      selectedSubGroupId = '';
      return;
    }
    final hasGroup = studentGroups.any((g) => g.id == selectedGroupId);
    if (!hasGroup) {
      selectedGroupId = studentGroups.first.id;
    }
    final subGroups =
        studentSubGroups.where((x) => x.groupId == selectedGroupId).toList();
    if (subGroups.isEmpty) {
      selectedSubGroupId = '';
      return;
    }
    final hasSubGroup = subGroups.any((s) => s.id == selectedSubGroupId);
    if (!hasSubGroup) {
      selectedSubGroupId = subGroups.first.id;
    }
  }

  String attendanceLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'Hadir';
      case AttendanceStatus.sick:
        return 'Sakit';
      case AttendanceStatus.excused:
        return 'Izin';
      case AttendanceStatus.absent:
        return 'Alpa';
    }
  }

  Color attendanceColor(AttendanceStatus status, ColorScheme scheme) {
    switch (status) {
      case AttendanceStatus.present:
        return scheme.primary;
      case AttendanceStatus.sick:
        return Colors.orange;
      case AttendanceStatus.excused:
        return Colors.teal;
      case AttendanceStatus.absent:
        return scheme.error;
    }
  }

  bool isTxDuplicate({
    required String title,
    required String categoryId,
    required TxType type,
    required double amount,
    required DateTime date,
    String? exceptId,
  }) {
    final normalizedTitle = title.trim().toLowerCase();
    return txs.any((t) {
      if (exceptId != null && t.id == exceptId) return false;
      return t.title.trim().toLowerCase() == normalizedTitle &&
          t.categoryId == categoryId &&
          t.type == type &&
          t.amount == amount &&
          DateUtils.isSameDay(t.date, date);
    });
  }

  Future<bool> confirmDeleteAction({
    required String title,
    required String message,
  }) async {
    final navContext = _navigatorKey.currentState?.context;
    if (navContext == null) return false;
    final result = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openQuickAddTransaction() async {
    setState(() {
      fabExpanded = false;
      tab = 1;
      financeTabIndex = 0;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await showTxForm();
  }

  Future<void> _openQuickAddAttendance() async {
    setState(() {
      fabExpanded = false;
      tab = 1;
      financeTabIndex = 1;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await showAttendanceSessionForm();
  }

  void setSelectedGroup(String groupId) {
    final availableSubGroups =
        studentSubGroups.where((x) => x.groupId == groupId).toList();
    setState(() {
      selectedGroupId = groupId;
      selectedSubGroupId =
          availableSubGroups.isEmpty ? '' : availableSubGroups.first.id;
    });
  }

  void setSelectedSubGroup(String subGroupId) {
    setState(() => selectedSubGroupId = subGroupId);
  }

  Future<void> exportCsv(List<TxItem> data) async {
    final rows = ['Tanggal,Judul,Kategori,Tipe,Nominal'];
    for (final t in data) {
      final c = categories.firstWhere(
        (x) => x.id == t.categoryId,
        orElse: () =>
            const CategoryItem(id: 'x', name: 'Lainnya', color: Colors.grey),
      );
      rows.add(
        '${safeFormatDate('yyyy-MM-dd', t.date)},"${t.title}","${c.name}",${t.type.name},${t.amount.toStringAsFixed(0)}',
      );
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
  }

  Future<void> exportPdf(List<TxItem> data) async {
    final pdf = pw.Document();
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Laporan Keuangan Sekolah'),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Tanggal', 'Judul', 'Tipe', 'Nominal'],
            data: data
                .map((t) => [
                      safeFormatDate('dd/MM/yyyy', t.date),
                      t.title,
                      t.type.name,
                      f.format(t.amount),
                    ])
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  Future<void> exportAttendanceCsv(List<AttendanceSessionItem> data) async {
    final rows = ['Nama Siswa,Tgl,Status'];
    final sorted = [...data]..sort((a, b) => a.date.compareTo(b.date));
    for (final s in sorted) {
      for (final entry in s.studentStatus.entries) {
        final studentName = students
            .firstWhere(
              (x) => x.id == entry.key,
              orElse: () => StudentItem(
                id: entry.key,
                groupId: s.groupId,
                subGroupId: s.subGroupId,
                name: entry.key,
                nis: '-',
              ),
            )
            .name;
        rows.add(
          '"$studentName",${safeFormatDate('yyyy-MM-dd', s.date)},${attendanceCode(entry.value)}',
        );
      }
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    showInfo('CSV absensi dicopy ke clipboard.');
  }

  Future<void> exportAttendancePdf(List<AttendanceSessionItem> data) async {
    final pdf = pw.Document();
    final table = <List<String>>[];
    final sorted = [...data]..sort((a, b) => a.date.compareTo(b.date));
    for (final s in sorted) {
      for (final entry in s.studentStatus.entries) {
        final studentName = students
            .firstWhere(
              (x) => x.id == entry.key,
              orElse: () => StudentItem(
                id: entry.key,
                groupId: s.groupId,
                subGroupId: s.subGroupId,
                name: entry.key,
                nis: '-',
              ),
            )
            .name;
        table.add([
          studentName,
          safeFormatDate('dd/MM/yyyy', s.date),
          attendanceCode(entry.value),
        ]);
      }
    }
    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Laporan Absensi'),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Nama Siswa', 'Tgl', 'Status'],
            data: table,
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  Future<void> showTransactionFilterSheet() async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    String tempCat = filterCat;
    DateTime? tempStart = filterStart;
    DateTime? tempEnd = filterEnd;

    await showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter Transaksi',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tempCat.isEmpty ? 'all' : tempCat,
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('Semua Kategori')),
                  ...categories.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) =>
                    setLocal(() => tempCat = v == null || v == 'all' ? '' : v),
                decoration: const InputDecoration(
                    labelText: 'Kategori', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: tempStart ?? DateTime.now(),
                        );
                        if (picked != null) setLocal(() => tempStart = picked);
                      },
                      child: Text(tempStart == null
                          ? 'Dari tanggal'
                          : safeFormatDate('dd/MM/yyyy', tempStart!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: tempEnd ?? DateTime.now(),
                        );
                        if (picked != null) setLocal(() => tempEnd = picked);
                      },
                      child: Text(tempEnd == null
                          ? 'Sampai tanggal'
                          : safeFormatDate('dd/MM/yyyy', tempEnd!)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        filterCat = '';
                        filterStart = null;
                        filterEnd = null;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        filterCat = tempCat;
                        filterStart = tempStart;
                        filterEnd = tempEnd;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Terapkan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = ['Dashboard', 'Transaksi', 'Laporan'];
    final pages = _pages();
    final safeTab = tab.clamp(0, pages.length - 1);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Catat Kelas',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (homeCtx) {
          final screenWidth = MediaQuery.of(homeCtx).size.width;
          final fabSize = (screenWidth * 0.15).clamp(54.0, 62.0);
          final fabIconSize = (fabSize * 0.42).clamp(22.0, 27.0);
          return Scaffold(
            appBar: AppBar(
              title: Text(labels[safeTab],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  tooltip: 'Pengaturan',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () {
                    Navigator.of(homeCtx).push(
                      _buildFadeSlideRoute(
                        Scaffold(
                          appBar: AppBar(title: const Text('Pengaturan')),
                          body: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(homeCtx).colorScheme.surface,
                                  Theme.of(homeCtx)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: _settingsView(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(homeCtx)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.9),
                      Theme.of(homeCtx).colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(homeCtx).colorScheme.surface,
                    Theme.of(homeCtx).colorScheme.surfaceContainerLowest,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: pages[safeTab],
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
            floatingActionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: fabExpanded
                      ? Container(
                          key: const ValueKey('fab-menu'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.payments_outlined),
                                title: const Text('Transaksi'),
                                onTap: _openQuickAddTransaction,
                              ),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.how_to_reg_rounded),
                                title: const Text('Absensi'),
                                onTap: _openQuickAddAttendance,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                SizedBox(
                  width: fabSize,
                  height: fabSize,
                  child: FloatingActionButton(
                    onPressed: () => setState(() => fabExpanded = !fabExpanded),
                    child: AnimatedRotation(
                      turns: fabExpanded ? 0.125 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(Icons.add_rounded, size: fabIconSize),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() {
                tab = v;
                fabExpanded = false;
              }),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_rounded), label: 'Transaksi'),
                NavigationDestination(
                    icon: Icon(Icons.assessment_rounded), label: 'Laporan'),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _pages() {
    return [
      DashboardPage(txs: txs, income: income, expense: expense),
      TransactionsPage(
        initialTabIndex: financeTabIndex,
        txs: filtered,
        allCats: categories,
        hasActiveFilter: hasActiveTxFilter,
        attendanceSessions: attendanceSessions,
        allGroups: studentGroups,
        allSubGroups: studentSubGroups,
        onOpenFilter: showTransactionFilterSheet,
        onEdit: (t) => showTxForm(edit: t),
        onDelete: (t) async {
          final ok = await confirmDeleteAction(
            title: 'Hapus Transaksi',
            message: 'Apakah yakin untuk menghapus data transaksi ini?',
          );
          if (!ok) return;
          setState(() => txs.removeWhere((x) => x.id == t.id));
          showInfo('Transaksi berhasil dihapus.');
        },
        onEditAttendance: (s) => showAttendanceSessionForm(edit: s),
        onDeleteAttendance: (s) async {
          final ok = await confirmDeleteAction(
            title: 'Hapus Sesi Absen',
            message: 'Apakah yakin untuk menghapus data sesi absen ini?',
          );
          if (!ok) return;
          setState(() => attendanceSessions.removeWhere((x) => x.id == s.id));
          showInfo('Sesi absen berhasil dihapus.');
        },
        onTabChanged: (v) => setState(() => financeTabIndex = v),
      ),
      ReportsPage(
        txs: txs,
        cats: categories,
        attendanceSessions: attendanceSessions,
        groups: studentGroups,
        subGroups: studentSubGroups,
        students: students,
        onCsv: exportCsv,
        onPdf: exportPdf,
        onAttendanceCsv: exportAttendanceCsv,
        onAttendancePdf: exportAttendancePdf,
      ),
    ];
  }

  Widget _settingsView() {
    return SettingsPage(
      dark: dark,
      users: users,
      roles: roles,
      groups: studentGroups,
      subGroups: studentSubGroups,
      students: students,
      cats: categories,
      txs: txs,
      firebaseEnabled: masterController.firebaseEnabled,
      firebaseError: masterController.lastError,
      onDark: (v) => setState(() => dark = v),
      userProfile: userProfile,
      onOpenProfile: showUserProfilePage,
      onAddUser: () => showUserForm(),
      onEditUser: (u) => showUserForm(edit: u),
      onDeleteUser: (u) async {
        await masterController.deleteUser(u.id);
        showInfo(masterController.lastError ?? 'Pengguna berhasil dihapus.');
      },
      onUserTap: (u) => showUserActionSheet(u),
      onAddRole: () => showRoleForm(),
      onEditRole: (r) => showRoleForm(edit: r),
      onDeleteRole: (r) async {
        if (isRoleUsed(r.name)) {
          showInfo('Role "${r.name}" masih dipakai pengguna.');
          return;
        }
        await masterController.deleteRole(r.id);
        showInfo(masterController.lastError ?? 'Role berhasil dihapus.');
      },
      onAddGroup: () => showGroupForm(),
      onEditGroup: (g) => showGroupForm(edit: g),
      onDeleteGroup: (g) async {
        await masterController.deleteStudentGroup(g.id);
        showInfo(masterController.lastError ?? 'Group berhasil dihapus.');
      },
      onAddSubGroup: () => showSubGroupForm(),
      onEditSubGroup: (g) => showSubGroupForm(edit: g),
      onDeleteSubGroup: (g) async {
        await masterController.deleteStudentSubGroup(g.id);
        showInfo(masterController.lastError ?? 'Sub Group berhasil dihapus.');
      },
      onAddStudent: () => showStudentForm(),
      onEditStudent: (s) => showStudentForm(edit: s),
      onDeleteStudent: (s) async {
        await masterController.deleteStudent(s.id);
        showInfo(masterController.lastError ?? 'Murid berhasil dihapus.');
      },
      onAddCat: () => showCatForm(),
      onEditCat: (c) => showCatForm(edit: c),
      onDeleteCat: (c) async {
        final inUse = isCategoryUsed(c.id);
        if (inUse) {
          showInfo('Kategori "${c.name}" sudah dipakai transaksi.');
          return;
        }
        await masterController.deleteCategory(c.id);
        showInfo(masterController.lastError ?? 'Kategori berhasil dihapus.');
      },
      onBackup: backup,
      onRestore: restore,
    );
  }

  Future<void> showTxForm({TxItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    if (categories.isEmpty) {
      showInfo('Master kategori belum tersedia.');
      return;
    }
    final key = GlobalKey<FormState>();
    final t = TextEditingController(text: edit?.title ?? '');
    final a = TextEditingController(
        text: edit == null ? '' : edit.unitAmount.toStringAsFixed(0));
    String cat = edit?.categoryId ?? categories.first.id;
    if (categories.every((c) => c.id != cat)) {
      cat = categories.first.id;
    }
    TxType type = edit?.type ?? TxType.income;
    DateTime date = edit?.date ?? DateTime.now();
    String localGroupId = edit?.selectedGroupId ?? selectedGroupId;
    String localSubGroupId = edit?.selectedSubGroupId ?? selectedSubGroupId;
    final checkedIds = <String>{
      ...(edit?.checkedStudentIds ?? const <String>[])
    };
    final studentAmounts = <String, String>{
      ...((edit?.checkedStudentAmounts ?? const <String, double>{})
          .map((k, v) => MapEntry(k, v.toStringAsFixed(0)))),
    };

    await Navigator.of(navContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(edit == null ? 'Tambah Transaksi' : 'Edit Transaksi'),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: StatefulBuilder(builder: (_, setLocal) {
                if (categories.every((c) => c.id != cat)) {
                  cat = categories.first.id;
                }
                final selectedCategory =
                    findCategoryById(cat) ?? categories.first;
                final showChecklistEditor = edit != null &&
                    (selectedCategory.useGroup ||
                        selectedCategory.useSubGroup ||
                        selectedCategory.useStudent);
                final localSubGroups = studentSubGroups
                    .where((x) => x.groupId == localGroupId)
                    .toList(growable: false);
                if (localSubGroupId.isNotEmpty &&
                    localSubGroups.every((x) => x.id != localSubGroupId)) {
                  localSubGroupId =
                      localSubGroups.isEmpty ? '' : localSubGroups.first.id;
                }
                final localStudents = students
                    .where((x) => x.subGroupId == localSubGroupId)
                    .toList(growable: false);
                final localGroupName = studentGroups
                    .firstWhere(
                      (x) => x.id == localGroupId,
                      orElse: () => const StudentGroupItem(id: '-', name: '-'),
                    )
                    .name;
                final localSubGroupName = studentSubGroups
                    .firstWhere(
                      (x) => x.id == localSubGroupId,
                      orElse: () => const StudentSubGroupItem(
                          id: '-', groupId: '-', name: '-'),
                    )
                    .name;
                final selectedCount = checkedIds.length;
                final unitAmount = double.tryParse(a.text) ?? 0;
                final useVariableStudentAmount = showChecklistEditor &&
                    selectedCategory.useStudent &&
                    selectedCategory.useStudentVariableAmount;
                final computedTotal = useVariableStudentAmount
                    ? checkedIds.fold<double>(0, (sum, id) {
                        final n = double.tryParse((studentAmounts[id] ?? '')
                                .replaceAll(',', '.')) ??
                            0;
                        return sum + n;
                      })
                    : (showChecklistEditor && selectedCategory.useStudent
                        ? unitAmount * selectedCount
                        : unitAmount);
                final allowEmptyOnCreate =
                    edit == null && selectedCategory.allowEmptyAmountOnCreate;
                return Form(
                  key: key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(ctx).colorScheme.primaryContainer,
                              Theme.of(ctx).colorScheme.surfaceContainerHighest,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              edit == null
                                  ? 'Input transaksi baru'
                                  : 'Atur nominal dan data checklist',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Form adaptif untuk transaksi umum dan transaksi checklist kelas.',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: t,
                        decoration: const InputDecoration(
                            labelText: 'Judul', border: OutlineInputBorder()),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Wajib' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: a,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          labelText: (showChecklistEditor &&
                                      selectedCategory.useStudent) ||
                                  selectedCategory.allowEmptyAmountOnCreate
                              ? 'Nominal per item'
                              : 'Nominal total',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (allowEmptyOnCreate &&
                              (v == null || v.trim().isEmpty)) {
                            return null;
                          }
                          final parsed =
                              double.tryParse((v ?? '').replaceAll(',', '.'));
                          if (parsed == null || parsed <= 0) {
                            return 'Tidak valid';
                          }
                          return null;
                        },
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: cat,
                        items: categories
                            .map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setLocal(() => cat = v ?? cat),
                        decoration: const InputDecoration(
                            labelText: 'Kategori',
                            border: OutlineInputBorder()),
                      ),
                      if (showChecklistEditor)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Master: Group ${localGroupId.isEmpty ? "-" : localGroupName} | '
                              'Sub Group ${localSubGroupId.isEmpty ? "-" : localSubGroupName} | '
                              'Item ceklis: $selectedCount',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: showChecklistEditor
                            ? Column(
                                key: const ValueKey('checklist-editor'),
                                children: [
                                  const SizedBox(height: 8),
                                  if (selectedCategory.useGroup)
                                    DropdownButtonFormField<String>(
                                      value: localGroupId.isEmpty
                                          ? null
                                          : localGroupId,
                                      items: studentGroups
                                          .map((g) => DropdownMenuItem(
                                              value: g.id, child: Text(g.name)))
                                          .toList(),
                                      onChanged: (v) => setLocal(() {
                                        localGroupId = v ?? '';
                                        final sub = studentSubGroups
                                            .where((x) =>
                                                x.groupId == localGroupId)
                                            .toList();
                                        localSubGroupId =
                                            sub.isEmpty ? '' : sub.first.id;
                                        checkedIds.clear();
                                      }),
                                      decoration: const InputDecoration(
                                          labelText: 'Group',
                                          border: OutlineInputBorder()),
                                    ),
                                  if (selectedCategory.useSubGroup) ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: localSubGroupId.isEmpty
                                          ? null
                                          : localSubGroupId,
                                      items: localSubGroups
                                          .map((g) => DropdownMenuItem(
                                              value: g.id, child: Text(g.name)))
                                          .toList(),
                                      onChanged: (v) => setLocal(() {
                                        localSubGroupId = v ?? '';
                                        checkedIds.clear();
                                      }),
                                      decoration: const InputDecoration(
                                          labelText: 'Sub Group',
                                          border: OutlineInputBorder()),
                                    ),
                                  ],
                                  if (selectedCategory.useStudent) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Checklist Murid',
                                        style:
                                            Theme.of(ctx).textTheme.titleSmall,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (localStudents.isEmpty)
                                      const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                            'Belum ada murid pada sub group ini.'),
                                      )
                                    else
                                      SizedBox(
                                        height: 220,
                                        child: ListView(
                                          children: localStudents
                                              .map(
                                                (s) => CheckboxListTile(
                                                  dense: true,
                                                  value:
                                                      checkedIds.contains(s.id),
                                                  onChanged: (v) =>
                                                      setLocal(() {
                                                    if (v == true) {
                                                      checkedIds.add(s.id);
                                                      studentAmounts[s.id] =
                                                          studentAmounts[
                                                                  s.id] ??
                                                              (a.text
                                                                      .trim()
                                                                      .isEmpty
                                                                  ? ''
                                                                  : a.text
                                                                      .trim());
                                                    } else {
                                                      checkedIds.remove(s.id);
                                                      studentAmounts
                                                          .remove(s.id);
                                                    }
                                                  }),
                                                  title: Text(s.name),
                                                  subtitle:
                                                      Text('NIS ${s.nis}'),
                                                  controlAffinity:
                                                      ListTileControlAffinity
                                                          .leading,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    if (useVariableStudentAmount &&
                                        checkedIds.isNotEmpty)
                                      ...checkedIds.map((id) {
                                        final student =
                                            localStudents.firstWhere(
                                          (x) => x.id == id,
                                          orElse: () => StudentItem(
                                            id: id,
                                            groupId: localGroupId,
                                            subGroupId: localSubGroupId,
                                            name: id,
                                            nis: '-',
                                          ),
                                        );
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: TextFormField(
                                            initialValue:
                                                studentAmounts[id] ?? '',
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                  RegExp(r'[0-9.,]')),
                                            ],
                                            decoration: InputDecoration(
                                              labelText:
                                                  'Nominal ${student.name}',
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                            onChanged: (v) => setLocal(() {
                                              studentAmounts[id] = v;
                                            }),
                                          ),
                                        );
                                      }),
                                  ],
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (showChecklistEditor)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Total otomatis: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(computedTotal)} '
                              '${useVariableStudentAmount ? '(penjumlahan nominal item)' : (selectedCategory.useStudent ? '($unitAmount x $selectedCount item)' : '')}',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      SegmentedButton<TxType>(
                        segments: const [
                          ButtonSegment(
                              value: TxType.income, label: Text('Pemasukan')),
                          ButtonSegment(
                              value: TxType.expense,
                              label: Text('Pengeluaran')),
                        ],
                        selected: {type},
                        onSelectionChanged: (v) =>
                            setLocal(() => type = v.first),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(safeFormatDate('dd MMM yyyy', date)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final pick = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDate: date,
                          );
                          if (pick != null) setLocal(() => date = pick);
                        },
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            if (!key.currentState!.validate()) return;
                            if (showChecklistEditor &&
                                selectedCategory.useGroup &&
                                localGroupId.isEmpty) {
                              showInfo('Pilih group terlebih dahulu.');
                              return;
                            }
                            if (showChecklistEditor &&
                                selectedCategory.useSubGroup &&
                                localSubGroupId.isEmpty) {
                              showInfo('Pilih sub group terlebih dahulu.');
                              return;
                            }
                            final unit =
                                double.tryParse(a.text.replaceAll(',', '.')) ??
                                    0;
                            if (!allowEmptyOnCreate && unit <= 0) {
                              showInfo('Nominal wajib diisi angka yang valid.');
                              return;
                            }
                            final amount = useVariableStudentAmount
                                ? computedTotal
                                : (showChecklistEditor &&
                                        selectedCategory.useStudent
                                    ? unit * selectedCount
                                    : unit);
                            if (showChecklistEditor &&
                                selectedCategory.useStudent &&
                                selectedCount == 0) {
                              showInfo(
                                  'Checklist item masih kosong. Centang murid terlebih dahulu.');
                              return;
                            }
                            if (useVariableStudentAmount) {
                              final invalid = checkedIds.any((id) {
                                final n = double.tryParse(
                                    (studentAmounts[id] ?? '')
                                        .replaceAll(',', '.'));
                                return n == null || n <= 0;
                              });
                              if (invalid) {
                                showInfo(
                                    'Nominal tiap murid yang diceklis harus diisi angka valid.');
                                return;
                              }
                            }
                            if (isTxDuplicate(
                              title: t.text,
                              categoryId: cat,
                              type: type,
                              amount: amount,
                              date: date,
                              exceptId: edit?.id,
                            )) {
                              showInfo(
                                  'Transaksi yang sama sudah ada. Gunakan data yang berbeda.');
                              return;
                            }
                            setState(() {
                              final item = TxItem(
                                id: edit?.id ?? id(),
                                title: t.text.trim(),
                                categoryId: cat,
                                type: type,
                                amount: amount,
                                unitAmount: unit,
                                date: date,
                                selectedGroupId: showChecklistEditor
                                    ? (localGroupId.isEmpty
                                        ? null
                                        : localGroupId)
                                    : null,
                                selectedSubGroupId: showChecklistEditor
                                    ? (localSubGroupId.isEmpty
                                        ? null
                                        : localSubGroupId)
                                    : null,
                                checkedStudentIds: showChecklistEditor
                                    ? checkedIds.toList(growable: false)
                                    : const [],
                                checkedStudentAmounts: useVariableStudentAmount
                                    ? checkedIds.fold<Map<String, double>>({},
                                        (m, id) {
                                        final n = double.tryParse(
                                                (studentAmounts[id] ?? '')
                                                    .replaceAll(',', '.')) ??
                                            0;
                                        m[id] = n;
                                        return m;
                                      })
                                    : const {},
                              );
                              if (edit == null) {
                                txs.add(item);
                              } else {
                                final i =
                                    txs.indexWhere((x) => x.id == edit.id);
                                if (i >= 0) txs[i] = item;
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Simpan'),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showAttendanceSessionForm({AttendanceSessionItem? edit}) async {
    await _ensureIntlReady();
    final navState = _navigatorKey.currentState;
    if (navState == null) return;
    if (studentGroups.isEmpty) {
      showInfo('Master group murid belum tersedia.');
      return;
    }

    final defaultTitle = safeFormatDate(
        'EEEE, dd MMMM yyyy', edit?.date ?? DateTime.now(), 'id_ID');
    final titleCtrl = TextEditingController(text: edit?.title ?? defaultTitle);
    bool titleTouched = edit != null;
    DateTime date = edit?.date ?? DateTime.now();
    String groupId = edit?.groupId ?? studentGroups.first.id;
    String subGroupId = edit?.subGroupId ?? '';
    String nameFilter = '';
    final statusMap = <String, AttendanceStatus>{
      ...(edit?.studentStatus ?? const <String, AttendanceStatus>{}),
    };

    List<StudentSubGroupItem> currentSubGroups() => studentSubGroups
        .where((x) => x.groupId == groupId)
        .toList(growable: false);

    List<StudentItem> currentStudents() => students
        .where((x) => x.subGroupId == subGroupId)
        .toList(growable: false);

    if (subGroupId.isEmpty && currentSubGroups().isNotEmpty) {
      subGroupId = currentSubGroups().first.id;
    }

    AttendanceStatus bulkStatus = AttendanceStatus.present;

    await navState.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(edit == null ? 'Tambah Sesi Absen' : 'Edit Sesi Absen'),
          ),
          body: SafeArea(
            child: StatefulBuilder(
              builder: (_, setLocal) {
                final subGroups = currentSubGroups();
                final studentsInSubGroup = currentStudents();
                final normalizedNameFilter = nameFilter.trim().toLowerCase();
                final visibleStudents = normalizedNameFilter.isEmpty
                    ? studentsInSubGroup
                    : studentsInSubGroup
                        .where((s) =>
                            s.name.toLowerCase().contains(normalizedNameFilter))
                        .toList(growable: false);
                if (subGroupId.isNotEmpty &&
                    subGroups.every((x) => x.id != subGroupId)) {
                  subGroupId = subGroups.isEmpty ? '' : subGroups.first.id;
                }
                final presentCount = statusMap.values
                    .where((x) => x == AttendanceStatus.present)
                    .length;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        onChanged: (_) => titleTouched = true,
                        decoration: const InputDecoration(
                          labelText: 'Judul sesi absen',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: groupId,
                        items: studentGroups
                            .map((g) => DropdownMenuItem(
                                value: g.id, child: Text(g.name)))
                            .toList(),
                        onChanged: (v) => setLocal(() {
                          groupId = v ?? groupId;
                          final sg = currentSubGroups();
                          subGroupId = sg.isEmpty ? '' : sg.first.id;
                          statusMap.clear();
                        }),
                        decoration: const InputDecoration(
                            labelText: 'Group', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: subGroupId.isEmpty ? null : subGroupId,
                        items: subGroups
                            .map((sg) => DropdownMenuItem(
                                value: sg.id, child: Text(sg.name)))
                            .toList(),
                        onChanged: (v) => setLocal(() {
                          subGroupId = v ?? subGroupId;
                          statusMap.clear();
                        }),
                        decoration: const InputDecoration(
                            labelText: 'Sub Group',
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(safeFormatDate('dd MMM yyyy', date)),
                        subtitle: Text(
                            '$presentCount hadir dari ${studentsInSubGroup.length}'),
                        trailing: const Icon(Icons.calendar_month_rounded),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDate: date,
                          );
                          if (picked != null) {
                            setLocal(() {
                              date = picked;
                              if (!titleTouched) {
                                titleCtrl.text = safeFormatDate(
                                    'EEEE, dd MMMM yyyy', date, 'id_ID');
                              }
                            });
                          }
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Filter Nama',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                              onChanged: (v) => setLocal(() => nameFilter = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<AttendanceStatus>(
                              value: bulkStatus,
                              items: AttendanceStatus.values
                                  .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(attendanceLabel(s))))
                                  .toList(),
                              onChanged: (v) =>
                                  setLocal(() => bulkStatus = v ?? bulkStatus),
                              decoration: const InputDecoration(
                                  labelText: 'Status Ceklis',
                                  border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: () => setLocal(() {
                            for (final s in visibleStudents) {
                              statusMap[s.id] = bulkStatus;
                            }
                          }),
                          child: Text(
                            normalizedNameFilter.isEmpty
                                ? 'Apply All'
                                : 'Apply Filter',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (studentsInSubGroup.isEmpty)
                        const Text('Belum ada murid pada sub group ini.')
                      else if (visibleStudents.isEmpty)
                        const Text('Murid tidak ditemukan untuk filter ini.')
                      else
                        ...visibleStudents.map((s) {
                          final current =
                              statusMap[s.id] ?? AttendanceStatus.absent;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text(s.name),
                                    subtitle: Text('NIS ${s.nis}'),
                                    trailing: Icon(Icons.circle,
                                        size: 10,
                                        color: attendanceColor(current,
                                            Theme.of(ctx).colorScheme)),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children:
                                        AttendanceStatus.values.map((status) {
                                      final selected = current == status;
                                      return ChoiceChip(
                                        selected: selected,
                                        label: Text(attendanceLabel(status)),
                                        onSelected: (_) => setLocal(
                                            () => statusMap[s.id] = status),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              showInfo('Judul sesi absen wajib diisi.');
                              return;
                            }
                            if (subGroupId.isEmpty) {
                              showInfo('Pilih sub group terlebih dahulu.');
                              return;
                            }
                            if (studentsInSubGroup.isNotEmpty &&
                                statusMap.length != studentsInSubGroup.length) {
                              showInfo('Isi status absen untuk semua murid.');
                              return;
                            }
                            setState(() {
                              final item = AttendanceSessionItem(
                                id: edit?.id ?? id(),
                                title: title,
                                date: date,
                                groupId: groupId,
                                subGroupId: subGroupId,
                                studentStatus: Map.unmodifiable(statusMap),
                              );
                              if (edit == null) {
                                attendanceSessions.add(item);
                              } else {
                                final i = attendanceSessions
                                    .indexWhere((x) => x.id == edit.id);
                                if (i >= 0) attendanceSessions[i] = item;
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Simpan Sesi Absen'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showAttendanceManager() async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    await Navigator.of(navContext).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Absensi Siswa')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            children: [
              FilledButton.icon(
                onPressed: () => showAttendanceSessionForm(),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Sesi Absen'),
              ),
              const SizedBox(height: 10),
              if (attendanceSessions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Belum ada sesi absensi.'),
                  ),
                )
              else
                ...attendanceSessions.map((s) {
                  final present = s.studentStatus.values
                      .where((x) => x == AttendanceStatus.present)
                      .length;
                  final total = s.studentStatus.length;
                  return Card(
                    child: ListTile(
                      title: Text(s.title),
                      subtitle: Text(
                        '${safeFormatDate('dd MMM yyyy', s.date)} - Hadir $present/$total',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') {
                            showAttendanceSessionForm(edit: s);
                          } else {
                            confirmDeleteAction(
                              title: 'Hapus Sesi Absen',
                              message:
                                  'Apakah yakin untuk menghapus data sesi absen ini?',
                            ).then((ok) {
                              if (!ok) return;
                              setState(() => attendanceSessions
                                  .removeWhere((x) => x.id == s.id));
                            });
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Hapus')),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showCatForm({CategoryItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final c = TextEditingController(text: edit?.name ?? '');
    const colorOptions = <Color>[
      Color(0xFF0A84FF),
      Color(0xFF34C759),
      Color(0xFFFF9F0A),
      Color(0xFFAF52DE),
      Color(0xFFE91E63),
      Color(0xFF30B0C7),
      Color(0xFF795548),
      Color(0xFF607D8B),
    ];
    Color selectedColor = edit?.color ?? const Color(0xFF30B0C7);
    final hexCtrl = TextEditingController(text: _colorToHexRgb(selectedColor));
    String? hexError;
    bool useGroup = edit?.useGroup ?? false;
    bool useSubGroup = edit?.useSubGroup ?? false;
    bool useStudent = edit?.useStudent ?? false;
    bool allowEmptyAmountOnCreate = edit?.allowEmptyAmountOnCreate ?? false;
    bool useStudentVariableAmount = edit?.useStudentVariableAmount ?? false;
    await showDialog(
      context: navContext,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(edit == null ? 'Tambah Kategori' : 'Edit Kategori'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: c,
                    decoration:
                        const InputDecoration(labelText: 'Nama kategori')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Warna kategori',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colorOptions.map((color) {
                    final selected = selectedColor.value == color.value;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setLocal(() {
                        selectedColor = color;
                        hexCtrl.text = _colorToHexRgb(color);
                        hexError = null;
                      }),
                      child: CircleAvatar(
                        radius: selected ? 16 : 14,
                        backgroundColor: color,
                        child: selected
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hexCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'HEX Warna',
                    hintText: '#RRGGBB',
                    border: const OutlineInputBorder(),
                    errorText: hexError,
                  ),
                  onChanged: (value) => setLocal(() {
                    final parsed = _colorFromHexRgb(value);
                    if (parsed == null) {
                      hexError = 'Format HEX tidak valid (contoh: #30B0C7)';
                      return;
                    }
                    selectedColor = parsed;
                    hexError = null;
                  }),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useGroup,
                  onChanged: (v) => setLocal(() => useGroup = v ?? false),
                  title: const Text('Gunakan Group'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useSubGroup,
                  onChanged: (v) => setLocal(() => useSubGroup = v ?? false),
                  title: const Text('Gunakan Sub Group'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useStudent,
                  onChanged: (v) => setLocal(() => useStudent = v ?? false),
                  title: const Text('Gunakan Murid (Checklist)'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowEmptyAmountOnCreate,
                  onChanged: (v) =>
                      setLocal(() => allowEmptyAmountOnCreate = v ?? false),
                  title: const Text('Izinkan nominal kosong saat tambah'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useStudentVariableAmount,
                  onChanged: (v) =>
                      setLocal(() => useStudentVariableAmount = v ?? false),
                  title: const Text('Mode menabung: nominal per murid'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final name = c.text.trim();
                if (name.isEmpty) {
                  showInfo('Nama kategori wajib diisi.');
                  return;
                }
                final parsedHex = _colorFromHexRgb(hexCtrl.text);
                if (parsedHex == null) {
                  setLocal(() {
                    hexError = 'Format HEX tidak valid (contoh: #30B0C7)';
                  });
                  return;
                }
                if (isCategoryNameUsed(name, exceptId: edit?.id)) {
                  showInfo('Nama kategori sudah digunakan.');
                  return;
                }
                if (edit != null && isCategoryUsed(edit.id)) {
                  showInfo(
                      'Kategori "${edit.name}" sudah dipakai transaksi, edit tidak diizinkan.');
                  return;
                }
                final item = CategoryItem(
                  id: edit?.id ?? id(),
                  name: name,
                  color: parsedHex,
                  useGroup: useGroup,
                  useSubGroup: useSubGroup,
                  useStudent: useStudent,
                  allowEmptyAmountOnCreate: allowEmptyAmountOnCreate,
                  useStudentVariableAmount: useStudentVariableAmount,
                );
                await masterController.addOrUpdateCategory(item);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                showInfo(masterController.lastError ??
                    (edit == null
                        ? 'Kategori berhasil ditambahkan.'
                        : 'Kategori berhasil diperbarui.'));
              },
              child: const Text('Simpan'),
            )
          ],
        ),
      ),
    );
  }

  Future<void> showUserForm({UserItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final roleOptions = roles.isEmpty
        ? const [UserRoleItem(id: 'role-admin', name: 'Admin')]
        : roles;
    final saved = await Navigator.of(navContext).push<_UserFormValue>(
      _buildFadeSlideRoute(
        _UserFormPage(
          title: edit == null ? 'Tambah Pengguna' : 'Edit Pengguna',
          initialName: edit?.name ?? '',
          initialRole: edit?.role ?? roleOptions.first.name,
          roleOptions: roleOptions.map((e) => e.name).toList(growable: false),
        ),
      ),
    );
    if (saved == null) return;
    final name = saved.name.trim();
    if (name.isEmpty) {
      showInfo('Nama pengguna wajib diisi.');
      return;
    }
    await masterController.addOrUpdateUser(
      UserItem(id: edit?.id ?? id(), name: name, role: saved.role),
    );
    showInfo(masterController.lastError ??
        (edit == null
            ? 'Pengguna berhasil ditambahkan.'
            : 'Pengguna berhasil diperbarui.'));
  }

  Future<void> showRoleForm({UserRoleItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final name = await Navigator.of(navContext).push<String>(
      _buildFadeSlideRoute(
        _RoleFormPage(
          title: edit == null ? 'Tambah Role Pengguna' : 'Edit Role Pengguna',
          initialName: edit?.name ?? '',
        ),
      ),
    );
    if (name == null) return;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      showInfo('Nama role wajib diisi.');
      return;
    }
    if (isRoleNameUsed(trimmedName, exceptId: edit?.id)) {
      showInfo('Nama role sudah digunakan.');
      return;
    }
    if (edit != null && isRoleUsed(edit.name)) {
      showInfo(
          'Role "${edit.name}" masih dipakai pengguna, edit tidak diizinkan.');
      return;
    }
    await masterController.addOrUpdateRole(
      UserRoleItem(id: edit?.id ?? id(), name: trimmedName),
    );
    showInfo(masterController.lastError ??
        (edit == null
            ? 'Role pengguna berhasil ditambahkan.'
            : 'Role pengguna berhasil diperbarui.'));
  }

  Future<void> showUserProfilePage() async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final saved = await Navigator.of(navContext).push<UserProfileData>(
      _buildFadeSlideRoute(
        _UserProfilePage(initialData: userProfile),
      ),
    );
    if (saved == null) return;
    setState(() => userProfile = saved);
    showInfo('Profil pengguna berhasil disimpan.');
  }

  Future<void> showGroupForm({StudentGroupItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final c = TextEditingController(text: edit?.name ?? '');

    await showDialog(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: Text(edit == null ? 'Tambah Group' : 'Edit Group'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
              labelText: 'Nama group', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final name = c.text.trim();
              if (name.isEmpty) {
                showInfo('Nama group wajib diisi.');
                return;
              }
              if (isGroupNameUsed(name, exceptId: edit?.id)) {
                showInfo('Nama group sudah digunakan.');
                return;
              }
              await masterController.addOrUpdateStudentGroup(
                StudentGroupItem(id: edit?.id ?? id(), name: name),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              showInfo(masterController.lastError ??
                  (edit == null
                      ? 'Group berhasil ditambahkan.'
                      : 'Group berhasil diperbarui.'));
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> showSubGroupForm({StudentSubGroupItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final c = TextEditingController(text: edit?.name ?? '');
    String groupId = edit?.groupId.isNotEmpty == true
        ? edit!.groupId
        : (studentGroups.isEmpty ? '' : studentGroups.first.id);

    await showDialog(
      context: navContext,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(edit == null ? 'Tambah Sub Group' : 'Edit Sub Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: groupId.isEmpty ? null : groupId,
                items: studentGroups
                    .map((g) =>
                        DropdownMenuItem(value: g.id, child: Text(g.name)))
                    .toList(),
                onChanged: (v) => setLocal(() => groupId = v ?? groupId),
                decoration: const InputDecoration(
                    labelText: 'Group', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c,
                decoration: const InputDecoration(
                    labelText: 'Nama sub group', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final name = c.text.trim();
                if (groupId.isEmpty) {
                  showInfo('Pilih group terlebih dahulu.');
                  return;
                }
                if (name.isEmpty) {
                  showInfo('Nama sub group wajib diisi.');
                  return;
                }
                if (isSubGroupNameUsed(groupId, name, exceptId: edit?.id)) {
                  showInfo('Nama sub group sudah digunakan pada group ini.');
                  return;
                }
                await masterController.addOrUpdateStudentSubGroup(
                  StudentSubGroupItem(
                    id: edit?.id ?? id(),
                    groupId: groupId,
                    name: name,
                  ),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                showInfo(masterController.lastError ??
                    (edit == null
                        ? 'Sub Group berhasil ditambahkan.'
                        : 'Sub Group berhasil diperbarui.'));
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showStudentForm({StudentItem? edit}) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final nameCtrl = TextEditingController(text: edit?.name ?? '');
    final nisCtrl = TextEditingController(text: edit?.nis ?? '');
    String groupId = edit?.groupId.isNotEmpty == true
        ? edit!.groupId
        : (studentGroups.isEmpty ? '' : studentGroups.first.id);
    String subGroupId =
        edit?.subGroupId.isNotEmpty == true ? edit!.subGroupId : '';

    List<StudentSubGroupItem> currentSubGroups() => studentSubGroups
        .where((x) => x.groupId == groupId)
        .toList(growable: false);

    if (subGroupId.isEmpty && currentSubGroups().isNotEmpty) {
      subGroupId = currentSubGroups().first.id;
    }

    await showDialog(
      context: navContext,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(edit == null ? 'Tambah Murid' : 'Edit Murid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: groupId.isEmpty ? null : groupId,
                items: studentGroups
                    .map((g) =>
                        DropdownMenuItem(value: g.id, child: Text(g.name)))
                    .toList(),
                onChanged: (v) {
                  setLocal(() {
                    groupId = v ?? groupId;
                    final sub = currentSubGroups();
                    subGroupId = sub.isEmpty ? '' : sub.first.id;
                  });
                },
                decoration: const InputDecoration(
                    labelText: 'Group', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: subGroupId.isEmpty ? null : subGroupId,
                items: currentSubGroups()
                    .map((g) =>
                        DropdownMenuItem(value: g.id, child: Text(g.name)))
                    .toList(),
                onChanged: (v) => setLocal(() => subGroupId = v ?? subGroupId),
                decoration: const InputDecoration(
                    labelText: 'Sub Group', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nama murid', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nisCtrl,
                decoration: const InputDecoration(
                    labelText: 'NIS', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final nis = nisCtrl.text.trim();
                if (subGroupId.isEmpty) {
                  showInfo('Pilih sub group terlebih dahulu.');
                  return;
                }
                if (name.isEmpty || nis.isEmpty) {
                  showInfo('Nama murid dan NIS wajib diisi.');
                  return;
                }
                if (isStudentNameUsed(subGroupId, name, exceptId: edit?.id)) {
                  showInfo('Nama murid sudah digunakan pada sub group ini.');
                  return;
                }
                await masterController.addOrUpdateStudent(
                  StudentItem(
                    id: edit?.id ?? id(),
                    groupId: groupId,
                    subGroupId: subGroupId,
                    name: name,
                    nis: nis,
                  ),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                showInfo(masterController.lastError ??
                    (edit == null
                        ? 'Murid berhasil ditambahkan.'
                        : 'Murid berhasil diperbarui.'));
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showUserActionSheet(UserItem user) async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    await showModalBottomSheet(
      context: navContext,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(user.role, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 12),
              _ModernActionTile(
                icon: Icons.add_card_rounded,
                title: 'Tambah Transaksi',
                subtitle: 'Input pemasukan atau pengeluaran baru',
                onTap: () {
                  Navigator.pop(ctx);
                  showTxForm();
                },
              ),
              const SizedBox(height: 8),
              _ModernActionTile(
                icon: Icons.receipt_long_rounded,
                title: 'Kelola Transaksi',
                subtitle: 'Edit atau hapus transaksi dengan cepat',
                onTap: () {
                  Navigator.pop(ctx);
                  showTransactionManagerSheet();
                },
              ),
              const SizedBox(height: 8),
              _ModernActionTile(
                icon: Icons.category_rounded,
                title: 'Tambah Kategori',
                subtitle: 'Buat kategori baru sesuai kebutuhan',
                onTap: () {
                  Navigator.pop(ctx);
                  showCatForm();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showTransactionManagerSheet() async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    await showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kelola Transaksi',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Akses cepat transaksi dari menu akun pengguna.',
                  style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showTxForm();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah Transaksi'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.46,
                child: txs.isEmpty
                    ? const Center(child: Text('Belum ada transaksi.'))
                    : ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = txs[i];
                          final cat = categories.firstWhere(
                            (x) => x.id == t.categoryId,
                            orElse: () => const CategoryItem(
                              id: 'x',
                              name: 'Lainnya',
                              color: Colors.grey,
                            ),
                          );
                          return Card(
                            elevation: 0,
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              title: Text(t.title),
                              subtitle: Text(
                                '${cat.name} - ${safeFormatDate('dd MMM yyyy', t.date)}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') {
                                    Navigator.pop(ctx);
                                    showTxForm(edit: t);
                                    return;
                                  }
                                  confirmDeleteAction(
                                    title: 'Hapus Transaksi',
                                    message:
                                        'Apakah yakin untuk menghapus data transaksi ini?',
                                  ).then((ok) {
                                    if (!ok) return;
                                    setState(() =>
                                        txs.removeWhere((x) => x.id == t.id));
                                    showInfo('Transaksi berhasil dihapus.');
                                  });
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Hapus')),
                                ],
                              ),
                              leading: CircleAvatar(
                                backgroundColor: cat.color.withOpacity(0.2),
                                child: Icon(
                                  t.type == TxType.income
                                      ? Icons.south_west_rounded
                                      : Icons.north_east_rounded,
                                  color: cat.color,
                                ),
                              ),
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              horizontalTitleGap: 10,
                              minVerticalPadding: 10,
                              isThreeLine: false,
                              visualDensity: const VisualDensity(vertical: -1),
                              titleTextStyle: Theme.of(ctx)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              subtitleTextStyle:
                                  Theme.of(ctx).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> backup() async {
    final data = {
      'dark': dark,
      'userProfile': userProfile.toJson(),
      'categories': categories.map((e) => e.toJson()).toList(),
      'transactions': txs.map((e) => e.toJson()).toList(),
      'users': users.map((e) => e.toJson()).toList(),
      'roles': roles.map((e) => e.toJson()).toList(),
      'studentGroups': studentGroups.map((e) => e.toJson()).toList(),
      'studentSubGroups': studentSubGroups.map((e) => e.toJson()).toList(),
      'students': students.map((e) => e.toJson()).toList(),
      'attendanceSessions': attendanceSessions.map((e) => e.toJson()).toList(),
    };

    final text = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: text));
    if (_navigatorKey.currentContext == null) return;

    showDialog(
      context: _navigatorKey.currentContext!,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup JSON'),
        content: SingleChildScrollView(
          child: SelectableText(text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> restore() async {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;
    final c = TextEditingController();

    await showDialog(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore JSON'),
        content: TextField(
          controller: c,
          maxLines: 10,
          decoration: const InputDecoration(
              labelText: 'Paste backup JSON', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              try {
                final m = jsonDecode(c.text) as Map<String, dynamic>;
                final newCats = (m['categories'] as List<dynamic>)
                    .map(
                        (e) => CategoryItem.fromJson(e as Map<String, dynamic>))
                    .toList();
                final newTx = (m['transactions'] as List<dynamic>)
                    .map((e) => TxItem.fromJson(e as Map<String, dynamic>))
                    .toList();
                final newUsers = (m['users'] as List<dynamic>)
                    .map((e) => UserItem.fromJson(e as Map<String, dynamic>))
                    .toList();
                final newRoles = (m['roles'] as List<dynamic>?)
                        ?.map((e) =>
                            UserRoleItem.fromJson(e as Map<String, dynamic>))
                        .toList() ??
                    roles;
                final newStudentGroups = (m['studentGroups'] as List<dynamic>?)
                        ?.map((e) => StudentGroupItem.fromJson(
                            e as Map<String, dynamic>))
                        .toList() ??
                    studentGroups;
                final newStudentSubGroups =
                    (m['studentSubGroups'] as List<dynamic>?)
                            ?.map((e) => StudentSubGroupItem.fromJson(
                                e as Map<String, dynamic>))
                            .toList() ??
                        studentSubGroups;
                final newStudents = (m['students'] as List<dynamic>?)
                        ?.map((e) =>
                            StudentItem.fromJson(e as Map<String, dynamic>))
                        .toList() ??
                    students;
                final newAttendance =
                    (m['attendanceSessions'] as List<dynamic>?)
                            ?.map((e) => AttendanceSessionItem.fromJson(
                                e as Map<String, dynamic>))
                            .toList() ??
                        attendanceSessions;

                setState(() {
                  dark = m['dark'] == true;
                  userProfile = m['userProfile'] is Map
                      ? UserProfileData.fromJson(
                          Map<String, dynamic>.from(m['userProfile'] as Map))
                      : const UserProfileData();
                  txs
                    ..clear()
                    ..addAll(newTx);
                  attendanceSessions
                    ..clear()
                    ..addAll(newAttendance);
                });

                await masterController.replaceFromBackup(
                  categories: newCats,
                  users: newUsers,
                  roles: newRoles,
                  studentGroups: newStudentGroups,
                  studentSubGroups: newStudentSubGroups,
                  students: newStudents,
                );

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              } catch (_) {}
            },
            child: const Text('Restore'),
          )
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage(
      {super.key,
      required this.txs,
      required this.income,
      required this.expense});

  final List<TxItem> txs;
  final double income;
  final double expense;

  @override
  Widget build(BuildContext context) {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final scheme = Theme.of(context).colorScheme;
    final months = List.generate(
        6,
        (i) =>
            DateTime(DateTime.now().year, DateTime.now().month - (5 - i), 1));
    final incomeSpots = <FlSpot>[];
    final expenseSpots = <FlSpot>[];

    for (var i = 0; i < months.length; i++) {
      final d = months[i];
      final monthData =
          txs.where((t) => t.date.year == d.year && t.date.month == d.month);
      incomeSpots.add(FlSpot(
          i.toDouble(),
          monthData
              .where((t) => t.type == TxType.income)
              .fold(0.0, (s, t) => s + t.amount)));
      expenseSpots.add(FlSpot(
          i.toDouble(),
          monthData
              .where((t) => t.type == TxType.expense)
              .fold(0.0, (s, t) => s + t.amount)));
    }

    Widget card(String t, String v, Color c, IconData icon) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: c.withOpacity(0.16),
                    child: Icon(icon, color: c, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                        Text(t, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text('Ringkasan Kas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, cons) {
            final wide = cons.maxWidth >= 680;
            final itemW =
                wide ? (cons.maxWidth - 12) / 2 : (cons.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: itemW,
                  child: card('Total Pemasukan', f.format(income),
                      scheme.secondary, Icons.trending_up_rounded),
                ),
                SizedBox(
                  width: itemW,
                  child: card('Total Pengeluaran', f.format(expense),
                      const Color(0xFFFB7185), Icons.trending_down_rounded),
                ),
                SizedBox(
                  width: cons.maxWidth,
                  child: card('Saldo Akhir', f.format(income - expense),
                      scheme.primary, Icons.account_balance_wallet_rounded),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  titlesData: const FlTitlesData(
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                        spots: incomeSpots,
                        isCurved: true,
                        barWidth: 3,
                        color: scheme.primary,
                        dotData: const FlDotData(show: false)),
                    LineChartBarData(
                        spots: expenseSpots,
                        isCurved: true,
                        barWidth: 3,
                        color: scheme.secondary,
                        dotData: const FlDotData(show: false)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.initialTabIndex,
    required this.txs,
    required this.allCats,
    required this.hasActiveFilter,
    required this.attendanceSessions,
    required this.allGroups,
    required this.allSubGroups,
    required this.onOpenFilter,
    required this.onEdit,
    required this.onDelete,
    required this.onEditAttendance,
    required this.onDeleteAttendance,
    required this.onTabChanged,
  });

  final int initialTabIndex;
  final List<TxItem> txs;
  final List<CategoryItem> allCats;
  final bool hasActiveFilter;
  final List<AttendanceSessionItem> attendanceSessions;
  final List<StudentGroupItem> allGroups;
  final List<StudentSubGroupItem> allSubGroups;
  final VoidCallback onOpenFilter;
  final ValueChanged<TxItem> onEdit;
  final Future<void> Function(TxItem) onDelete;
  final ValueChanged<AttendanceSessionItem> onEditAttendance;
  final Future<void> Function(AttendanceSessionItem) onDeleteAttendance;
  final ValueChanged<int> onTabChanged;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    )..addListener(() {
        if (!_tabController.indexIsChanging) {
          widget.onTabChanged(_tabController.index);
        }
      });
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.initialTabIndex.clamp(0, 1);
    if (target != _tabController.index) {
      _tabController.animateTo(target);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    String groupName(String id) => widget.allGroups
        .firstWhere((x) => x.id == id,
            orElse: () => const StudentGroupItem(id: '-', name: '-'))
        .name;
    String subGroupName(String id) => widget.allSubGroups
        .firstWhere((x) => x.id == id,
            orElse: () =>
                const StudentSubGroupItem(id: '-', groupId: '-', name: '-'))
        .name;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Card(
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Data Sekolah',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            widget.hasActiveFilter
                                ? 'Filter transaksi aktif'
                                : 'Kelola transaksi dan absensi',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onOpenFilter,
                      icon: Badge(
                        isLabelVisible: widget.hasActiveFilter,
                        child: const Icon(Icons.filter_alt_outlined),
                      ),
                      tooltip: 'Filter Transaksi',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Transaksi'),
              Tab(text: 'Absensi'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (widget.txs.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 42,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 8),
                            Text('Belum ada transaksi',
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ),
                  ...widget.txs.map((t) {
                    final c = widget.allCats.firstWhere(
                        (x) => x.id == t.categoryId,
                        orElse: () => const CategoryItem(
                            id: 'x', name: 'Lainnya', color: Colors.grey));
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.color.withOpacity(0.2),
                          child: Icon(
                            t.type == TxType.income
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: c.color,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        title: Text(t.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${c.name} - ${safeFormatDate('dd MMM yyyy', t.date)}'
                          '${t.checkedStudentIds.isEmpty ? '' : ' | ceklis ${t.checkedStudentIds.length}'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async => v == 'edit'
                              ? widget.onEdit(t)
                              : await widget.onDelete(t),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Hapus')),
                          ],
                          child: Text(
                            '${t.type == TxType.income ? '+' : '-'} ${f.format(t.amount)}',
                            style: TextStyle(
                              color: c.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (widget.attendanceSessions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Belum ada sesi absensi.'),
                      ),
                    )
                  else
                    ...widget.attendanceSessions.map((s) {
                      final present = s.studentStatus.values
                          .where((x) => x == AttendanceStatus.present)
                          .length;
                      return Card(
                        child: ListTile(
                          title: Text(s.title),
                          subtitle: Text(
                            '${safeFormatDate('dd MMM yyyy', s.date)} | '
                            '${groupName(s.groupId)} / ${subGroupName(s.subGroupId)} | '
                            'Hadir $present/${s.studentStatus.length}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async => v == 'edit'
                                ? widget.onEditAttendance(s)
                                : await widget.onDeleteAttendance(s),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Hapus')),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage(
      {super.key,
      required this.txs,
      required this.cats,
      required this.attendanceSessions,
      required this.groups,
      required this.subGroups,
      required this.students,
      required this.onCsv,
      required this.onPdf,
      required this.onAttendanceCsv,
      required this.onAttendancePdf});

  final List<TxItem> txs;
  final List<CategoryItem> cats;
  final List<AttendanceSessionItem> attendanceSessions;
  final List<StudentGroupItem> groups;
  final List<StudentSubGroupItem> subGroups;
  final List<StudentItem> students;
  final Future<void> Function(List<TxItem>) onCsv;
  final Future<void> Function(List<TxItem>) onPdf;
  final Future<void> Function(List<AttendanceSessionItem>) onAttendanceCsv;
  final Future<void> Function(List<AttendanceSessionItem>) onAttendancePdf;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String reportType = 'Transaksi';
  String txPeriod = 'Bulanan';
  String txFormat = 'Per Transaksi';
  String attendancePeriod = 'Bulanan';
  String attendanceFormat = 'Rinci Bulanan';

  String _attendanceLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'Hadir';
      case AttendanceStatus.sick:
        return 'Sakit';
      case AttendanceStatus.excused:
        return 'Izin';
      case AttendanceStatus.absent:
        return 'Alpa';
    }
  }

  String attendanceCode(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'H';
      case AttendanceStatus.sick:
        return 'S';
      case AttendanceStatus.excused:
        return 'I';
      case AttendanceStatus.absent:
        return 'A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final txData = txPeriod == 'Bulanan'
        ? widget.txs
            .where((t) => t.date.year == now.year && t.date.month == now.month)
            .toList()
        : widget.txs.where((t) => t.date.year == now.year).toList();
    final attendanceData = attendancePeriod == 'Bulanan'
        ? widget.attendanceSessions
            .where((s) => s.date.year == now.year && s.date.month == now.month)
            .toList()
        : widget.attendanceSessions
            .where((s) => s.date.year == now.year)
            .toList();

    final txSummary = <String, double>{};
    for (final t in txData) {
      final c = widget.cats.firstWhere((x) => x.id == t.categoryId,
          orElse: () =>
              const CategoryItem(id: 'x', name: 'Lainnya', color: Colors.grey));
      txSummary[c.name] = (txSummary[c.name] ?? 0) + t.amount;
    }
    final attendanceSummary = <AttendanceStatus, int>{
      for (final s in AttendanceStatus.values) s: 0
    };
    for (final session in attendanceData) {
      for (final status in session.studentStatus.values) {
        attendanceSummary[status] = (attendanceSummary[status] ?? 0) + 1;
      }
    }

    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    String groupName(String id) => widget.groups
        .firstWhere((x) => x.id == id,
            orElse: () => const StudentGroupItem(id: '-', name: '-'))
        .name;
    String subGroupName(String id) => widget.subGroups
        .firstWhere((x) => x.id == id,
            orElse: () =>
                const StudentSubGroupItem(id: '-', groupId: '-', name: '-'))
        .name;
    String studentName(String id) => widget.students
        .firstWhere(
          (x) => x.id == id,
          orElse: () => StudentItem(
            id: id,
            groupId: '-',
            subGroupId: '-',
            name: id,
            nis: '-',
          ),
        )
        .name;

    final attendanceDetailRows = attendanceData
        .expand((s) => s.studentStatus.entries.map((entry) => {
              'studentName': studentName(entry.key),
              'date': s.date,
              'status': entry.value,
            }))
        .toList()
      ..sort((a, b) {
        final dateA = a['date'] as DateTime;
        final dateB = b['date'] as DateTime;
        final cmp = dateA.compareTo(dateB);
        if (cmp != 0) return cmp;
        return (a['studentName'] as String)
            .compareTo(b['studentName'] as String);
      });
    final attendanceFormatOptions = attendancePeriod == 'Bulanan'
        ? const ['Rinci Bulanan', 'Per Sesi', 'Rekap Status']
        : const ['Per Sesi', 'Rekap Status'];
    final attendanceFormatValue =
        attendanceFormatOptions.contains(attendanceFormat)
            ? attendanceFormat
            : attendanceFormatOptions.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Transaksi', label: Text('Transaksi')),
              ButtonSegment(value: 'Absensi', label: Text('Absensi')),
            ],
            selected: {reportType},
            onSelectionChanged: (v) => setState(() => reportType = v.first),
          ),
        ),
        Card(
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerHigh,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      reportType == 'Transaksi'
                          ? 'Laporan Transaksi'
                          : 'Laporan Absensi',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Bulanan', label: Text('Bulanan')),
                      ButtonSegment(value: 'Tahunan', label: Text('Tahunan')),
                    ],
                    selected: {
                      reportType == 'Transaksi' ? txPeriod : attendancePeriod
                    },
                    onSelectionChanged: (v) => setState(() {
                      if (reportType == 'Transaksi') {
                        txPeriod = v.first;
                      } else {
                        attendancePeriod = v.first;
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: reportType == 'Transaksi'
                        ? txFormat
                        : attendanceFormatValue,
                    decoration: const InputDecoration(
                      labelText: 'Format Laporan',
                      border: OutlineInputBorder(),
                    ),
                    items: (reportType == 'Transaksi'
                            ? const ['Per Transaksi', 'Per Kategori']
                            : attendanceFormatOptions)
                        .map(
                          (x) => DropdownMenuItem(
                            value: x,
                            child: Text(x),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        if (reportType == 'Transaksi') {
                          txFormat = v;
                        } else {
                          attendanceFormat = v;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (reportType == 'Transaksi') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(builder: (ctx) {
                if (txData.isEmpty) {
                  return const Text(
                      'Tidak ada data transaksi pada periode ini.');
                }
                if (txFormat == 'Per Transaksi') {
                  return Column(
                    children: txData.map((t) {
                      final c = widget.cats.firstWhere(
                        (x) => x.id == t.categoryId,
                        orElse: () => const CategoryItem(
                          id: 'x',
                          name: 'Lainnya',
                          color: Colors.grey,
                        ),
                      );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: c.color.withOpacity(0.2),
                          child: Icon(
                            t.type == TxType.income
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: c.color,
                          ),
                        ),
                        title: Text(t.title),
                        subtitle: Text(
                            "${c.name} - ${safeFormatDate('dd MMM yyyy', t.date)}"),
                        trailing: Text(
                          '${t.type == TxType.income ? '+' : '-'} ${f.format(t.amount)}',
                          style: TextStyle(
                            color: c.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }
                return Column(
                  children: txSummary.entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.key)),
                              Text(
                                f.format(e.value),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async => widget.onCsv(txData),
            icon: const Icon(Icons.table_chart),
            label: const Text('Export Excel (CSV)'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () async => widget.onPdf(txData),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: attendanceData.isEmpty
                  ? const Text('Tidak ada data absensi pada periode ini.')
                  : attendanceFormatValue == 'Rinci Bulanan'
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Nama Siswa')),
                              DataColumn(label: Text('Tgl')),
                              DataColumn(label: Text('Status')),
                            ],
                            rows: attendanceDetailRows
                                .map(
                                  (row) => DataRow(
                                    cells: [
                                      DataCell(
                                          Text(row['studentName'] as String)),
                                      DataCell(Text(safeFormatDate('dd/MM/yyyy',
                                          row['date'] as DateTime))),
                                      DataCell(Text(attendanceCode(
                                          row['status'] as AttendanceStatus))),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        )
                      : attendanceFormatValue == 'Rekap Status'
                          ? Column(
                              children: AttendanceStatus.values
                                  .map(
                                    (s) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                              child: Text(_attendanceLabel(s))),
                                          Text(
                                            '${attendanceSummary[s] ?? 0}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            )
                          : Column(
                              children: attendanceData
                                  .map(
                                    (s) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(s.title),
                                      subtitle: Text(
                                        '${safeFormatDate('dd MMM yyyy', s.date)} | '
                                        '${groupName(s.groupId)} / ${subGroupName(s.subGroupId)}',
                                      ),
                                      trailing: Text(
                                        'Hadir ${s.studentStatus.values.where((x) => x == AttendanceStatus.present).length}/${s.studentStatus.length}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async => widget.onAttendanceCsv(attendanceData),
            icon: const Icon(Icons.table_chart),
            label: const Text('Export Absensi CSV'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () async => widget.onAttendancePdf(attendanceData),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export Absensi PDF'),
          ),
        ],
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.dark,
    required this.users,
    required this.roles,
    required this.groups,
    required this.subGroups,
    required this.students,
    required this.cats,
    required this.txs,
    required this.firebaseEnabled,
    required this.firebaseError,
    required this.onDark,
    required this.userProfile,
    required this.onOpenProfile,
    required this.onAddUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onUserTap,
    required this.onAddRole,
    required this.onEditRole,
    required this.onDeleteRole,
    required this.onAddGroup,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onAddSubGroup,
    required this.onEditSubGroup,
    required this.onDeleteSubGroup,
    required this.onAddStudent,
    required this.onEditStudent,
    required this.onDeleteStudent,
    required this.onAddCat,
    required this.onEditCat,
    required this.onDeleteCat,
    required this.onBackup,
    required this.onRestore,
  });

  final bool dark;
  final List<UserItem> users;
  final List<UserRoleItem> roles;
  final List<StudentGroupItem> groups;
  final List<StudentSubGroupItem> subGroups;
  final List<StudentItem> students;
  final List<CategoryItem> cats;
  final List<TxItem> txs;
  final bool firebaseEnabled;
  final String? firebaseError;
  final ValueChanged<bool> onDark;
  final UserProfileData userProfile;
  final VoidCallback onOpenProfile;
  final VoidCallback onAddUser;
  final ValueChanged<UserItem> onEditUser;
  final Future<void> Function(UserItem) onDeleteUser;
  final ValueChanged<UserItem> onUserTap;
  final VoidCallback onAddRole;
  final ValueChanged<UserRoleItem> onEditRole;
  final Future<void> Function(UserRoleItem) onDeleteRole;
  final VoidCallback onAddGroup;
  final ValueChanged<StudentGroupItem> onEditGroup;
  final Future<void> Function(StudentGroupItem) onDeleteGroup;
  final VoidCallback onAddSubGroup;
  final ValueChanged<StudentSubGroupItem> onEditSubGroup;
  final Future<void> Function(StudentSubGroupItem) onDeleteSubGroup;
  final VoidCallback onAddStudent;
  final ValueChanged<StudentItem> onEditStudent;
  final Future<void> Function(StudentItem) onDeleteStudent;
  final VoidCallback onAddCat;
  final ValueChanged<CategoryItem> onEditCat;
  final Future<void> Function(CategoryItem) onDeleteCat;
  final VoidCallback onBackup;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        Card(
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.surfaceContainerHigh,
                  Theme.of(context).colorScheme.surfaceContainerLow,
                ],
              ),
            ),
            child: SwitchListTile(
                value: dark, onChanged: onDark, title: const Text('Dark Mode')),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: firebaseEnabled
                    ? [
                        Theme.of(context).colorScheme.primaryContainer,
                        Theme.of(context).colorScheme.surfaceContainerHigh,
                      ]
                    : [
                        Theme.of(context).colorScheme.errorContainer,
                        Theme.of(context).colorScheme.surfaceContainerHigh,
                      ],
              ),
            ),
            child: ListTile(
              leading: Icon(firebaseEnabled
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_off_rounded),
              title: Text(firebaseEnabled
                  ? 'Firebase terhubung'
                  : 'Firebase belum terhubung'),
              subtitle: Text(firebaseError ??
                  'Master kategori & pengguna tersinkron ke Firestore saat koneksi aktif.'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SettingsMenuCard(
          icon: Icons.account_circle_rounded,
          title: 'Profil Pengguna',
          subtitle: userProfile.summaryText,
          onTap: onOpenProfile,
        ),
        const SizedBox(height: 14),
        Text(
          'Master Data',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _SettingsMenuCard(
          icon: Icons.manage_accounts_rounded,
          title: 'Akun & Role Pengguna',
          subtitle: '${users.length} akun | ${roles.length} role',
          onTap: () => Navigator.of(context).push(
            _buildFadeSlideRoute(
              _UserRoleMasterPage(
                users: users,
                roles: roles,
                onAddUser: onAddUser,
                onEditUser: onEditUser,
                onDeleteUser: onDeleteUser,
                onUserTap: onUserTap,
                onAddRole: onAddRole,
                onEditRole: onEditRole,
                onDeleteRole: onDeleteRole,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SettingsMenuCard(
          icon: Icons.class_outlined,
          title: 'Master Group Murid',
          subtitle: '${groups.length} group aktif',
          onTap: () => Navigator.of(context).push(
            _buildFadeSlideRoute(
              _SimpleMasterDetailPage<StudentGroupItem>(
                title: 'Master Group Murid',
                description: 'Kelola group untuk dasar klasifikasi murid.',
                icon: Icons.class_outlined,
                addLabel: 'Tambah Group',
                emptyText: 'Belum ada group.',
                deleteTitle: 'Hapus Group',
                deleteMessage: 'Apakah yakin untuk menghapus data group ini?',
                items: groups,
                itemId: (x) => x.id,
                itemTitle: (x) => x.name,
                itemSubtitle: (x) =>
                    '${subGroups.where((s) => s.groupId == x.id).length} sub group',
                onAdd: onAddGroup,
                onEdit: onEditGroup,
                onDelete: onDeleteGroup,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SettingsMenuCard(
          icon: Icons.account_tree_outlined,
          title: 'Master Sub Group',
          subtitle: '${subGroups.length} sub group',
          onTap: () => Navigator.of(context).push(
            _buildFadeSlideRoute(
              _SimpleMasterDetailPage<StudentSubGroupItem>(
                title: 'Master Sub Group',
                description: 'Hubungkan sub group dengan group induk.',
                icon: Icons.account_tree_outlined,
                addLabel: 'Tambah Sub Group',
                emptyText: 'Belum ada sub group.',
                deleteTitle: 'Hapus Sub Group',
                deleteMessage:
                    'Apakah yakin untuk menghapus data sub group ini?',
                items: subGroups,
                itemId: (x) => x.id,
                itemTitle: (x) => x.name,
                itemSubtitle: (x) => groups
                    .firstWhere(
                      (g) => g.id == x.groupId,
                      orElse: () => const StudentGroupItem(id: '-', name: '-'),
                    )
                    .name,
                onAdd: onAddSubGroup,
                onEdit: onEditSubGroup,
                onDelete: onDeleteSubGroup,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SettingsMenuCard(
          icon: Icons.groups_outlined,
          title: 'Master Murid',
          subtitle: '${students.length} murid',
          onTap: () => Navigator.of(context).push(
            _buildFadeSlideRoute(
              _SimpleMasterDetailPage<StudentItem>(
                title: 'Master Murid',
                description: 'Daftar murid per sub group beserta NIS.',
                icon: Icons.groups_outlined,
                addLabel: 'Tambah Murid',
                emptyText: 'Belum ada murid.',
                deleteTitle: 'Hapus Murid',
                deleteMessage: 'Apakah yakin untuk menghapus data murid ini?',
                items: students,
                itemId: (x) => x.id,
                itemTitle: (x) => x.name,
                itemSubtitle: (x) => 'NIS ${x.nis}',
                onAdd: onAddStudent,
                onEdit: onEditStudent,
                onDelete: onDeleteStudent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SettingsMenuCard(
          icon: Icons.category_rounded,
          title: 'Master Kategori',
          subtitle: '${cats.length} kategori',
          onTap: () => Navigator.of(context).push(
            _buildFadeSlideRoute(
              _SimpleMasterDetailPage<CategoryItem>(
                title: 'Master Kategori',
                description:
                    'Atur kategori transaksi dan keterkaitan data master.',
                icon: Icons.category_rounded,
                addLabel: 'Tambah Kategori',
                emptyText: 'Belum ada kategori.',
                deleteTitle: 'Hapus Kategori',
                deleteMessage:
                    'Apakah yakin untuk menghapus data kategori ini?',
                items: cats,
                itemId: (x) => x.id,
                itemTitle: (x) => x.name,
                itemSubtitle: (x) => [
                  if (x.useGroup) 'group',
                  if (x.useSubGroup) 'sub group',
                  if (x.useStudent) 'murid',
                  if (isCategoryUsed(x.id, txs)) 'dipakai transaksi',
                ].isEmpty
                    ? 'tanpa master'
                    : [
                        if (x.useGroup) 'group',
                        if (x.useSubGroup) 'sub group',
                        if (x.useStudent) 'murid',
                        if (isCategoryUsed(x.id, txs)) 'dipakai transaksi',
                      ].join(' | '),
                leadingBuilder: (_, item) => CircleAvatar(
                  backgroundColor: item.color.withOpacity(0.22),
                  child: CircleAvatar(radius: 8, backgroundColor: item.color),
                ),
                onAdd: onAddCat,
                onEdit: onEditCat,
                onDelete: onDeleteCat,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
            onPressed: onBackup,
            icon: const Icon(Icons.backup_rounded),
            label: const Text('Backup Data')),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore Data')),
      ],
    );
  }
}

bool isCategoryUsed(String categoryId, List<TxItem> txs) {
  return txs.any((t) => t.categoryId == categoryId);
}

class _SettingsMenuCard extends StatelessWidget {
  const _SettingsMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailIntroCard extends StatelessWidget {
  const _DetailIntroCard({
    required this.title,
    required this.subtitle,
    required this.onAdd,
    required this.addLabel,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final VoidCallback onAdd;
  final String addLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer,
              scheme.surfaceContainerLow,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(addLabel),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Container _deleteBackground(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
  );
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Ya, Hapus'),
        ),
      ],
    ),
  );
  return ok == true;
}

PageRoute<T> _buildFadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, animation, __) => FadeTransition(
      opacity: animation,
      child: page,
    ),
    transitionsBuilder: (_, animation, __, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return SlideTransition(position: slide, child: child);
    },
  );
}

class _SimpleMasterDetailPage<T> extends StatelessWidget {
  const _SimpleMasterDetailPage({
    required this.title,
    required this.description,
    required this.icon,
    required this.addLabel,
    required this.emptyText,
    required this.deleteTitle,
    required this.deleteMessage,
    required this.items,
    required this.itemId,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.leadingBuilder,
    this.onItemTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final String addLabel;
  final String emptyText;
  final String deleteTitle;
  final String deleteMessage;
  final List<T> items;
  final String Function(T) itemId;
  final String Function(T) itemTitle;
  final String? Function(T) itemSubtitle;
  final Widget Function(BuildContext context, T item)? leadingBuilder;
  final VoidCallback onAdd;
  final ValueChanged<T> onEdit;
  final Future<void> Function(T) onDelete;
  final ValueChanged<T>? onItemTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          _DetailIntroCard(
            title: title,
            subtitle: description,
            onAdd: onAdd,
            addLabel: addLabel,
            icon: icon,
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(emptyText),
              ),
            )
          else
            ...items.map(
              (item) => Dismissible(
                key: ValueKey('${title.toLowerCase()}-${itemId(item)}'),
                direction: DismissDirection.endToStart,
                background: _deleteBackground(context),
                confirmDismiss: (_) async {
                  final ok = await _confirmDelete(
                    context,
                    title: deleteTitle,
                    message: deleteMessage,
                  );
                  if (!ok) return false;
                  await onDelete(item);
                  return true;
                },
                child: Card(
                  elevation: 0,
                  child: ListTile(
                    onTap: onItemTap == null ? null : () => onItemTap!(item),
                    leading: leadingBuilder?.call(context, item) ??
                        CircleAvatar(child: Icon(icon, size: 18)),
                    title: Text(itemTitle(item)),
                    subtitle: itemSubtitle(item) == null
                        ? null
                        : Text(itemSubtitle(item)!),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          onEdit(item);
                          return;
                        }
                        final ok = await _confirmDelete(
                          context,
                          title: deleteTitle,
                          message: deleteMessage,
                        );
                        if (!ok) return;
                        await onDelete(item);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Hapus')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserRoleMasterPage extends StatelessWidget {
  const _UserRoleMasterPage({
    required this.users,
    required this.roles,
    required this.onAddUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onUserTap,
    required this.onAddRole,
    required this.onEditRole,
    required this.onDeleteRole,
  });

  final List<UserItem> users;
  final List<UserRoleItem> roles;
  final VoidCallback onAddUser;
  final ValueChanged<UserItem> onEditUser;
  final Future<void> Function(UserItem) onDeleteUser;
  final ValueChanged<UserItem> onUserTap;
  final VoidCallback onAddRole;
  final ValueChanged<UserRoleItem> onEditRole;
  final Future<void> Function(UserRoleItem) onDeleteRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun & Role Pengguna')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          _DetailIntroCard(
            title: 'Master Pengguna',
            subtitle: 'Kelola akun pengguna dan role dalam satu halaman.',
            onAdd: onAddUser,
            addLabel: 'Tambah Pengguna',
            icon: Icons.person_add_alt_1_rounded,
          ),
          const SizedBox(height: 10),
          if (users.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Belum ada pengguna.'),
              ),
            )
          else
            ...users.map(
              (u) => Dismissible(
                key: ValueKey('user-master-${u.id}'),
                direction: DismissDirection.endToStart,
                background: _deleteBackground(context),
                confirmDismiss: (_) async {
                  final ok = await _confirmDelete(
                    context,
                    title: 'Hapus Pengguna',
                    message: 'Apakah yakin untuk menghapus data pengguna ini?',
                  );
                  if (!ok) return false;
                  await onDeleteUser(u);
                  return true;
                },
                child: Card(
                  elevation: 0,
                  child: ListTile(
                    onTap: () => onUserTap(u),
                    leading: CircleAvatar(
                      child: Text(u.name.isEmpty ? '?' : u.name[0]),
                    ),
                    title: Text(u.name),
                    subtitle: Text(u.role),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          onEditUser(u);
                          return;
                        }
                        final ok = await _confirmDelete(
                          context,
                          title: 'Hapus Pengguna',
                          message:
                              'Apakah yakin untuk menghapus data pengguna ini?',
                        );
                        if (!ok) return;
                        await onDeleteUser(u);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Hapus')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _DetailIntroCard(
            title: 'Master Role',
            subtitle: 'Role dipakai sebagai akses dan identitas akun.',
            onAdd: onAddRole,
            addLabel: 'Tambah Role',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 10),
          if (roles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Belum ada role pengguna.'),
              ),
            )
          else
            ...roles.map(
              (r) => Dismissible(
                key: ValueKey('role-master-${r.id}'),
                direction: DismissDirection.endToStart,
                background: _deleteBackground(context),
                confirmDismiss: (_) async {
                  final ok = await _confirmDelete(
                    context,
                    title: 'Hapus Role',
                    message: 'Apakah yakin untuk menghapus data role ini?',
                  );
                  if (!ok) return false;
                  await onDeleteRole(r);
                  return true;
                },
                child: Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.badge_outlined),
                    ),
                    title: Text(r.name),
                    subtitle: users.any((u) => u.role == r.name)
                        ? const Text('Sedang dipakai pengguna')
                        : const Text('Belum dipakai'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          onEditRole(r);
                          return;
                        }
                        final ok = await _confirmDelete(
                          context,
                          title: 'Hapus Role',
                          message:
                              'Apakah yakin untuk menghapus data role ini?',
                        );
                        if (!ok) return;
                        await onDeleteRole(r);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Hapus')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserFormValue {
  const _UserFormValue({required this.name, required this.role});

  final String name;
  final String role;
}

class _UserFormPage extends StatefulWidget {
  const _UserFormPage({
    required this.title,
    required this.initialName,
    required this.initialRole,
    required this.roleOptions,
  });

  final String title;
  final String initialName;
  final String initialRole;
  final List<String> roleOptions;

  @override
  State<_UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<_UserFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late String _role;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer,
                        scheme.surfaceContainerLow,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: const Text(
                      'Isi data akun pengguna dengan nama dan role aktif.'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Pengguna',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _role,
                items: widget.roleOptions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(growable: false),
                onChanged: (v) => setState(() => _role = v ?? _role),
                decoration: const InputDecoration(
                  labelText: 'Role Pengguna',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    if (_formKey.currentState?.validate() != true) return;
                    Navigator.pop(
                      context,
                      _UserFormValue(name: _nameCtrl.text.trim(), role: _role),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Simpan Pengguna'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleFormPage extends StatefulWidget {
  const _RoleFormPage({
    required this.title,
    required this.initialName,
  });

  final String title;
  final String initialName;

  @override
  State<_RoleFormPage> createState() => _RoleFormPageState();
}

class _RoleFormPageState extends State<_RoleFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Card(
                elevation: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer,
                        scheme.surfaceContainerLow,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child:
                      const Text('Role menentukan akses dan identitas akun.'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Role',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama role wajib diisi'
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    if (_formKey.currentState?.validate() != true) return;
                    Navigator.pop(context, _nameCtrl.text.trim());
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Simpan Role'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserProfileData {
  const UserProfileData({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.photoPath,
  });

  final String fullName;
  final String email;
  final String phone;
  final String address;
  final String? photoPath;

  UserProfileData copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? address,
    String? photoPath,
    bool clearPhoto = false,
  }) {
    return UserProfileData(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'address': address,
        'photoPath': photoPath,
      };

  factory UserProfileData.fromJson(Map<String, dynamic> json) {
    return UserProfileData(
      fullName: (json['fullName'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      photoPath: json['photoPath'] as String?,
    );
  }

  String get summaryText {
    if (fullName.trim().isNotEmpty) {
      return email.trim().isNotEmpty ? '$fullName | $email' : fullName;
    }
    return 'Atur foto dan informasi profil';
  }
}

class _UserProfilePage extends StatefulWidget {
  const _UserProfilePage({required this.initialData});

  final UserProfileData initialData;

  @override
  State<_UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<_UserProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String? _photoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialData.fullName);
    _emailCtrl = TextEditingController(text: widget.initialData.email);
    _phoneCtrl = TextEditingController(text: widget.initialData.phone);
    _addressCtrl = TextEditingController(text: widget.initialData.address);
    _photoPath = widget.initialData.photoPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (!mounted || file == null) return;
      setState(() => _photoPath = file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengambil foto profil.')),
      );
    }
  }

  Future<void> _openPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Ambil dari Kamera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Pilih dari Galeri'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Hapus Foto'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _photoPath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveProfile() {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final profile = UserProfileData(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      photoPath: _photoPath,
    );
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      Navigator.pop(context, profile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarText =
        _nameCtrl.text.trim().isEmpty ? 'U' : _nameCtrl.text.trim()[0];
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Card(
                  elevation: 0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer,
                          scheme.surfaceContainerLow,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: scheme.primary.withOpacity(0.16),
                              backgroundImage: _photoPath == null
                                  ? null
                                  : FileImage(File(_photoPath!)),
                              child: _photoPath == null
                                  ? Text(
                                      avatarText.toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: scheme.primary,
                                          ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _openPhotoOptions,
                                borderRadius: BorderRadius.circular(20),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: scheme.primary,
                                  child: Icon(
                                    Icons.camera_alt_rounded,
                                    size: 18,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Foto Profil',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(
                          'Tap ikon kamera untuk upload atau ganti foto',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama lengkap wajib diisi'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Email wajib diisi';
                    final valid =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                    return valid ? null : 'Format email tidak valid';
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Nomor Telepon',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Nomor telepon wajib diisi';
                    if (value.length < 8) return 'Nomor telepon terlalu pendek';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Alamat',
                    prefixIcon: Icon(Icons.home),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Alamat wajib diisi'
                      : null,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveProfile,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Menyimpan...' : 'Simpan Profil'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernActionTile extends StatelessWidget {
  const _ModernActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
