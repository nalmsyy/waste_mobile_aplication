# 🗑️ Deteksi Sampah — Aplikasi Mobile Flutter

Aplikasi deteksi sampah **realtime** berbasis kamera yang menggunakan model **YOLO26m (Eksperimen 4)** yang di-export ke format **TFLite** (atau ONNX sebagai fallback) untuk berjalan langsung di smartphone tanpa koneksi internet.

---

## 📦 Model

| Properti | Detail |
|---|---|
| **Arsitektur** | YOLO26m |
| **Eksperimen** | Eksperimen 4 – Dataset Asli Roboflow |
| **File sumber** | `best.pt` (root repository) |
| **Precision** | 0.973 |
| **Recall** | 0.955 |
| **mAP@50** | 0.984 |
| **mAP@50-95** | 0.843 |

## 🏷️ Kelas Deteksi

| ID | Kelas |
|---|---|
| 0 | Kertas |
| 1 | Logam |
| 2 | Pakaian |
| 3 | Plastik |
| 4 | Tumbuhan |

---

## 🚀 Cara Menjalankan

### 1. Export Model `best.pt` ke TFLite / ONNX

> **Wajib dilakukan sekali** sebelum menjalankan aplikasi Flutter.

Buka terminal di root repository (folder yang berisi `best.pt`):

```bash
# Install Ultralytics (sekali saja)
python -m pip install ultralytics

# Jalankan script export
python mobile_waste_detection/scripts/export_model.py
```

Script akan:
1. **Mencoba export ke TFLite** → `assets/models/yolo26m_waste.tflite`
2. **Jika TFLite gagal**, fallback ke ONNX → `assets/models/yolo26m_waste.onnx`

> **Catatan:** Export TFLite membutuhkan TensorFlow:
> ```bash
> pip install tensorflow
> ```

---

### 2. Setup Flutter

