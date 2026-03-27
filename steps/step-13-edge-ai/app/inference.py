"""Edge inference helpers for face recognition via KServe v2 API.

Derived from step-11 remote_infer.py, adapted for the edge camera app.
Uses the KServe v2 Binary Tensor Extension to avoid JSON serialization
of large float arrays (~400ms saved per request).
Ref: https://kserve.github.io/website/docs/concepts/architecture/data-plane/v2-protocol/binary-tensor-data-extension
"""

import json

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
    """Send inference using KServe v2 Binary Tensor Extension.

    Instead of serializing 1.2M floats as a JSON array (~12 MB, ~400ms),
    sends the tensor as raw bytes (~5 MB, ~10ms serialization).
    Falls back to JSON if the binary extension is not supported.
    """
    tensor_bytes = np.ascontiguousarray(blob, dtype=np.float32).tobytes()

    json_header = json.dumps({
        "inputs": [{
            "name": "images",
            "shape": list(blob.shape),
            "datatype": "FP32",
            "parameters": {"binary_data_size": len(tensor_bytes)},
        }],
        "parameters": {"binary_data_output": True},
    })

    json_bytes = json_header.encode("utf-8")
    body = json_bytes + tensor_bytes

    resp = requests.post(
        endpoint,
        data=body,
        headers={
            "Content-Type": "application/octet-stream",
            "Inference-Header-Content-Length": str(len(json_bytes)),
        },
        timeout=timeout,
    )
    resp.raise_for_status()

    header_length_str = resp.headers.get("Inference-Header-Content-Length")
    if header_length_str:
        header_length = int(header_length_str)
        resp_json = json.loads(resp.content[:header_length])
        binary_data = resp.content[header_length:]

        outputs = []
        offset = 0
        for output in resp_json["outputs"]:
            shape = output["shape"]
            bin_size = output.get("parameters", {}).get("binary_data_size", 0)
            if bin_size > 0:
                tensor = np.frombuffer(
                    binary_data[offset : offset + bin_size], dtype=np.float32
                ).reshape(shape)
                offset += bin_size
            else:
                tensor = np.array(output["data"]).reshape(shape)
            outputs.append(tensor)
        return outputs

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
