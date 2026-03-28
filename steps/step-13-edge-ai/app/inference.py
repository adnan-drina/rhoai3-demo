"""Edge inference helpers for face recognition via KServe v2 gRPC API.

Uses tritonclient gRPC for low-latency inference. Includes identity
uniqueness constraint: a known person can only appear once per frame.
Works with both OpenVINO Model Server and NVIDIA Triton.
"""

import cv2
import cv2.dnn
import numpy as np
import tritonclient.grpc as grpcclient

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


def enforce_identity_uniqueness(detections, identity_class_id=0):
    """Keep only the highest-confidence detection per known identity.

    A known person cannot physically appear twice in the same image,
    so duplicate detections are reclassified as unknown_face.
    """
    identity_dets = [d for d in detections if d["class_id"] == identity_class_id]
    if len(identity_dets) > 1:
        best = max(identity_dets, key=lambda d: d["confidence"])
        for d in identity_dets:
            if d is not best:
                d["class_id"] = 1
                d["class_name"] = CLASSES.get(1, "unknown_face")
    return detections


def postprocess(response_data, scale, img_bgr, conf_threshold: float = 0.7):
    """Parse ONNX output tensor, apply NMS + identity uniqueness, draw boxes."""
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

    for idx in result_boxes:
        box = boxes[idx]
        cid = class_ids[idx]
        conf = scores[idx]
        detections.append({
            "class_id": cid,
            "class_name": CLASSES.get(cid, "unknown"),
            "confidence": float(conf),
            "box": box,
            "scale": scale,
        })

    detections = enforce_identity_uniqueness(detections)

    annotated = img_bgr.copy()
    for det in detections:
        box = det["box"]
        cid = det["class_id"]
        conf = det["confidence"]
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


_clients = {}


def _get_client(endpoint: str):
    """Reuse gRPC client connections across requests."""
    if endpoint not in _clients:
        _clients[endpoint] = grpcclient.InferenceServerClient(url=endpoint)
    return _clients[endpoint]


def send_request(blob, endpoint: str, model_name: str):
    """Send inference via KServe v2 gRPC."""
    client = _get_client(endpoint)

    input_tensor = grpcclient.InferInput("images", list(blob.shape), "FP32")
    input_tensor.set_data_from_numpy(blob.astype(np.float32))

    output_tensor = grpcclient.InferRequestedOutput("output0")

    result = client.infer(
        model_name=model_name,
        inputs=[input_tensor],
        outputs=[output_tensor],
    )

    return [result.as_numpy("output0")]


def detect_faces(img_bgr, endpoint: str, model_name: str, conf_threshold: float = 0.7):
    """End-to-end: preprocess, infer via gRPC, postprocess with identity uniqueness."""
    blob, scale = preprocess(img_bgr)
    response = send_request(blob, endpoint, model_name)
    return postprocess(response[0], scale, img_bgr, conf_threshold)