#### Prasyarat
- Flutter SDK ≥ 3.2.0 → [Install Flutter](https://docs.flutter.dev/get-started/install)
- Android Studio / VS Code
- Android SDK (API 21+) atau Xcode (untuk iOS)
- Perangkat fisik atau emulator dengan kamera

#### Install Dependencies

```bash
cd mobile_waste_detection
flutter pub get
```

#### Jalankan Aplikasi

```bash
flutter run
```

Atau untuk build release APK:

```bash
flutter build apk --release
```

---

## 📁 Struktur Project

```
mobile_waste_detection/
├── lib/
│   ├── main.dart                     # Entry point + splash screen
│   ├── models/
│   │   └── detection.dart            # Data class Detection
│   ├── pages/
│   │   └── detection_page.dart       # Halaman utama kamera + deteksi
│   ├── services/
│   │   ├── detector_service.dart     # Inference TFLite + parsing output
│   │   ├── image_utils.dart          # YUV→RGB, letterbox, normalisasi
│   │   └── nms.dart                  # Non-Maximum Suppression
│   └── widgets/
│       ├── bounding_box_painter.dart # Custom painter bounding box
│       └── detection_hud.dart        # FPS bar, count chip, slider
├── assets/
│   ├── models/
│   │   └── yolo26m_waste.tflite      # ← letakkan model di sini (setelah export)
│   └── labels/
│       └── labels.txt                # 5 kelas
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml       # Permission CAMERA
├── ios/
│   └── Runner/
│       └── Info.plist                # NSCameraUsageDescription
├── scripts/
│   └── export_model.py              # Script export best.pt
└── pubspec.yaml
```

---

## 🎮 Fitur Aplikasi

| Fitur | Deskripsi |
|---|---|
| 📷 Preview Realtime | Live kamera dengan bounding box overlay |
| 🏷️ Label + Confidence | Nama kelas dan persentase keyakinan |
| 📊 FPS Counter | Frame per detik inference |
| 🔢 Jumlah per Kelas | Chip count untuk setiap kelas terdeteksi |
| 🎚️ Confidence Slider | Atur threshold 5%–95% (default: 20%) |
| ⏸️ Pause / Resume | Hentikan sementara deteksi |
| 🔄 Switch Kamera | Ganti kamera depan/belakang |
| 🌙 Dark Mode | Tema gelap modern |
| ✈️ Offline | Semua inference di perangkat, tanpa server |

---

## ⚙️ Cara Mengatur Confidence Threshold

1. Buka aplikasi → tap ikon **tune** (kanan atas) untuk menampilkan kontrol
2. Geser slider **Confidence threshold** ke kiri (lebih sensitif) atau kanan (lebih ketat)
3. Nilai default: **20%** — cocok untuk kondisi pencahayaan normal

> **Tips:**
> - Kurangi threshold (10–15%) jika benda terlalu jauh/kecil
> - Naikkan threshold (40–60%) untuk mengurangi false positive

---

## 🔄 Cara Mengganti Model

1. Letakkan file TFLite baru di:
   ```
   mobile_waste_detection/assets/models/yolo26m_waste.tflite
   ```
2. Jika nama file berbeda, ubah konstanta `_modelAsset` di:
   ```dart
   // lib/services/detector_service.dart, baris ~20
   static const String _modelAsset = 'assets/models/NAMA_MODEL_BARU.tflite';
   ```
3. Jalankan ulang `flutter run`

---

## 🔁 Fallback ONNX Runtime (Jika TFLite Gagal)

Jika export TFLite tidak berhasil dan Anda menggunakan file `.onnx`:

### 1. Update `pubspec.yaml`

```yaml
dependencies:
  # Hapus atau comment:
  # tflite_flutter: ^0.10.4

  # Tambahkan:
  onnxruntime: ^1.18.0
```

### 2. Update `detector_service.dart`

Ganti implementasi `_loadModel()` dan `detect()` menggunakan API `OrtSession` dari package `onnxruntime`. Contoh:

```dart
import 'package:onnxruntime/onnxruntime.dart';

OrtSession? _session;

Future<void> _loadModel() async {
  OrtEnv.instance.init();
  final sessionOptions = OrtSessionOptions();
  final rawModel = await rootBundle.load('assets/models/yolo26m_waste.onnx');
  _session = OrtSession.fromBuffer(rawModel.buffer.asUint8List(), sessionOptions);
}
```

---

## ⚠️ Catatan Performa

> **YOLO26m cukup berat untuk perangkat mobile.**
> FPS sangat bergantung pada spesifikasi HP.

| Kategori HP | Estimasi FPS |
|---|---|
| High-end (Snapdragon 8 Gen 2+) | 10–20 FPS |
| Mid-range (Snapdragon 7xx) | 5–12 FPS |
| Low-end | 1–5 FPS |

**Tips meningkatkan performa:**
- Export model dengan `int8=True` (quantization) — akurasi sedikit turun, kecepatan naik 2–4×
- Kurangi `imgsz` ke 320 saat export (akurasi lebih rendah, performa lebih baik)
- Aktifkan NNAPI delegate di Android (edit `InterpreterOptions` di `detector_service.dart`)

```dart
// Aktifkan NNAPI delegate untuk Android
final options = InterpreterOptions()
  ..addDelegate(NnApiDelegate())
  ..threads = 4;
```

---

## 🛠️ Troubleshooting

### ❌ `FileSystemException: assets/models/yolo26m_waste.tflite not found`
→ Jalankan `export_model.py` terlebih dahulu (lihat langkah 1).

### ❌ `Camera permission denied`
→ Buka **Pengaturan Aplikasi** di HP → Izinkan akses kamera.

### ❌ `flutter pub get` gagal / package tidak ditemukan
→ Pastikan Flutter SDK sudah terbaru:
```bash
flutter upgrade
flutter pub cache repair
```

### ❌ Build Android gagal – `minSdkVersion`
→ Pastikan `minSdkVersion` di `android/app/build.gradle` minimal `21`.

### ❌ `tflite_flutter` tidak tersedia di platform
→ Gunakan fallback ONNX Runtime (lihat bagian Fallback di atas).

---

## 📄 Lisensi

Project ini dibuat untuk keperluan penelitian/tugas akademis. Model YOLO26m menggunakan lisensi Ultralytics AGPL-3.0.
