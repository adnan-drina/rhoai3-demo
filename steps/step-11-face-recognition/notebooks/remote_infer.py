"""Helper functions for face recognition inference via OpenVINO Model Server (KServe v2 API).

Used by notebooks 04 and 05 to preprocess images, send inference requests
to the served ONNX model, and draw annotated bounding boxes on results.
"""

import requests
import cv2
import cv2.dnn
import numpy as np
from typing import Optional

CLASSES = {
    0: "adnan",
    1: "unknown_face",
}

COLORS = {
    0: (0, 200, 0),      # green for recognized face
    1: (0, 0, 200),      # red for unknown face
}


def preprocess(image_path: str, imgsz: int = 640):
    """Read image, compute scale factor, and create ONNX-compatible blob."""
    original_image = cv2.imread(image_path)
    if original_image is None:
        raise FileNotFoundError(f"Could not read image: {image_path}")
    h, w, _ = original_image.shape
    scale = (h / imgsz, w / imgsz)
    blob = cv2.dnn.blobFromImage(
        original_image, scalefactor=1 / 255, size=(imgsz, imgsz), swapRB=True
    )
    return blob, scale, original_image


def draw_bounding_box(img, class_id, confidence, x, y, x_plus_w, y_plus_h):
    """Draw a labeled bounding box on the image."""
    color = COLORS.get(class_id, (128, 128, 128))
    label = f"{CLASSES.get(class_id, 'unknown')} {confidence:.2f}"
    (label_w, label_h), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
    cv2.rectangle(img, (x, y), (x_plus_w, y_plus_h), color, 2)
    cv2.rectangle(img, (x, y - label_h - 4), (x + label_w, y), color, cv2.FILLED)
    cv2.putText(img, label, (x, y - 2), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)


def postprocess(response_data, scale, original_image, conf_threshold: float = 0.25):
    """Parse ONNX/OpenVINO output tensor, apply NMS, and draw boxes."""
    outputs = np.array([cv2.transpose(response_data[0])])
    rows = outputs.shape[1]

    boxes, scores, class_ids = [], [], []
    for i in range(rows):
        classes_scores = outputs[0][i][4:]
        (_, max_score, _, (_, max_class_idx)) = cv2.minMaxLoc(classes_scores)
        if max_score >= conf_threshold:
            cx, cy, w, h = outputs[0][i][:4]
            box = [cx - 0.5 * w, cy - 0.5 * h, w, h]
            boxes.append(box)
            scores.append(max_score)
            class_ids.append(max_class_idx)

    result_boxes = cv2.dnn.NMSBoxes(boxes, scores, conf_threshold, 0.45, 0.5)
    detections = []

    for idx in result_boxes:
        box = boxes[idx]
        detection = {
            "class_id": class_ids[idx],
            "class_name": CLASSES.get(class_ids[idx], "unknown"),
            "confidence": scores[idx],
            "box": box,
            "scale": scale,
        }
        detections.append(detection)
        draw_bounding_box(
            original_image,
            class_ids[idx],
            scores[idx],
            round(box[0] * scale[1]),
            round(box[1] * scale[0]),
            round((box[0] + box[2]) * scale[1]),
            round((box[1] + box[3]) * scale[0]),
        )
    return original_image, detections


def serialize_for_v2(blob):
    """Serialize a preprocessed image blob for the KServe v2 inference API."""
    return {
        "inputs": [
            {
                "name": "images",
                "shape": list(blob.shape),
                "datatype": "FP32",
                "data": blob.flatten().tolist(),
            }
        ]
    }


def send_request(blob, endpoint: str):
    """Send an inference request to a KServe v2 endpoint."""
    payload = serialize_for_v2(blob)
    raw_response = requests.post(endpoint, json=payload, timeout=30)
    try:
        response = raw_response.json()
    except Exception:
        raise RuntimeError(
            f"Failed to deserialize response.\n"
            f"Status: {raw_response.status_code}\nBody: {raw_response.text}"
        )

    try:
        model_output = response["outputs"]
    except KeyError:
        raise RuntimeError(f"No 'outputs' in response: {response}")

    return [
        np.array(item["data"]).reshape(item["shape"]) for item in model_output
    ]


def process_image(image_path: str, endpoint: str, conf_threshold: float = 0.25):
    """End-to-end: preprocess, infer via REST, postprocess, and return annotated image."""
    blob, scale, original_image = preprocess(image_path)
    response = send_request(blob, endpoint)
    annotated, detections = postprocess(response[0], scale, original_image, conf_threshold)
    return annotated, detections


def process_video_local(video_path: str, model, output_path: Optional[str] = None, conf: float = 0.5):
    """Process a video using a local YOLO model and save annotated output.

    Args:
        video_path: Path to input video.
        model: A loaded ultralytics YOLO model.
        output_path: Path for annotated output video. If None, auto-generated.
        conf: Confidence threshold.

    Returns:
        Path to the output video.
    """
    import os
    if output_path is None:
        base, ext = os.path.splitext(video_path)
        output_path = f"{base}_annotated{ext}"

    cap = cv2.VideoCapture(video_path)
    fps = int(cap.get(cv2.CAP_PROP_FPS))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(output_path, fourcc, fps, (w, h))

    frame_count = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        results = model.predict(frame, conf=conf, verbose=False)
        annotated = results[0].plot()
        writer.write(annotated)

        frame_count += 1
        if frame_count % 30 == 0:
            print(f"  Processed {frame_count}/{total} frames...")

    cap.release()
    writer.release()
    print(f"  Done: {frame_count} frames -> {output_path}")
    return output_path
