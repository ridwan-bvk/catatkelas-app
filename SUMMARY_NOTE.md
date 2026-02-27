# Summary Note - catat_kelas

Tanggal update: 2026-02-26
Lokasi project: `D:\Project\PROJECT X\sekolah-mobile-app\catat_kelas`

## Ringkasan Progress
Aplikasi keuangan sekolah sudah direfactor ke struktur modular dan sudah ditambahkan koneksi Firebase Firestore untuk **master data kategori** dan **akun pengguna**.

## Update Lanjutan (2026-02-25)
### 1) Perbaikan Bug CRUD yang "tidak terjadi apa-apa"
- Akar masalah: pemanggilan `showDialog`, `showModalBottomSheet`, dan `SnackBar` sebelumnya memakai context yang berada di atas `MaterialApp`.
- Solusi:
  - ditambahkan `navigatorKey` dan `scaffoldMessengerKey` di `MaterialApp`
  - seluruh popup/form CRUD pengguna, kategori, transaksi, backup/restore dipindahkan menggunakan `navigatorKey.currentContext`
  - notifikasi info/error dipindahkan ke `scaffoldMessengerKey.currentState`
- Hasil: tambah/edit/hapus pada Pengaturan dan popup transaksi kembali responsif.

### 2) Perbaikan UI Dark Mode pada section Akun Pengguna
- Warna teks dan ikon pada section **Akun Pengguna** disesuaikan dengan `colorScheme` aktif (light/dark).
- Tujuan: menghindari teks gelap pada background gelap saat dark mode.

### 3) Master Role Pengguna (tidak hardcoded)
- Ditambahkan entitas master role:
  - model baru `UserRoleItem`
  - koleksi Firestore baru: `master_user_roles`
- `MasterDataController` sekarang mengelola role juga:
  - fetch role saat inisialisasi
  - add/update/delete role
  - sinkron role saat restore backup
- Form tambah/edit pengguna sekarang mengambil opsi role dari master role (bukan hardcoded `Admin/Bendahara`).
- Ditambahkan section baru di Pengaturan: **Master Role Pengguna** untuk CRUD role.
- Validasi:
  - nama role tidak boleh duplikat
  - role yang masih dipakai user tidak bisa dihapus/edit

### 4) Swipe Left Delete untuk Akun Pengguna
- Pada daftar user di Pengaturan ditambahkan `Dismissible` (geser ke kiri / `endToStart`) untuk hapus cepat.
- Menu popup `Edit/Hapus` tetap tersedia sebagai alternatif.

### 5) Backup/Restore Diperluas
- Backup JSON sekarang menyertakan data `roles`.
- Restore JSON mendukung pemulihan data `roles` sekaligus kategori, user, dan transaksi.

### 6) Tahap 1 Master Group/Sub Group/Murid + Checklist Dasar Transaksi
- Ditambahkan model master baru:
  - `StudentGroupItem`
  - `StudentSubGroupItem`
  - `StudentItem`
- Ditambahkan seed data in-memory untuk:
  - Group (contoh: Kelas 1, Kelas 2)
  - Sub Group (contoh: 1A, 1B, 2A)
  - Murid (nama + NIS)
- Di menu **Transaksi** ditambahkan panel **Checklist Absensi/Kas**:
  - pilih Group
  - pilih Sub Group
  - checklist per murid (dengan detail NIS)
  - aksi `Checklist Semua` dan `Reset`
- Status checklist disimpan pada state aplikasi (in-memory) sebagai pondasi untuk tahap sinkronisasi berikutnya.

### 7) Penyederhanaan UI Filter Transaksi
- Filter kategori/tanggal tidak lagi tampil sebagai form penuh di atas list.
- Diganti menjadi **1 tombol icon filter** pada header transaksi agar area konten lebih panjang.
- Saat icon filter diklik, muncul bottom sheet filter:
  - kategori
  - tanggal awal/akhir
  - reset dan terapkan filter
- Ditambahkan indikator badge pada icon saat filter aktif.

### 8) CRUD Master Group/Sub Group/Murid + Sinkron Firestore
- Master data Group/Sub Group/Murid dipindahkan ke `MasterDataController` (single source of truth), tidak lagi hardcoded di UI transaksi.
- `MasterFirestoreRepository` ditambah dukungan koleksi:
  - `master_student_groups`
  - `master_student_sub_groups`
  - `master_students`
