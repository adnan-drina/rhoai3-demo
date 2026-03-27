"""Edge inference helpers for face recognition via KServe v2 API.

Derived from step-11 remote_infer.py, adapted for the edge camera app:
- preprocess() accepts a BGR numpy array (no file I/O per frame)
- detect_faces() provides a single-call interface for the Streamlit app
"""

import cv2
import cv2.dnn
import numpy as np
import requests

CLASSES = {0: "adnan", 1: "unknown_face"}
COLORS = {0: (0, 200, 0), 1: (0, 0, 200)}


def preprocess(img_bgr, imgsz: int = 640):
    """Create ONNX-compatible blob from a BGR numpy array."""
    h, w, _ = img_bgr.shape
    scale = (h / imgsz, w / imgsz)
    blob = cv2.dnn.blobFromImage(
        img_bgr, scalefactor=1 / 255, size=(imgsz, imgsz), swapRB=True
    )
    return blob, scale


def postprocess(response_data, scale, img_bgr, conf_threshold: float = 0.25):
    """Parse ONNX output tensor, apply NMS, return annotated image + detections."""
    outputs = np.array([cv2.transpose(response_data[0])])
    rows = outputs.shape[1]

    boxes, scores, class_ids = [], [], []
    for i in range(rows):
        classes_scores = outputs[0][i][4:]
        (_, max_score, _, (_, max_class_idx)) = cv2.minMaxLoc(classes_scores)
        if max_score >= conf_threshold:
            cx, cy, w, h = outputs[0][i][:4]
            boxes.append([cx - 0.5 * w, cy - 0.5 * h, w, h])
            scores.append(max_score)
            class_ids.append(max_class_idx)

    result_boxes = cv2.dnn.NMSBoxes(boxes, scores, conf_threshold, 0.45, 0.5)
    detections = []
    annotated = img_bgr.copy()

    for idx in result_boxes:
        box = boxes[idx]
        cid = class_ids[idx]
        conf = scores[idx]
        detections.append({
            "class_id": cid,
            "class_name": CLASSES.get(cid, "unknown"),
            "confidence": float(conf),
        })
        x1 = round(box[0] * scale[1])
        y1 = round(box[1] * scale[0])
        x2 = round((box[0] + box[2]) * scale[1])
        y2 = round((box[1] + box[3]) * scale[0])
        color = COLORS.get(cid, (128, 128, 128))
        label = f"{CLASSES.get(cid, 'unknown')} {conf:.2f}"
        cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
        (lw, lh), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(annotated, (x1, y1 - lh - 4), (x1 + lw, y1), color, cv2.FILLED)
        cv2.putText(
            annotated, label, (x1, y1 - 2),
            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA,
        )

    return annotated, detections


def send_request(blob, endpoint: str, timeout: int = 10):
    """Send inference request to KServe v2 endpoint, return parsed output."""
    payload = {
        "inputs": [{
            "name": "images",
            "shape": list(blob.shape),
            "datatype": "FP32",
            "data": blob.flatten().tolist(),
        }]
    }
    resp = requests.post(endpoint, json=payload, timeout=timeout)
    resp.raise_for_status()
    data = resp.json()
    return [
        np.array(item["data"]).reshape(item["shape"])
        for item in data["outputs"]
    ]


def detect_faces(img_bgr, endpoint: str, conf_threshold: float = 0.25):
    """End-to-end: preprocess, infer via REST, postprocess."""
    blob, scale = preprocess(img_bgr)
    response = send_request(blob, endpoint)
    return postprocess(response[0], scale, img_bgr, conf_threshold)
