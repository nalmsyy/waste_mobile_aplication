#!/usr/bin/env python3
"""
Export script: best.pt (YOLO26m) -> TFLite or ONNX
====================================================
Model  : YOLO26m (Eksperimen 4 - Deteksi Sampah)
Classes: kertas, logam, pakaian, plastik, tumbuhan
Target : mobile_waste_detection/assets/models/
"""

import os
import sys
import shutil
import traceback
from pathlib import Path

# ── Root repository path (two levels up from scripts/) ──────────────────────
SCRIPT_DIR   = Path(__file__).resolve().parent
PROJECT_DIR  = SCRIPT_DIR.parent                          # mobile_waste_detection/
REPO_ROOT    = PROJECT_DIR.parent                         # repository root

MODEL_SRC    = REPO_ROOT / "best.pt"
ASSETS_DIR   = PROJECT_DIR / "assets" / "models"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

IMG_SIZE = 640

# ── Sanity checks ────────────────────────────────────────────────────────────
if not MODEL_SRC.exists():
    print(f"[ERROR] Model not found: {MODEL_SRC}")
    print("  Make sure best.pt is in the root of the repository.")
    sys.exit(1)

try:
    from ultralytics import YOLO
except ImportError:
    print("[ERROR] ultralytics not installed.")
    print("  Run:  python -m pip install ultralytics")
    sys.exit(1)

print(f"[INFO] Loading model: {MODEL_SRC}")
model = YOLO(str(MODEL_SRC))

# ── Helper: copy exported file to assets/ ───────────────────────────────────
def copy_to_assets(src: Path, dst_name: str) -> Path:
    dst = ASSETS_DIR / dst_name
    shutil.copy2(str(src), str(dst))
    print(f"[OK]   Copied to: {dst}")
    return dst

# ── Attempt 1: TFLite export ─────────────────────────────────────────────────
def export_tflite() -> bool:
    print("\n[STEP 1] Exporting to TFLite (LiteRT)...")
    try:
        export_path = model.export(
            format="tflite",
            imgsz=IMG_SIZE,
            int8=False,         # FP32 for accuracy; set True for INT8 quantisation
            dynamic=False,
            simplify=True,
        )
        if export_path is None:
            raise RuntimeError("export() returned None")

        # Ultralytics may return a string path or Path object
        tflite_file = Path(str(export_path))

        # Sometimes ultralytics creates a directory; find the .tflite inside
        if tflite_file.is_dir():
            candidates = list(tflite_file.rglob("*.tflite"))
            if not candidates:
                raise FileNotFoundError(f"No .tflite found in {tflite_file}")
            tflite_file = candidates[0]

        if not tflite_file.exists():
            raise FileNotFoundError(f"Expected file not found: {tflite_file}")

        copy_to_assets(tflite_file, "yolo26m_waste.tflite")
        print("\n[SUCCESS] TFLite export complete!")
        print(f"  -> {ASSETS_DIR / 'yolo26m_waste.tflite'}")
        return True

    except Exception as e:
        print(f"[WARN]  TFLite export failed: {e}")
        traceback.print_exc()
        return False

# ── Attempt 2: ONNX export (fallback) ────────────────────────────────────────
def export_onnx() -> bool:
    print("\n[STEP 2] Falling back to ONNX export...")
    try:
        export_path = model.export(
            format="onnx",
            imgsz=IMG_SIZE,
            dynamic=False,
            simplify=True,
            opset=17,
        )
        if export_path is None:
            raise RuntimeError("export() returned None")

        onnx_file = Path(str(export_path))

        if onnx_file.is_dir():
            candidates = list(onnx_file.rglob("*.onnx"))
            if not candidates:
                raise FileNotFoundError(f"No .onnx found in {onnx_file}")
            onnx_file = candidates[0]

        if not onnx_file.exists():
            raise FileNotFoundError(f"Expected file not found: {onnx_file}")

        copy_to_assets(onnx_file, "yolo26m_waste.onnx")
        print("\n[SUCCESS] ONNX export complete!")
        print(f"  -> {ASSETS_DIR / 'yolo26m_waste.onnx'}")
        return True

    except Exception as e:
        print(f"[ERROR] ONNX export also failed: {e}")
        traceback.print_exc()
        return False

# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("  YOLO26m Waste Detection – Model Export Script")
    print("=" * 60)
    print(f"  Source : {MODEL_SRC}")
    print(f"  Target : {ASSETS_DIR}")
    print(f"  ImgSize: {IMG_SIZE}")
    print("=" * 60)

    if export_tflite():
        print("\n[DONE] Use yolo26m_waste.tflite with tflite_flutter in Flutter.")
        print("       Set useOnnx = false in lib/services/detector_service.dart")
    elif export_onnx():
        print("\n[DONE] Use yolo26m_waste.onnx with onnxruntime_flutter in Flutter.")
        print("       Set useOnnx = true  in lib/services/detector_service.dart")
        print("\n       Also update pubspec.yaml:")
        print("         onnxruntime_flutter: ^1.0.0  # replace tflite_flutter")
    else:
        print("\n[FAIL] Both export methods failed.")
        print("  Suggestions:")
        print("  1. pip install --upgrade ultralytics onnx onnxsim")
        print("  2. pip install tensorflow  (needed for TFLite export)")
        print("  3. Check that best.pt is a valid Ultralytics YOLO model.")
        sys.exit(2)

if __name__ == "__main__":
    main()