- `MasterDataController` kini mendukung:
  - fetch awal Group/Sub Group/Murid
  - add/update/delete Group/Sub Group/Murid
  - sinkron ke Firebase per operasi
  - sinkron data Group/Sub Group/Murid saat restore backup
- Pada tab **Pengaturan** ditambahkan section CRUD:
  - Master Group Murid
  - Master Sub Group
  - Master Murid

### 9) Kategori Ditambah Flag Master (Group/Sub Group/Murid)
- Model `CategoryItem` diperluas dengan flag:
  - `useGroup`
  - `useSubGroup`
  - `useStudent`
- Form tambah/edit kategori sekarang menyediakan checklist flag tersebut.
- Tampilan list kategori di Pengaturan menampilkan ringkasan pemakaian flag.

### 10) Transaksi Berbasis Checklist Master
- Form tambah transaksi kini membaca flag kategori.
- Jika kategori memakai Sub Group/Murid:
  - input nominal diperlakukan sebagai **nominal per item**
  - total transaksi dihitung otomatis:
    - `total = nominal_per_item x jumlah_item_terceklis`
- Validasi ditambahkan:
  - kategori yang butuh Group/Sub Group wajib memilih data master terkait
  - kategori checklist tidak bisa disimpan jika item ceklis = 0
- Label checklist transaksi kini dinamis mengikuti master aktif:
  - `Checklist {Nama Group} / {Nama Sub Group}`

### 11) Backup/Restore Diperluas Lagi
- Backup JSON kini mencakup:
  - `studentGroups`
  - `studentSubGroups`
  - `students`
- Restore JSON mendukung pemulihan penuh data master tersebut.

### 12) Revisi Flow Transaksi: Checklist Hanya Muncul Saat Edit
- Panel checklist Group/Sub Group/Murid **dihapus dari halaman utama menu Transaksi**.
- Flow baru:
  1. Tambah transaksi -> isi judul, nominal, kategori -> simpan.
  2. Setelah transaksi tersimpan, saat **Edit transaksi** baru tampil area Group/Sub Group/Murid (sesuai flag kategori).
- Untuk kategori dengan flag master:
  - nilai transaksi dihitung dari **nominal per item x jumlah item murid yang diceklis**
  - nominal yang tampil pada list transaksi menjadi nilai total hasil perhitungan tersebut.
- Metadata checklist sekarang disimpan per transaksi (`TxItem`):
  - `unitAmount`
  - `selectedGroupId`
  - `selectedSubGroupId`
  - `checkedStudentIds`

### 13) UI Transaksi Dirapikan untuk Mobile
- Header transaksi dibuat lebih ringkas:
  - icon filter + badge aktif
  - tombol tambah transaksi
- List transaksi diperbarui:
  - card spacing lebih rapih untuk layar mobile
  - avatar ikon tipe transaksi (masuk/keluar)
  - subtitle menampilkan informasi ceklis jika transaksi menggunakan checklist

### 14) Lanjutan Implementasi yang Disarankan
- Integrasi yang disarankan sebelumnya dilanjutkan:
  - checklist ditampilkan kontekstual berdasarkan kategori ber-flag master
  - kalkulasi nominal otomatis saat edit transaksi
  - validasi group/subgroup/checklist saat simpan edit transaksi

### 15) Redesign Edit Transaksi (Anti Overflow + Mobile Friendly)
- Form transaksi tidak lagi memakai bottom sheet untuk mode edit.
- Edit transaksi dipindah ke tampilan **fullscreen dialog/page** agar:
  - tidak terjadi `bottom overflow by xxx pixel`
  - checklist murid dapat di-scroll dengan nyaman
  - UX lebih stabil di Android (keyboard + viewport kecil)
- UI edit transaksi diperbarui:
  - header visual modern (card gradient + informasi konteks)
  - section checklist muncul dengan transisi `AnimatedSwitcher` (fade in/out)
  - ringkasan total otomatis tetap tampil realtime

### 16) Hardening Error Firebase Firestore Disabled/Permission
- `MasterDataController` ditingkatkan untuk mendeteksi error Firestore API disabled/permission denied.
- Saat error tipe ini terjadi:
  - app tetap berjalan dengan data lokal
  - sinkron Firebase dinonaktifkan sementara pada sesi berjalan
  - user mendapat pesan yang lebih jelas untuk aktivasi Firestore API di project
- Status Firebase di Pengaturan kini membaca status runtime controller (bukan hanya status awal bootstrap).

