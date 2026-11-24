"""Photo model slot. If no trained model file exists, predict() returns None and the app
uses the symptom rules only. Put the files from the Colab notebook in backend/models/:
    models/dermascreen.tflite   models/labels.json   (e.g. ["acne","eczema",...,"healthy_other"])
"""
import json
import os
from pathlib import Path

_state = {"loaded": False, "interp": None, "labels": None}


def _load():
    if _state["loaded"]:
        return
    _state["loaded"] = True
    base = Path(os.environ.get("MODEL_DIR", "models"))
    mp, lp = base / "dermascreen.tflite", base / "labels.json"
    if not (mp.exists() and lp.exists()):
        return
    try:
        try:
            from ai_edge_litert.interpreter import Interpreter        # pip install ai-edge-litert
        except ImportError:
            try:
                from tflite_runtime.interpreter import Interpreter    # Linux / Mac
            except ImportError:
                from tensorflow.lite.python.interpreter import Interpreter  # pip install tensorflow
        it = Interpreter(model_path=str(mp))
        it.allocate_tensors()
        _state["interp"] = it
        _state["labels"] = json.loads(lp.read_text(encoding="utf-8"))
    except Exception as e:                      # a broken model must not break screening
        print("Model not loaded:", e)


def available() -> bool:
    _load()
    return _state["interp"] is not None


def predict(img):
    """img: PIL RGB image. Returns {label: probability} or None."""
    _load()
    it = _state["interp"]
    if it is None:
        return None
    import numpy as np
    inp, out = it.get_input_details()[0], it.get_output_details()[0]
    h, w = inp["shape"][1], inp["shape"][2]
    x = np.asarray(img.convert("RGB").resize((w, h)), dtype=np.float32) / 127.5 - 1.0  # MobileNetV2
    it.set_tensor(inp["index"], x[None, ...].astype(inp["dtype"]))
    it.invoke()
    p = it.get_tensor(out["index"])[0]
    return {lab: float(v) for lab, v in zip(_state["labels"], p)}