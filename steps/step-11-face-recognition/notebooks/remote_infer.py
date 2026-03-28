"""Helper functions for face recognition inference via OpenVINO Model Server (KServe v2 API).

Used by notebooks 03, 04, and the Streamlit app to preprocess images, send
inference requests to the served ONNX model, draw annotated bounding boxes,
and apply identity uniqueness constraints on results.
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


def enforce_identity_uniqueness(detections, identity_class_id=0):
    """Apply identity uniqueness constraint: one person can only appear once per frame.

    For the identified class (adnan), keeps only the highest-confidence detection
    and reclassifies duplicates as unknown_face. This is a standard domain-constrained
    post-processing technique used in identity-aware detection systems — a known person
    cannot physically appear twice in the same image, so any duplicate detection is
    guaranteed to be a false positive.

    Args:
        detections: List of detection dicts with 'class_id' and 'confidence' keys.
        identity_class_id: The class ID for the known identity (default: 0 = adnan).

    Returns:
        The detections list with duplicates reclassified.
    """
    identity_dets = [d for d in detections if d["class_id"] == identity_class_id]
    if len(identity_dets) > 1:
        best = max(identity_dets, key=lambda d: d["confidence"])
        for d in identity_dets:
            if d is not best:
                d["class_id"] = 1
                d["class_name"] = CLASSES.get(1, "unknown_face")
    return detections


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


def postprocess(response_data, scale, original_image, conf_threshold: float = 0.6):
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

    # Apply identity uniqueness constraint before drawing boxes
    detections = enforce_identity_uniqueness(detections)

    for det in detections:
        box = det["box"]
        draw_bounding_box(
            original_image,
            det["class_id"],
            det["confidence"],
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


def process_image(image_path: str, endpoint: str, conf_threshold: float = 0.6):
    """End-to-end: preprocess, infer via REST, postprocess, and return annotated image."""
    blob, scale, original_image = preprocess(image_path)
    response = send_request(blob, endpoint)
    annotated, detections = postprocess(response[0], scale, original_image, conf_threshold)
    return annotated, detections


def _to_h264(input_path: str) -> str:
    """Re-encode video to H.264 for HTML5 inline playback."""
    import subprocess, os
    h264_path = input_path.replace(".mp4", "_h264.mp4")
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", input_path, "-c:v", "libx264", "-preset", "fast",
         "-crf", "23", "-c:a", "aac", "-movflags", "+faststart", h264_path],
        capture_output=True, text=True
    )
    if result.returncode == 0 and os.path.exists(h264_path):
        os.replace(h264_path, input_path)
    return input_path


def process_video_local(video_path: str, model, output_path: Optional[str] = None, conf: float = 0.6):
    """Process a video using a local YOLO model with identity uniqueness constraint.

    Each frame is run through the model, then enforce_identity_uniqueness()
    ensures at most one "adnan" detection per frame. Annotated frames are
    reassembled into an H.264 video for browser playback.

    Args:
        video_path: Path to input video.
        model: A loaded ultralytics YOLO model.
        output_path: Path for annotated output video. If None, auto-generated.
        conf: Confidence threshold (default: 0.6).

    Returns:
        Path to the output video (H.264 encoded for browser playback).
    """
    import os
    if output_path is None:
        base = os.path.splitext(video_path)[0]
        output_path = f"{base}_annotated.mp4"

    cap = cv2.VideoCapture(video_path)
    fps = int(cap.get(cv2.CAP_PROP_FPS))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(output_path, fourcc, fps, (w, h))

    frame_count = 0
    dedup_count = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        results = model.predict(frame, conf=conf, verbose=False)

        # Apply identity uniqueness per frame
        for result in results:
            boxes = result.boxes
            if boxes is not None and len(boxes) > 0:
                cls = boxes.cls.cpu().numpy()
                confs = boxes.conf.cpu().numpy()
                adnan_idx = [i for i, c in enumerate(cls) if int(c) == 0]
                if len(adnan_idx) > 1:
                    best = max(adnan_idx, key=lambda i: confs[i])
                    new_data = boxes.data.clone()
                    for idx in adnan_idx:
                        if idx != best:
                            new_data[idx, 5] = 1
                    result.boxes = type(boxes)(new_data, result.orig_shape)
                    dedup_count += 1

        annotated = results[0].plot()
        writer.write(annotated)

        frame_count += 1
        if frame_count % 30 == 0:
            print(f"  Processed {frame_count}/{total} frames...")

    cap.release()
    writer.release()
    if dedup_count > 0:
        print(f"  Identity dedup applied on {dedup_count}/{frame_count} frames")
    print(f"  Done: {frame_count} frames")
    print("  Converting to H.264 for browser playback...")
    output_path = _to_h264(output_path)
    print(f"  Saved: {output_path}")
    return output_path


def process_video_rest(video_path: str, endpoint: str, output_path: Optional[str] = None, conf_threshold: float = 0.6):
    """Process a video frame-by-frame via the KServe REST API.

    Args:
        video_path: Path to input video.
        endpoint: KServe v2 infer endpoint URL.
        output_path: Path for annotated output video. If None, auto-generated.
        conf_threshold: Confidence threshold.

    Returns:
        Path to the output video (H.264 encoded for browser playback).
    """
    import os
    if output_path is None:
        base = os.path.splitext(video_path)[0]
        output_path = f"{base}_server_annotated.mp4"

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

        tmp_frame = "/tmp/current_frame.jpg"
        cv2.imwrite(tmp_frame, frame)

        try:
            annotated, _ = process_image(tmp_frame, endpoint, conf_threshold)
            writer.write(annotated)
        except Exception:
            writer.write(frame)

        frame_count += 1
        if frame_count % 30 == 0:
            print(f"  Processed {frame_count}/{total} frames...")

    cap.release()
    writer.release()
    print(f"  Done: {frame_count} frames")
    print("  Converting to H.264 for browser playback...")
    output_path = _to_h264(output_path)
    print(f"  Saved: {output_path}")
    return output_path