### 17) Alur Menabung per Murid (Checklist + Nominal Berbeda)
- Ditambahkan mode baru pada kategori untuk kasus menabung siswa:
  - `useStudentVariableAmount`: nominal berbeda per murid yang diceklis
  - `allowEmptyAmountOnCreate`: nominal boleh kosong saat tambah transaksi awal
- Implementasi pada edit transaksi:
  - saat murid diceklis, muncul input nominal per murid
  - total transaksi dihitung dari **penjumlahan nominal murid yang diceklis**
  - metadata nominal per murid disimpan pada transaksi (`checkedStudentAmounts`)
- Untuk mode non-menabung:
  - perhitungan tetap `nominal per item x jumlah item diceklis`

### 18) Validasi Input Nominal Lebih Ketat
- Input nominal transaksi dan nominal per murid sekarang difilter hanya menerima karakter numerik/desimal (`0-9`, `.` , `,`).
- Parsing nominal diubah ke `double.tryParse` dengan normalisasi koma, menghindari crash jika input tidak valid.

### 19) Rekomendasi Letak Fitur Absensi Siswa (Tanpa Mengubah Alur Transaksi)
- Absensi disarankan sebagai modul terpisah, bukan bagian transaksi nominal.
- Letak terbaik:
  - Tambahkan kartu/menu baru **Absensi Siswa** di tab **Pengaturan** atau tab baru khusus **Akademik**.
  - Data sumber tetap dari master Group/Sub Group/Murid yang sama.
  - Output absensi berdiri sendiri (hadir/izin/sakit/alpa), tidak memengaruhi nominal transaksi.

### 20) Floating Action Button Tengah + Quick Action Modern
- Ditambahkan FAB utama di tengah bottom area (`centerDocked`) dengan animasi modern:
  - tap FAB -> muncul quick menu `Transaksi` dan `Absensi`
  - animasi `fade + scale` dan rotasi ikon plus
- Tujuan: mempercepat alur input data dari semua halaman.

### 21) Modul Absensi Siswa (CRUD Sesi + Checklist Status)
- Modul Absensi Siswa diimplementasikan penuh (sumber master Group/Sub Group/Murid yang sama):
  - tambah/edit/hapus sesi absensi
  - checklist status per murid:
    - `Hadir`
    - `Sakit`
    - `Izin`
    - `Alpa`
- Ditambahkan model domain baru:
  - `AttendanceSessionItem`
  - `AttendanceStatus`
- Alur akses:
  - dari quick menu FAB -> pilih `Absensi`
  - masuk ke manager sesi absensi -> CRUD sesi
- Backup/restore kini juga mencakup `attendanceSessions`.

### 22) Penyesuaian Alur Menabung per Murid
- Ditambahkan flag kategori baru:
  - `allowEmptyAmountOnCreate` (nominal boleh kosong saat tambah)
  - `useStudentVariableAmount` (nominal berbeda per murid checklist)
- Saat mode `useStudentVariableAmount` aktif:
  - setelah murid diceklis muncul input nominal per murid
  - total transaksi dihitung dari **penjumlahan nominal murid yang diceklis**.
- Metadata nominal per murid disimpan di transaksi:
  - `checkedStudentAmounts`

### 23) Validasi Nominal Input
- Input nominal pada form transaksi dan nominal murid sekarang dibatasi karakter numerik/desimal.
- Parsing diubah ke `tryParse` + normalisasi koma agar tidak menerima karakter non-angka.

### 24) UX Absensi: Ceklis All + Judul Default Tanggal
- Pada form tambah/edit sesi absensi ditambahkan opsi percepatan input:
  - dropdown `Status Ceklis All`
  - tombol `Apply All` untuk menerapkan status ke seluruh murid dalam sub group
- Judul absensi sekarang default otomatis dari tanggal dengan format:
  - `Hari, dd MMMM yyyy`
  - contoh: `Senin, 24 Februari 2026`
- Jika judul belum diubah manual, saat tanggal diganti judul ikut ter-update otomatis.

### 25) Menu Transaksi Jadi 2 Tab (Transaksi + Absensi)
- Menu utama **Transaksi** kini dibagi menjadi 2 tab internal:
  1. `Transaksi` -> daftar transaksi + tambah/edit/hapus
  2. `Absensi` -> daftar sesi absensi tersimpan + edit/hapus
- Quick action dari FAB disesuaikan:
  - pilih `Transaksi` -> masuk tab transaksi
  - pilih `Absensi` -> langsung pindah ke tab absensi
- Tujuan: akses absensi tetap cepat tanpa mengubah alur transaksi yang sudah ada.

## Perubahan Besar di Turn Ini
### 1) Refactor Struktur Folder (Maintainable)
Struktur baru di `lib/`:
- `lib/main.dart`
- `lib/app/school_finance_app.dart`
- `lib/core/theme/app_theme.dart`
- `lib/features/finance/domain/models/tx_item.dart`
- `lib/features/master_data/domain/models/category_item.dart`
- `lib/features/master_data/domain/models/user_item.dart`
- `lib/features/master_data/data/master_firestore_repository.dart`
- `lib/features/master_data/application/master_data_controller.dart`

Tujuan refactor:
- Memisahkan tanggung jawab (`UI`, `state/controller`, `repository`, `model`).
- Memudahkan maintenance dan scaling fitur berikutnya.

### 2) Integrasi Firebase (Firestore)
- `main.dart` sekarang menjadi bootstrap Firebase:
  - `Firebase.initializeApp()` dijalankan saat startup.
  - Jika sukses -> repository Firestore diaktifkan.
  - Jika gagal -> app tetap jalan dengan fallback data lokal (offline-safe).
- Firestore repository ditambahkan untuk CRUD master data:
  - Koleksi: `master_categories`
  - Koleksi: `master_users`
  - Koleksi: `master_user_roles`
  - Koleksi: `master_student_groups`
  - Koleksi: `master_student_sub_groups`
  - Koleksi: `master_students`
- Controller `MasterDataController` mengelola:
  - sinkronisasi awal dari Firestore
  - add/update/delete kategori
  - add/update/delete user
  - replace data saat restore backup

### 3) UI Tetap Konsisten + Status Firebase
- UX utama tetap: Dashboard, Transaksi, Laporan, Pengaturan.
- Di halaman Pengaturan ditambahkan status koneksi Firebase:
  - "Firebase terhubung" / "Firebase belum terhubung"
  - error sync terakhir jika ada.

### 4) Pengaturan: Klik Akun Pengguna untuk Tambah/Kelola Transaksi & Kategori
- Pada kartu **Akun Pengguna**, item user sekarang bisa diklik.
- Saat diklik, muncul bottom sheet action modern:
  - `Tambah Transaksi`
  - `Kelola Transaksi`
  - `Tambah Kategori`
- UX dibuat tetap selaras tema app (Material 3 + warna turunan `colorScheme`).

### 5) Validasi CRUD Baru (Aman dari data bentrok)
- **Transaksi**
  - `Insert/Update` ditolak jika terdeteksi transaksi duplikat (judul, kategori, tipe, nominal, dan tanggal sama).
  - Notifikasi penolakan menggunakan `SnackBar` agar user paham alasan.
- **Kategori**
  - `Insert/Update` ditolak jika nama kategori sudah ada.
  - `Update/Delete` ditolak jika kategori sudah dipakai pada transaksi.
  - Pada list kategori ditampilkan status "Sedang dipakai transaksi" untuk transparansi.

## Langkah Implementasi Fitur (Step-by-Step)
1. Buka tab **Pengaturan**.
2. Pada section **Akun Pengguna**, klik salah satu akun.
3. Pilih aksi pada bottom sheet:
   - `Tambah Transaksi` untuk input transaksi baru.
   - `Kelola Transaksi` untuk edit/hapus transaksi yang sudah ada.
   - `Tambah Kategori` untuk menambah kategori baru.
4. Saat simpan data:
   - Sistem mengecek duplikasi transaksi.
   - Sistem mengecek duplikasi nama kategori.
   - Sistem memblokir edit/hapus kategori bila sudah dipakai transaksi.
5. Jika aksi ditolak, aplikasi menampilkan `SnackBar` dengan alasan validasi.
6. Jika valid, data langsung tersimpan dan UI otomatis refresh.

## Dependency Baru
`pubspec.yaml` ditambah:
- `firebase_core`
- `cloud_firestore`

Dependency lama tetap dipakai:
- `fl_chart`, `intl`, `google_fonts`, `pdf`, `printing`

## Validasi Teknis Setelah Refactor
- `flutter pub get` -> sukses
- `dart format lib test` -> sukses
- `flutter analyze` -> **No issues found**
- `flutter test` -> **All tests passed**

## Step-by-Step Setup Firebase (Wajib Agar Sync Aktif)
### Step 1 - Buat Project Firebase
1. Buka Firebase Console.
2. Create project baru (atau pakai existing).
3. Aktifkan Cloud Firestore (mode test untuk dev, lalu lockdown rules untuk production).

### Step 2 - Registrasi App Flutter
1. Tambahkan Android app (isi package name sesuai `android/app/build.gradle`).
2. Tambahkan Web app bila target web dipakai.
3. (Opsional) Tambahkan iOS/macOS sesuai kebutuhan deploy.

### Step 3 - Generate Konfigurasi FlutterFire
1. Install CLI:
   - `dart pub global activate flutterfire_cli`
2. Login Firebase:
   - `firebase login`
3. Dari root project jalankan:
   - `flutterfire configure`
4. Pilih project Firebase + platform yang dipakai.
5. Pastikan file `lib/firebase_options.dart` tergenerate.

### Step 4 - Integrasi `firebase_options.dart` di Main
Saat ini app pakai `Firebase.initializeApp()` default.
Untuk konfigurasi produksi multi-platform, update ke:
- `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`

Catatan:
- Setelah `flutterfire configure`, import file generated `firebase_options.dart`.

### Step 5 - Android Config Check
Pastikan file berikut tersedia/benar:
- `android/app/google-services.json` (jika workflow Firebase Android klasik digunakan)
- Gradle plugin firebase sesuai dokumentasi versi Flutter/Firebase yang dipakai.

### Step 6 - Firestore Rules (Awal)
Untuk dev sementara, bisa test mode.
Untuk production, buat rules berbasis auth + role (admin/bendahara).

### Step 7 - Verifikasi Runtime
1. Jalankan app.
2. Buka tab Pengaturan.
3. Pastikan status menunjukkan "Firebase terhubung".
4. Tambah/Edit/Hapus kategori & pengguna.
5. Cek data masuk ke koleksi:
   - `master_categories`
   - `master_users`

## Batasan Saat Ini
- Modul transaksi masih local in-memory (belum Firestore).
- Firebase Auth/role permissions belum diterapkan.
- `firebase_options.dart` belum dibuat otomatis di repo ini (menunggu `flutterfire configure` dijalankan pada environment Anda).
- Master Group/Sub Group/Murid dan checklist transaksi masih in-memory (belum CRUD di Pengaturan + belum Firestore).

## Next Step Disarankan
1. Integrasikan `firebase_options.dart` hasil `flutterfire configure`.
2. Tambah Firebase Auth + role claims (Admin/Bendahara).
3. Tambahkan CRUD master Group/Sub Group/Murid di Pengaturan.
4. Sinkronkan master Group/Sub Group/Murid + checklist transaksi ke Firestore.
5. Tambah offline cache lokal (Isar/Hive) + sync strategy.

## File yang Diubah pada Turn Ini
- `pubspec.yaml`
- `lib/main.dart`
- `lib/app/school_finance_app.dart`
- `lib/core/theme/app_theme.dart`
- `lib/features/finance/domain/models/tx_item.dart`
- `lib/features/master_data/domain/models/category_item.dart`
- `lib/features/master_data/domain/models/user_item.dart`
- `lib/features/master_data/domain/models/user_role_item.dart`
- `lib/features/master_data/domain/models/student_group_item.dart`
- `lib/features/master_data/domain/models/student_sub_group_item.dart`
- `lib/features/master_data/domain/models/student_item.dart`
- `lib/features/master_data/data/master_firestore_repository.dart`
- `lib/features/master_data/application/master_data_controller.dart`
- `test/widget_test.dart`
- `SUMMARY_NOTE.md`

## Update Lanjutan (2026-02-26)
### 1) Fix Error Saat Edit di Menu Transaksi
- Gejala: saat klik `Edit` pada transaksi tertentu, form bisa error/tidak terbuka stabil.
- Akar masalah: nilai `categoryId` pada item transaksi bisa tidak lagi valid terhadap opsi dropdown kategori aktif.
- Solusi:
  - hardening pada `showTxForm(...)` untuk fallback kategori ke kategori pertama yang tersedia jika `categoryId` transaksi tidak ditemukan
  - sinkronisasi validasi kategori juga dilakukan saat build form agar state dropdown tetap aman
  - akses `selectedCategory` dibuat aman (tidak null) agar kalkulasi dan label form tidak memicu error null

### 2) Fix FAB Quick Action `Absensi` Tidak Merespons
- Gejala: klik FAB `+` -> pilih `Absensi` terasa tidak ada aksi.
- Akar masalah: aksi sebelumnya hanya pindah ke tab `Transaksi > Absensi` tanpa membuka form tambah sesi.
- Solusi:
  - quick action FAB dipindah ke alur `postFrameCallback` agar navigasi tab + buka form berjalan stabil
  - aksi FAB `Absensi` kini memanggil `showAttendanceSessionForm()` via callback tersebut
- Hasil: flow quick add sekarang konsisten:
  - `Transaksi` -> langsung buka form tambah transaksi
  - `Absensi` -> langsung buka form tambah sesi absen

### 3) UI Disederhanakan: Tombol Tambah di Tab Di-hide
- Tombol `Tambah Transaksi` pada tab `Transaksi` dihilangkan.
- Tombol `Tambah Sesi Absen` pada tab `Absensi` dihilangkan.
- Input data baru sekarang hanya lewat FAB (quick action `Transaksi` / `Absensi`).

### 4) File Adjustment pada Update Ini
- `lib/app/school_finance_app.dart`
- `SUMMARY_NOTE.md`

### 5) Hotfix Tambahan: FAB Absensi Hanya Redirect Tab
- Gejala lanjutan: pada beberapa kondisi, pilih `Absensi` dari FAB hanya memindahkan ke tab Absensi tanpa membuka form input.
- Solusi teknis:
  - quick action FAB `Transaksi/Absensi` diubah menjadi alur async dengan jeda singkat setelah perpindahan tab agar route/tab siap
  - pengambilan context untuk form absensi diubah memakai `navigatorState.context` agar lebih stabil saat push route
- Hasil:
  - pilih FAB `Absensi` sekarang langsung membuka form `Tambah Sesi Absen`
  - tidak berhenti di redirect tab saja

### 6) Hotfix Locale `id_ID` untuk DateFormat Absensi
- Gejala: crash `LocaleDataException` saat membuka form absensi:
  - `Locale data has not been initialized, call initializeDateFormatting(<locale>)`
- Solusi teknis:
  - inisialisasi locale di bootstrap app (`main.dart`) dengan `initializeDateFormatting('id_ID')`
  - ditambah guard runtime di `showAttendanceSessionForm()` agar locale siap sebelum `DateFormat('...','id_ID')` dipakai
- Hasil:
  - form absensi tidak crash lagi karena locale date formatting sudah terinisialisasi

### 7) Form Absensi: Tambah Filter Nama Murid
- Pada form `Tambah/Edit Sesi Absen` ditambahkan input `Filter Nama` di area yang proporsional dengan kontrol `Status Ceklis`.
- Perilaku baru:
  - daftar murid dapat difilter berdasarkan nama secara realtime
  - tombol `Apply` menyesuaikan:
    - `Apply All` saat tanpa filter
    - `Apply Filter` saat filter nama aktif
  - status massal diterapkan ke daftar murid yang sedang tampil (hasil filter)

### 8) Konfirmasi Delete di Transaksi & Pengaturan
- Semua aksi hapus sekarang memakai dialog konfirmasi:
  - judul sesuai entitas (`Transaksi`, `Sesi Absen`, `Pengguna`, `Role`, `Group`, `Sub Group`, `Murid`, `Kategori`)
  - opsi: `Ya` dan `Batal`
- Cakupan:
  - hapus transaksi/absensi di tab Transaksi
  - hapus transaksi dari manager sheet
  - hapus user (popup + swipe dismiss)
  - hapus role/group/subgroup/murid/kategori di Pengaturan

### 9) Upgrade Menu Laporan: Per Transaksi + Laporan Absensi
- Menu laporan sekarang punya 2 mode utama:
  - `Transaksi`
  - `Absensi`
- Kontrol UX diperbarui agar lebih modern dan mudah dipakai:
  - segmented control untuk pilih mode laporan
  - segmented control untuk periode (`Bulanan` / `Tahunan`)
  - dropdown `Format Laporan` kontekstual
- Format pada mode `Transaksi`:
  - `Per Kategori` (ringkasan nominal per kategori)
  - `Per Transaksi` (list detail setiap transaksi)
  - export CSV/PDF tetap tersedia untuk transaksi
- Format pada mode `Absensi`:
  - `Per Sesi` (list sesi absensi per tanggal/group/subgroup)
  - `Rekap Status` (akumulasi hadir/sakit/izin/alpa)
